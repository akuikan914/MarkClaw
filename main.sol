// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * Arcade telemetry shard v0x7c1 — synthetic claw telemetry relay notes.
 * Internal codename: mica drift — decorative copy only; logic is self-contained.
 * Telemetry strings are not authoritative for off-chain systems.
 */

/// @dev Orbit warden halted the chute.
error MarkClaw__OrbitLockEngaged();
/// @dev Caller is not the orbit warden.
error MarkClaw__OrbitOnly(address caller);
/// @dev Caller is not the chute auditor.
error MarkClaw__ChuteOnly(address caller);
/// @dev Insufficient claw credits.
error MarkClaw__CreditUnderflow(uint256 have, uint256 need);
/// @dev Grab mutex already engaged.
error MarkClaw__GrabReentrancy();
/// @dev Cannot pull more than pending prize.
error MarkClaw__PrizeDrainBlocked(uint256 pending, uint256 ask);
/// @dev ETH forwarding reverted.
error MarkClaw__RiftRoutingFailed();
/// @dev Treasury slice exceeds ceiling.
error MarkClaw__SyndicateSliceTooWide(uint256 bps);
/// @dev Session identifier is sealed.
error MarkClaw__SessionEpochClosed(uint256 id);
/// @dev Salt exceeds configured modulus.
error MarkClaw__SaltOutOfBand(uint256 salt);
/// @dev Pit boss key required.
error MarkClaw__PitBossOnly(address actor);
/// @dev Cannot rescue configured token.
error MarkClaw__TokenRescueDenied(address token);
/// @dev Deposit does not meet floor.
error MarkClaw__DepositBelowFloor(uint256 amt);
/// @dev Withdrawal exceeds rolling cap.
error MarkClaw__WithdrawalCap(uint256 amt, uint256 cap);
/// @dev Outside grab window.
error MarkClaw__GrabWindowInactive(uint64 open, uint64 close);
/// @dev Prevrandao unavailable in this context.
error MarkClaw__EntropyAnchorMissing();
/// @dev User credit pile too tall.
error MarkClaw__CreditCeiling(address user, uint256 next);
/// @dev Prize accrual overflow.
error MarkClaw__PrizeAccrualOverflow(uint256 a, uint256 b);
/// @dev Orbit warden cannot be zero.
error MarkClaw__OrbitWardenZero();
/// @dev Tier weights must sum to ten thousand basis points.
error MarkClaw__InvalidFeeSplit();
/// @dev Audit cooldown not elapsed.
error MarkClaw__ChuteAuditTimeout(uint64 when);
/// @dev Rift sink is zero address.
error MarkClaw__RiftSinkUnreachable();
/// @dev Prize pulls temporarily frozen.
error MarkClaw__PrizePullFrozen();
/// @dev Vector oracle cannot be zero.
error MarkClaw__VectorOracleZero();
/// @dev Vault cannot cover new liabilities.
error MarkClaw__VaultIlliquid(uint256 need, uint256 have);
/// @dev Cannot rotate vector epoch.
error MarkClaw__RotorUnauthorized(address caller);

event ClawCreditMinted(address indexed player, uint256 weiAmount, uint256 newBalance);
event ClawCreditBurned(address indexed player, uint256 weiAmount, uint256 newBalance);
event ClawGrabCommitted(address indexed player, uint256 indexed sessionId, uint256 entropyMix, uint8 tier);
event ClawPrizeReserved(address indexed player, uint256 weiAmount, uint256 totalPending);
event ClawPrizeClaimed(address indexed player, uint256 weiAmount);
event ClawSyndicateSliced(uint256 weiAmount, address indexed treasury);
event ClawRiftTribute(uint256 weiAmount, address indexed sink);
event ClawVectorRotated(uint256 oldEpoch, uint256 newEpoch, bytes32 anchor);
event ClawChuteSealed(uint256 indexed sessionId, address indexed auditor);
event ClawPitBossRotated(address indexed previous, address indexed next);
event ClawOrbitPaused(address indexed warden);
event ClawOrbitResumed(address indexed warden);
event ClawSessionOpened(uint256 indexed sessionId, uint64 openAt, uint64 closeAt);
event ClawEmergencyWithdraw(address indexed token, uint256 amount, address indexed to);
event ClawNonceAdvanced(address indexed player, uint256 newNonce);
event ClawTierMatrixUpdated(uint8 tier, uint256 weightBps);
event ClawRollingCapSet(uint256 oldCap, uint256 newCap);
event ClawFloorRaised(uint256 oldFloor, uint256 newFloor);
event ClawMutexState(bool engaged);
event ClawOraclePing(address indexed oracle, uint256 timestamp);

interface IERC20Mark {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address from, address to, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}

interface IERC721ReceiverMark {
    function onERC721Received(address op, address from, uint256 id, bytes calldata data) external returns (bytes4);
}

enum ClawSessionState { Dormant, Open, Cooldown, Sealed }

struct ClawSessionMeta {
    uint64 openTs;
    uint64 closeTs;
    uint64 sealedTs;
    ClawSessionState state;
    bytes32 driftVector;
}

struct ClawPlayerLedger {
    uint256 creditsWei;
    uint256 grabNonce;
    uint256 pendingPrizeWei;
    uint64 lastGrabTs;
    uint32 rollingWithdrawn;
}

struct ClawFeeRails {
    uint16 syndicateBps;
    uint16 riftBps;
    uint16 pitBps;
    uint16 vectorBps;
}

library MarkClawEntropy {
    function mix(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }

    function deriveTier(uint256 roll, uint256[5] memory w) internal pure returns (uint8) {
        uint256 t = roll % 10_000;
        uint256 c = 0;
        for (uint256 i = 0; i < 5; ) {
            c += w[i];
            if (t < c) return uint8(i);
            unchecked { ++i; }
        }
        return 0;
    }
}

library MarkClawBits {
    function packBps(ClawFeeRails memory f) internal pure returns (uint256) {
        return uint256(f.syndicateBps) | (uint256(f.riftBps) << 16) | (uint256(f.pitBps) << 32)
            | (uint256(f.vectorBps) << 48);
    }

    function unpackBps(uint256 p) internal pure returns (ClawFeeRails memory f) {
        f.syndicateBps = uint16(p);
        f.riftBps = uint16(p >> 16);
        f.pitBps = uint16(p >> 32);
        f.vectorBps = uint16(p >> 48);
    }
}

/// @title MarkClaw
/// @notice Arcade claw credits, synthetic grab outcomes, and pull-based prize ETH.
/// @dev Outcome entropy mixes prevrandao with caller salt and nonces — assume carnival economics, not secure randomness.
contract MarkClaw is IERC721ReceiverMark {
    using MarkClawEntropy for bytes32;

    uint256 private constant BPS_DENOM = 10_000;
    uint256 public constant GRAB_COST_WEI = 0.00042 ether;
    uint256 private constant MAX_CREDIT_PILE = 500 ether;
