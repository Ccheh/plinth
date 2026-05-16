// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IYieldVenue} from "./interfaces/IYieldVenue.sol";

/// @title  MockYieldVenue — testnet stand-in for a T-bill-style yield strategy
/// @notice Models the "USYC sweep" cash-management pattern: USDC sitting idle
///         in the vault is deployed here, accrues continuous yield at a fixed
///         APR (5% by default), and can be redeemed by the vault's agent when
///         capital is needed elsewhere.
///
///         Architecture mirrors Plinth's existing capability-constraint model:
///         the venue receives USDC from Plinth via the standard `deployToVenue`
///         path (bare ETH-style call), accrues yield on its own, and a venue-
///         level helper (`returnPrincipal`) pushes funds back to Plinth via
///         `returnFromVenue`. The accrued yield is reported as PnL by the
///         agent — exactly the same pattern as Aster L1 trades — and verifiable
///         by reading this contract's `currentBalance()` on chain.
///
///         **This is a testnet mock.** Production replaces this with the real
///         USYC token on Base (or Ethereum/Solana), bridged from Arc via CCTP.
///         See `sdk-ts/examples/yield-strategy.ts` for the production wiring.
///
/// @dev    Pre-fund pattern: the operator deposits some USDC to the reserve
///         via `fundReserve()` at deployment time so yield payouts are
///         actually backed by on-chain funds. Otherwise `returnAll()` would
///         revert when trying to send out principal + accrued yield.
contract MockYieldVenue is IYieldVenue {
    /* ---------------- constants ---------------- */

    /// @notice Annual percentage yield in basis points. 500 = 5.00%.
    uint256 public constant YIELD_BPS = 500;

    /// @notice Seconds per year for the yield calculation (365 days exact).
    uint256 public constant YEAR_SECONDS = 365 days;

    /* ---------------- state ---------------- */

    /// @notice Cumulative principal currently held (excluding accrued yield).
    /// Each `receive()` from Plinth bumps this up. `_settleYield()` rolls
    /// any pending yield into `principal` as a one-time conversion.
    uint256 public principal;

    /// @notice Block timestamp of the most recent state-mutating interaction.
    /// Yield accrues from this point forward at the YIELD_BPS rate.
    uint64 public lastUpdateAt;

    /// @notice Operator address (deployer) — for events only, no privileged ops.
    address public immutable operator;

    /* ---------------- events ---------------- */
    /* `FundsReceived`, `YieldSettled`, `PrincipalReturned` are inherited from IYieldVenue. */

    event ReserveFunded(address indexed from, uint256 amount);

    /* ---------------- construction ---------------- */

    constructor() {
        operator = msg.sender;
        lastUpdateAt = uint64(block.timestamp);
    }

    /* ---------------- inbound capital ---------------- */

    /// @notice Plinth (or anyone) sends USDC via bare call. The first call
    /// from Plinth's `deployToVenue` path lands here.
    receive() external payable {
        _settleYield();
        principal += msg.value;
        emit FundsReceived(msg.sender, msg.value, principal);
    }

    /// @notice Explicit reserve-funding entry point. Operator pre-funds the
    /// venue with extra USDC so yield payouts are backed by real balance.
    /// USDC sent this way does NOT increase `principal` — it goes purely
    /// into reserves.
    function fundReserve() external payable {
        emit ReserveFunded(msg.sender, msg.value);
    }

    /* ---------------- yield math ---------------- */

    /// @notice Yield that has accrued since `lastUpdateAt` but hasn't yet been
    /// rolled into `principal`. Computed simple-interest on `principal`.
    function accruedYield() public view returns (uint256) {
        if (principal == 0) return 0;
        uint256 elapsed = block.timestamp - lastUpdateAt;
        return (principal * YIELD_BPS * elapsed) / (10_000 * YEAR_SECONDS);
    }

    /// @notice Total redeemable balance = principal + accrued yield.
    /// This is what an off-chain Underwriter reads to verify the agent's
    /// reportedPnL on Plinth.
    function currentBalance() external view returns (uint256) {
        return principal + accruedYield();
    }

    /// @notice Principal-only view, matching IYieldVenue.principalBalance.
    function principalBalance() external view returns (uint256) {
        return principal;
    }

    /// @notice IYieldVenue metadata — identifies this as the testnet mock.
    function yieldSource() external pure returns (string memory) {
        return "mock-5pct-apr";
    }

    /// @notice IYieldVenue semver.
    function yieldVenueVersion() external pure returns (string memory) {
        return "0.5.0";
    }

    /// @dev Rolls any pending yield into principal and resets the clock.
    function _settleYield() internal {
        uint256 acc = accruedYield();
        if (acc > 0) {
            principal += acc;
            emit YieldSettled(acc, principal);
        }
        lastUpdateAt = uint64(block.timestamp);
    }

    /* ---------------- outbound capital ---------------- */

    /// @notice Send `amount` USDC back to a Plinth contract by invoking its
    /// `returnFromVenue(bytes32 vaultId, address venue, uint256 amount)`
    /// function. The `amount` MUST equal what was originally deployed (i.e.
    /// only principal can be returned via this path) because Plinth requires
    /// `v.deployedAUM >= amount`. Accrued yield stays in this contract until
    /// the agent harvests it (see `harvestYield`).
    ///
    /// @dev   Anyone can call this — it just forwards funds to a Plinth contract.
    ///        The pattern matches how Hyperliquid / Aster / etc. settlement
    ///        would unwind: external trigger, no privileged access.
    function returnPrincipal(
        address payable plinth,
        bytes32 vaultId,
        uint256 amount,
        bytes4 returnFromVenueSelector
    ) external {
        _settleYield();
        require(amount <= principal, "exceeds tracked principal");
        require(address(this).balance >= amount, "insufficient reserve");
        principal -= amount;
        emit PrincipalReturned(plinth, vaultId, amount);
        (bool ok,) = plinth.call{value: amount}(
            abi.encodeWithSelector(returnFromVenueSelector, vaultId, address(this), amount)
        );
        require(ok, "venue-to-vault return failed");
    }

    /// @notice Sweep accrued yield to a recipient (typically the vault's agent,
    /// who then reports it as PnL on Plinth). Settles yield into principal-form
    /// first, then peels off `amount` from principal. The agent's accounting
    /// logic should:
    ///   1. Read `accruedYield()` to know how much can be harvested
    ///   2. Call `harvestYield(agent, yieldAmount)`
    ///   3. Send that USDC back into Plinth (no clean path — agent's choice
    ///      whether to keep it, redeposit as their own, or absorb as fee)
    ///   4. Call `Plinth.reportPnL(vault, +yieldAmount)` to reflect in NAV
    /// In v0 demos we keep it simple: the on-chain `currentBalance()` is the
    /// ground truth for the Underwriter, and the agent reports yield via PnL
    /// without actually moving the yield USDC out.
    function harvestYield(address payable to, uint256 amount) external {
        _settleYield();
        require(amount <= principal, "exceeds settled balance");
        require(address(this).balance >= amount, "insufficient reserve");
        principal -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "harvest send failed");
    }
}
