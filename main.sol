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
