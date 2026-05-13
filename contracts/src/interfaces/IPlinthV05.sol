// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPlinth} from "./IPlinth.sol";

/// @title  IPlinthV05 — security-hardened Plinth interface
/// @notice Extends IPlinth with additional errors and events introduced by
///         the v0.5 hardening pass (see docs/security-audit.md).
///
///         v0.5 changes vs v0:
///           - deposit cooldown: shares cannot be redeemed within
///             DEPOSIT_COOLDOWN of their minting tx (sandwich defense)
///           - returnFromVenue is restricted to (venue || agent)
///           - reportPnL is bounded: |newPnL| ≤ MAX_PNL_MULTIPLE × capital
///             and |Δ PnL| ≤ PNL_RATE_PCT × capital per PNL_RATE_WINDOW
///           - reportPnL is rejected on Closed vaults
///           - strategyDescriptor is bounded to MAX_STRATEGY_LEN bytes
///
///         All v0 invariants (capability constraint, no agent withdraw,
///         no admin keys) are retained verbatim.
interface IPlinthV05 is IPlinth {
    /* ------------------------------ new errors ------------------------ */

    /// @notice Caller is not the venue or the vault's agent. Replaces v0's
    ///         open-access on returnFromVenue.
    error NotAuthorized();

    /// @notice Shares minted by this user have not yet vested. Wait until
    ///         `lastDepositAt[vaultId][user] + DEPOSIT_COOLDOWN`.
    error SharesPendingVesting();

    /// @notice newPnL magnitude exceeds MAX_PNL_MULTIPLE × capital.
    error PnLOutOfBounds();

    /// @notice newPnL would change reportedPnL by more than PNL_RATE_PCT
    ///         of capital within PNL_RATE_WINDOW since last report.
    error PnLRateLimitExceeded();

    /// @notice strategyDescriptor exceeds MAX_STRATEGY_LEN bytes.
    error StrategyDescriptorTooLong();
}
