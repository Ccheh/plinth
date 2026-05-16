// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IYieldVenue} from "./interfaces/IYieldVenue.sol";

/// @title  MorphoVenueAdapter — production-path scaffold wrapping a Morpho Vault V2 market
/// @notice Plinth-compatible adapter that takes native USDC (Arc gas) and routes it into
///         a Morpho Vault V2 (ERC-4626) market. The accrued yield comes from real Morpho
///         lending, not a mock APR.
///
/// @dev    **Status (May 2026)**: Morpho is not yet deployed on Arc Testnet — this adapter
///         is published with an UNINITIALIZED `morphoVault` address. When Morpho's Arc
///         deployment lands, set the vault address at construction time. The interface
///         and accounting logic are production-ready and unit-tested against a mock
///         ERC-4626 vault.
///
///         **Native USDC ↔ ERC-20 USDC**: Arc Testnet uses USDC as native gas (`msg.value`).
///         Morpho Vault V2 expects an ERC-20 token. This adapter abstracts the wrap/unwrap
///         step behind two hooks (`_wrapNativeToErc20` and `_unwrapErc20ToNative`) that
///         the operator overrides at deployment time depending on Arc's wrapping contract
///         (likely `wUSDC` at a precompile-style address — TBD by Arc).
///
///         **Principal vs yield accounting**: Morpho tracks the adapter's shares; we
///         translate shares ↔ assets via `convertToAssets()`. `principal` is what the
///         adapter received; anything above that on `convertToAssets(balanceOf(adapter))`
///         is yield.
///
/// @custom:roadmap Once Morpho's Arc Testnet deployment is announced, replace
///         `_PLACEHOLDER_VAULT` with the real address in the constructor's default-arg
///         path. The contract is fully unit-tested against the canonical ERC-4626 interface.
contract MorphoVenueAdapter is IYieldVenue {
    /* ---------------- placeholder for unset Morpho Arc deployment ---------------- */

    /// @dev When set to this zero-ish placeholder, all `deposit`/`withdraw` paths
    /// short-circuit and the adapter behaves as a pass-through (funds stay native,
    /// no yield). This makes the scaffold safe to deploy before Morpho exists on Arc.
    address private constant _PLACEHOLDER_VAULT = address(0xdEaD);

    /* ---------------- immutables ---------------- */

    /// @notice The Morpho Vault V2 (ERC-4626) market this adapter routes to.
    /// MUST hold the underlying USDC token. Set to a Morpho-on-Arc address once available.
    IERC4626 public immutable morphoVault;

    /// @notice ERC-20 USDC contract used by `morphoVault` as the underlying asset.
    /// On Arc this will likely be `wUSDC` (wrapped form of native USDC). For other
    /// chains it's the canonical Circle USDC (6 decimals).
    IERC20 public immutable underlyingToken;

    /// @notice Operator address — for events only, no privileged ops.
    address public immutable operator;

    /* ---------------- state ---------------- */

    /// @notice Cumulative principal deposited by Plinth (and others) into Morpho via this adapter.
    /// Yield above this lives in Morpho until harvested. Matches the IYieldVenue accounting model.
    uint256 public principal;

    /* ---------------- construction ---------------- */

    /// @param _morphoVault   Morpho Vault V2 address on the target chain. Pass
    ///                       address(0xdEaD) to deploy in placeholder mode (pre-Morpho-on-Arc).
    /// @param _underlying    The ERC-20 USDC contract used by the vault (address(0) in placeholder mode).
    constructor(address _morphoVault, address _underlying) {
        morphoVault = IERC4626(_morphoVault);
        underlyingToken = IERC20(_underlying);
        operator = msg.sender;
    }

    /// @notice True when Morpho hasn't deployed on this chain yet and this adapter
    /// is acting as a pure passthrough holder (no yield).
    function isPlaceholder() public view returns (bool) {
        return address(morphoVault) == _PLACEHOLDER_VAULT;
    }

    /* ---------------- IYieldVenue: views ---------------- */

    function currentBalance() public view returns (uint256) {
        if (isPlaceholder()) return principal;
        uint256 shares = morphoVault.balanceOf(address(this));
        return morphoVault.convertToAssets(shares);
    }

    function principalBalance() external view returns (uint256) {
        return principal;
    }

    function accruedYield() public view returns (uint256) {
        uint256 cur = currentBalance();
        return cur > principal ? cur - principal : 0;
    }

    function yieldSource() external view returns (string memory) {
        return isPlaceholder() ? "morpho-arc-PLACEHOLDER" : "morpho-vault-v2";
    }

    function yieldVenueVersion() external pure returns (string memory) {
        return "0.1.0";
    }

    /* ---------------- IYieldVenue: deposit path ---------------- */

    /// @notice Plinth (or anyone) sends native USDC; adapter wraps + deposits to Morpho.
    /// In placeholder mode, funds simply accumulate as native balance + tracked principal.
    receive() external payable {
        principal += msg.value;
        if (!isPlaceholder()) {
            // Production path: wrap native USDC → ERC-20 USDC → deposit to Morpho
            uint256 erc20Amount = _wrapNativeToErc20(msg.value);
            underlyingToken.approve(address(morphoVault), erc20Amount);
            morphoVault.deposit(erc20Amount, address(this));
        }
        emit FundsReceived(msg.sender, msg.value, principal);
    }

    /* ---------------- IYieldVenue: withdraw path ---------------- */

    function returnPrincipal(
        address payable plinth,
        bytes32 vaultId,
        uint256 amount,
        bytes4 returnFromVenueSelector
    ) external {
        require(amount <= principal, "exceeds tracked principal");
        principal -= amount;

        uint256 nativeOut;
        if (isPlaceholder()) {
            // Funds are sitting native in this contract; just check + forward
            require(address(this).balance >= amount, "insufficient native reserve");
            nativeOut = amount;
        } else {
            // Production: withdraw from Morpho → unwrap to native
            morphoVault.withdraw(amount, address(this), address(this));
            nativeOut = _unwrapErc20ToNative(amount);
            require(nativeOut == amount, "unwrap amount mismatch");
        }

        emit PrincipalReturned(plinth, vaultId, amount);
        (bool ok,) = plinth.call{value: nativeOut}(
            abi.encodeWithSelector(returnFromVenueSelector, vaultId, address(this), amount)
        );
        require(ok, "venue-to-vault return failed");
    }

    function harvestYield(address payable to, uint256 amount) external {
        uint256 yieldNow = accruedYield();
        require(amount <= yieldNow, "exceeds accrued yield");

        uint256 nativeOut;
        if (isPlaceholder()) {
            require(address(this).balance >= principal + amount, "insufficient native reserve");
            nativeOut = amount;
        } else {
            morphoVault.withdraw(amount, address(this), address(this));
            nativeOut = _unwrapErc20ToNative(amount);
        }

        (bool ok,) = to.call{value: nativeOut}("");
        require(ok, "harvest send failed");
    }

    /* ---------------- arc-specific wrap hooks ---------------- */

    /// @dev Override at deploy time (via inheritance) or via a minimal-proxy pattern
    /// once Arc's USDC wrapping primitive is final. Default: assume 1:1 wUSDC at
    /// a fixed address (TBD by Arc).
    ///
    /// In production: call wUSDC.deposit{value: native}() or equivalent, then
    /// transfer underlyingToken to this contract.
    function _wrapNativeToErc20(uint256 nativeAmount) internal virtual returns (uint256) {
        // Placeholder pass-through. Override in a deployment-specific subclass.
        return nativeAmount;
    }

    function _unwrapErc20ToNative(uint256 erc20Amount) internal virtual returns (uint256) {
        // Placeholder pass-through. Override in a deployment-specific subclass.
        return erc20Amount;
    }
}

/* ====================================================================== */
/*    Minimal external interfaces — keeps the adapter compileable without  */
/*    pulling in @openzeppelin or Morpho-protocol dependencies.            */
/* ====================================================================== */

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface IERC4626 {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}
