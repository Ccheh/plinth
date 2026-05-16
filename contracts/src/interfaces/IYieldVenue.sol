// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  IYieldVenue — standard interface for yield-strategy venues approved by a Plinth vault
/// @notice Plinth vaults can deploy idle USDC to any contract that implements this interface.
///         The interface is intentionally minimal: it expresses the Plinth-side capability
///         constraint model (capital flows in via `receive()`, flows out via `returnPrincipal()`),
///         and exposes the views that an off-chain Underwriter needs to reconcile the agent's
///         `reportPnL` on Plinth.
///
/// @dev    Adapters that implement this interface wrap real yield protocols:
///           - `MorphoVenueAdapter`  → wraps a Morpho Vault V2 (ERC-4626) market
///           - `AaveVenueAdapter`    → wraps an Aave aToken pool
///           - `MockYieldVenue`      → testnet stand-in with fixed 5% APR (default v0.5 deployment)
///
///         The "principal vs yield" split is a Plinth-specific accounting convention:
///         `returnPrincipal()` returns ONLY the originally-deployed capital (so Plinth's
///         `v.deployedAUM >= amount` invariant holds), and `harvestYield()` peels off
///         accrued returns separately. Real protocols don't make this distinction at the
///         protocol level, but the adapter tracks it via `principal` storage.
///
///         **Native-USDC note**: On Arc, USDC is native gas (msg.value), so `receive()` is
///         the inbound path. Adapters that wrap protocols expecting ERC-20 USDC handle the
///         wrap/unwrap internally — implementers MUST document this in their NatSpec.
interface IYieldVenue {
    /* ---------------------------- events ---------------------------- */

    event FundsReceived(address indexed from, uint256 amount, uint256 newPrincipal);
    event YieldSettled(uint256 yieldAccrued, uint256 newPrincipal);
    event PrincipalReturned(address indexed plinth, bytes32 indexed vaultId, uint256 amount);

    /* --------------------------- views ----------------------------- */

    /// @notice Total redeemable balance under this adapter's control.
    /// Returns `principalBalance() + accruedYield()`. This is the value an
    /// off-chain Underwriter reconciles against the agent's `reportPnL`.
    function currentBalance() external view returns (uint256);

    /// @notice The amount of USDC originally deployed by the Plinth vault
    /// (or by other depositors) and still under management. Excludes
    /// any yield earned. Used to enforce Plinth's `deployedAUM` invariant.
    function principalBalance() external view returns (uint256);

    /// @notice Yield earned on top of `principalBalance()` since the last
    /// `_settleYield()` interaction. Computed at the underlying protocol.
    /// In a Morpho/Aave adapter this is read from the protocol; in
    /// MockYieldVenue it's computed as simple interest.
    function accruedYield() external view returns (uint256);

    /// @notice Human-readable identifier of the underlying protocol.
    /// E.g. "mock-5pct-apr", "morpho-arc-usdc-v2", "aave-arc-usdc".
    function yieldSource() external view returns (string memory);

    /// @notice Semver of the adapter contract itself.
    function yieldVenueVersion() external pure returns (string memory);

    /* --------------------------- writes ---------------------------- */

    /// @notice Return `amount` USDC to a Plinth contract via its `returnFromVenue`
    /// entry-point. The caller passes Plinth's contract address + the relevant
    /// vault id + the `returnFromVenue(bytes32,address,uint256)` selector so the
    /// adapter is venue-version-agnostic (works with both Plinth v0 and v0.5).
    ///
    /// MUST send exactly `amount` of native USDC to `plinth` and MUST decrease
    /// `principalBalance()` by `amount`. Yield is unaffected (use `harvestYield`
    /// to peel that off).
    function returnPrincipal(
        address payable plinth,
        bytes32 vaultId,
        uint256 amount,
        bytes4 returnFromVenueSelector
    ) external;

    /// @notice Sweep `amount` of accrued yield to recipient `to`. The agent
    /// then reports this as positive PnL on Plinth via `reportPnL(vaultId, +amount)`.
    /// Caller is typically the agent; adapters MAY restrict this further.
    function harvestYield(address payable to, uint256 amount) external;
}
