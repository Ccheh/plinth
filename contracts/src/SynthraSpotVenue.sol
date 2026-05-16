// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  SynthraSpotVenue — Plinth-compatible adapter wrapping Synthra v3 spot AMM (Arc-native)
/// @notice Plinth vaults approve this contract as a venue. The agent calls `swap(...)` to route
///         USDC ↔ other tokens through Synthra's v3 SwapRouter on Arc Testnet. Off-chain
///         Underwriter (a `SynthraSpotVerifier` — sibling to AsterVerifier) reads Synthra v3
///         `Swap` events to reconcile the agent's reportedPnL on Plinth.
///
///         This is the **Arc-native** answer to Aster L1's cross-chain perp venue: same
///         capability-not-custody pattern, no cross-chain hop, faster reconciliation.
///
/// @dev    **Architecture**: identical to MorphoVenueAdapter — placeholder mode + production mode.
///         The constructor takes a `_swapRouter` address; pass `address(0xdEaD)` for placeholder
///         (used when Synthra's spot SwapRouter on Arc Testnet hasn't been verified by the
///         operator yet, or for local testing). In placeholder mode, all swap calls revert
///         loudly so misuse is obvious; funds stay native and `returnPrincipal()` works.
///
///         **Native USDC ↔ ERC-20 USDC**: Arc Testnet uses USDC as native gas. Synthra v3
///         (a Uniswap v3 fork) expects ERC-20 tokens. The wrap/unwrap is delegated to
///         overridable hooks (`_wrapNativeToErc20Usdc` / `_unwrapErc20UsdcToNative`) that
///         the operator implements for the chain's specific wrapping contract.
///
///         **Why no formal interface?**: The "spot trading venue" surface is the agent's
///         freedom to swap tokens. There's no universally-shared event schema across DEXes
///         (Uniswap v3, Curve, Balancer all differ). Plinth simply requires `receive() payable`
///         + `returnPrincipal()`, which any venue contract — including this one — exposes.
///
/// @custom:roadmap When Synthra spot SwapRouter is verified on Arc Testnet, pass the
///         real address at construction and the placeholder gate flips off.
contract SynthraSpotVenue {
    /* ---------------- placeholder for unset Synthra deployment ---------------- */

    address private constant _PLACEHOLDER_ROUTER = address(0xdEaD);

    /* ---------------- immutables ---------------- */

    /// @notice Synthra v3 SwapRouter02 address on Arc. Set to address(0xdEaD) in placeholder mode.
    ISwapRouter02 public immutable swapRouter;

    /// @notice ERC-20 USDC on Arc (the form Synthra v3 expects). On Arc this is the wrapped
    /// form of native USDC. Set to address(0) in placeholder mode.
    IERC20 public immutable usdcToken;

    /// @notice Agent address allowed to initiate swaps. Investors can never trigger trades.
    address public immutable agent;

    /// @notice Operator (deployer) — events only, no privileged ops.
    address public immutable operator;

    /* ---------------- state ---------------- */

    /// @notice Cumulative principal received (native USDC value). Used for Plinth's
    /// deployedAUM invariant — returnPrincipal() can never return more than this.
    /// Yield (or losses) above/below `principal` are realized by the agent reporting
    /// PnL on Plinth based on the venue's current token holdings.
    uint256 public principal;

    /* ---------------- events ---------------- */

    event FundsReceived(address indexed from, uint256 amount, uint256 newPrincipal);
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint24 fee
    );
    event PrincipalReturned(address indexed plinth, bytes32 indexed vaultId, uint256 amount);

    /* ---------------- errors ---------------- */

    error NotAgent();
    error PlaceholderMode();
    error InsufficientReserve();
    error ExceedsPrincipal();
    error SwapFailed();

    /* ---------------- construction ---------------- */

    /// @param _swapRouter  Synthra v3 SwapRouter02 address (address(0xdEaD) for placeholder).
    /// @param _usdcToken   ERC-20 USDC contract Synthra uses (address(0) in placeholder mode).
    /// @param _agent       Address authorized to initiate swaps via this venue.
    constructor(address _swapRouter, address _usdcToken, address _agent) {
        swapRouter = ISwapRouter02(_swapRouter);
        usdcToken = IERC20(_usdcToken);
        agent = _agent;
        operator = msg.sender;
    }

    function isPlaceholder() public view returns (bool) {
        return address(swapRouter) == _PLACEHOLDER_ROUTER;
    }

    /* ---------------- inbound capital ---------------- */

    /// @notice Plinth sends native USDC; venue tracks principal.
    /// In placeholder mode, funds simply hold as native balance.
    /// In production mode, native is held until the agent calls swap().
    receive() external payable {
        principal += msg.value;
        emit FundsReceived(msg.sender, msg.value, principal);
    }

    /* ---------------- trading surface ---------------- */

    /// @notice Agent-initiated swap: USDC → tokenOut via Synthra v3.
    /// @param tokenOut       Target token (must be a token Synthra has liquidity for).
    /// @param fee            Synthra v3 pool fee tier (e.g. 500 = 0.05%, 3000 = 0.30%, 10000 = 1%).
    /// @param amountIn       Native USDC to swap.
    /// @param minAmountOut   Slippage protection — minimum tokenOut acceptable.
    function swapUsdcToToken(
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        if (msg.sender != agent) revert NotAgent();
        if (isPlaceholder()) revert PlaceholderMode();
        if (amountIn > address(this).balance) revert InsufficientReserve();

        uint256 erc20Amount = _wrapNativeToErc20Usdc(amountIn);
        usdcToken.approve(address(swapRouter), erc20Amount);

        amountOut = swapRouter.exactInputSingle(ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(usdcToken),
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            amountIn: erc20Amount,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        }));

        if (amountOut < minAmountOut) revert SwapFailed();
        emit SwapExecuted(address(usdcToken), tokenOut, erc20Amount, amountOut, fee);
    }

    /// @notice Agent-initiated swap back: tokenIn → USDC via Synthra v3.
    /// Used to liquidate positions before returning principal to Plinth.
    function swapTokenToUsdc(
        address tokenIn,
        uint24 fee,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        if (msg.sender != agent) revert NotAgent();
        if (isPlaceholder()) revert PlaceholderMode();

        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        uint256 erc20Out = swapRouter.exactInputSingle(ISwapRouter02.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: address(usdcToken),
            fee: fee,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        }));

        if (erc20Out < minAmountOut) revert SwapFailed();
        // Unwrap ERC-20 USDC back to native for Plinth-compatible return path
        amountOut = _unwrapErc20UsdcToNative(erc20Out);
        emit SwapExecuted(tokenIn, address(usdcToken), amountIn, amountOut, fee);
    }

    /* ---------------- outbound capital ---------------- */

    /// @notice Send `amount` USDC back to Plinth via its `returnFromVenue` entry point.
    /// MUST be called with venue holding sufficient native USDC (the agent should
    /// have swapped back any non-USDC holdings first via `swapTokenToUsdc`).
    function returnPrincipal(
        address payable plinth,
        bytes32 vaultId,
        uint256 amount,
        bytes4 returnFromVenueSelector
    ) external {
        if (amount > principal) revert ExceedsPrincipal();
        if (address(this).balance < amount) revert InsufficientReserve();
        principal -= amount;
        emit PrincipalReturned(plinth, vaultId, amount);
        (bool ok,) = plinth.call{value: amount}(
            abi.encodeWithSelector(returnFromVenueSelector, vaultId, address(this), amount)
        );
        if (!ok) revert SwapFailed();
    }

    /* ---------------- arc-specific wrap hooks ---------------- */

    /// @dev Override per chain. Default: 1:1 pass-through (for placeholder + tests).
    function _wrapNativeToErc20Usdc(uint256 nativeAmount) internal virtual returns (uint256) {
        return nativeAmount;
    }

    function _unwrapErc20UsdcToNative(uint256 erc20Amount) internal virtual returns (uint256) {
        return erc20Amount;
    }
}

/* ====================================================================== */
/*    Minimal external interfaces — keeps the venue compileable without    */
/*    pulling in @uniswap/v3-periphery or Synthra-specific dependencies.   */
/* ====================================================================== */

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/// @notice Uniswap v3 SwapRouter02 shape — Synthra v3 is a Uniswap v3 fork so
/// the ABI matches. We only need `exactInputSingle` for the venue's MVP swap path.
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
