// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SynthraSpotVenue, IERC20, ISwapRouter02} from "../src/SynthraSpotVenue.sol";
import {PlinthV05} from "../src/PlinthV05.sol";

/// @notice Tests for SynthraSpotVenue — covers:
///   (1) placeholder mode safety (swap calls revert loudly, principal still round-trips)
///   (2) production mode against a mock Uniswap-v3-style SwapRouter (Synthra is a v3 fork)
///   (3) access control: only the agent can initiate swaps
///   (4) Plinth-side integration: createVault → deployToVenue → returnPrincipal cycle
contract SynthraSpotVenueTest is Test {
    SynthraSpotVenue placeholder;
    SynthraSpotVenue prod;
    MockSwapRouter mockRouter;
    MockToken usdc;
    MockToken weth;
    PlinthV05 plinth;

    address agent     = makeAddr("agent");
    address operator  = makeAddr("operator");
    address attacker  = makeAddr("attacker");

    function setUp() public {
        plinth = new PlinthV05();
        usdc = new MockToken("USDC", 6);
        weth = new MockToken("WETH", 18);
        mockRouter = new MockSwapRouter(weth);

        // Placeholder: address(0xdEaD) router, no USDC token configured.
        vm.prank(operator);
        placeholder = new SynthraSpotVenue(address(0xdEaD), address(0), agent);

        // Production: real-shaped router + USDC; 1:1 wrap passthrough for test simplicity.
        vm.prank(operator);
        prod = new TestableSynthraSpotVenue(address(mockRouter), address(usdc), agent, usdc);

        vm.deal(agent, 100 ether);
        vm.deal(operator, 100 ether);
        vm.warp(1_000_000);

        // Seed mock router with WETH so swaps can deliver tokenOut
        weth.mint(address(mockRouter), 1_000 ether);
    }

    /* ====================================================================== */
    /*               Placeholder safety: swaps revert, principal works         */
    /* ====================================================================== */

    function test_placeholder_acceptsFunds() public {
        vm.prank(agent);
        (bool ok,) = address(placeholder).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(placeholder.principal(), 1 ether);
        assertTrue(placeholder.isPlaceholder());
    }

    function test_placeholder_swapReverts() public {
        vm.prank(agent);
        (bool ok,) = address(placeholder).call{value: 1 ether}("");
        assertTrue(ok);

        vm.prank(agent);
        vm.expectRevert(SynthraSpotVenue.PlaceholderMode.selector);
        placeholder.swapUsdcToToken(address(weth), 3000, 0.5 ether, 0);
    }

    function test_placeholder_returnPrincipal_roundTrips() public {
        address[] memory venues = new address[](1);
        venues[0] = address(placeholder);
        vm.prank(agent);
        bytes32 vaultId = plinth.createVault{value: 0.01 ether}(venues, "placeholder-spot");

        vm.prank(agent);
        plinth.deployToVenue(vaultId, address(placeholder), 0.005 ether);
        assertEq(placeholder.principal(), 0.005 ether);

        placeholder.returnPrincipal(
            payable(address(plinth)),
            vaultId,
            0.005 ether,
            plinth.returnFromVenue.selector
        );
        assertEq(placeholder.principal(), 0);
    }

    /* ====================================================================== */
    /*               Access control                                            */
    /* ====================================================================== */

    function test_swap_revertsForNonAgent() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        vm.prank(attacker);
        vm.expectRevert(SynthraSpotVenue.NotAgent.selector);
        prod.swapUsdcToToken(address(weth), 3000, 0.5 ether, 0);
    }

    function test_swapBack_revertsForNonAgent() public {
        vm.prank(attacker);
        vm.expectRevert(SynthraSpotVenue.NotAgent.selector);
        prod.swapTokenToUsdc(address(weth), 3000, 1 ether, 0);
    }

    /* ====================================================================== */
    /*               Production: USDC → WETH swap via mock router              */
    /* ====================================================================== */

    function test_prod_usdcToWeth_swap() public {
        // Deposit 1 ether worth of native USDC into venue
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        // Mock router pays 0.5 WETH per 1 USDC by default
        vm.prank(agent);
        uint256 wethOut = prod.swapUsdcToToken(address(weth), 3000, 1 ether, 0.4 ether);
        assertEq(wethOut, 0.5 ether);
        assertEq(weth.balanceOf(address(prod)), 0.5 ether);
    }

    function test_prod_slippageProtection() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        // Demand min 0.6 WETH but router only gives 0.5 → revert
        vm.prank(agent);
        vm.expectRevert();  // MockSwapRouter reverts internally with InsufficientOutputAmount
        prod.swapUsdcToToken(address(weth), 3000, 1 ether, 0.6 ether);
    }

    function test_prod_swap_emitsEvent() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        vm.expectEmit(true, true, false, true, address(prod));
        emit SynthraSpotVenue.SwapExecuted(address(usdc), address(weth), 1 ether, 0.5 ether, 3000);
        vm.prank(agent);
        prod.swapUsdcToToken(address(weth), 3000, 1 ether, 0.4 ether);
    }

    /* ====================================================================== */
    /*               Round-trip: USDC → WETH → USDC                            */
    /* ====================================================================== */

    function test_prod_roundTrip_usdcToWethToUsdc() public {
        // Deposit
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(prod.principal(), 1 ether);

        // Swap to WETH
        vm.prank(agent);
        prod.swapUsdcToToken(address(weth), 3000, 1 ether, 0.4 ether);
        assertEq(weth.balanceOf(address(prod)), 0.5 ether);

        // Mock router: 2 USDC per 1 WETH on reverse direction → 0.5 WETH yields 1 USDC
        usdc.mint(address(mockRouter), 1 ether);  // ensure router has USDC liquidity
        vm.prank(agent);
        uint256 usdcOut = prod.swapTokenToUsdc(address(weth), 3000, 0.5 ether, 0.9 ether);
        assertEq(usdcOut, 1 ether);
    }

    /* ====================================================================== */
    /*               Return-principal invariants                               */
    /* ====================================================================== */

    function test_returnPrincipal_revertsExcessOfPrincipal() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        vm.expectRevert(SynthraSpotVenue.ExceedsPrincipal.selector);
        prod.returnPrincipal(payable(address(plinth)), bytes32(0), 2 ether, bytes4(0));
    }

    function test_returnPrincipal_revertsInsufficientReserve() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        // Agent swapped to WETH; native USDC reserve is now 0
        vm.prank(agent);
        prod.swapUsdcToToken(address(weth), 3000, 1 ether, 0.4 ether);

        vm.expectRevert(SynthraSpotVenue.InsufficientReserve.selector);
        prod.returnPrincipal(payable(address(plinth)), bytes32(0), 0.5 ether, bytes4(0));
    }
}

/* ====================================================================== */
/*                 Test-only subclasses + mocks                            */
/* ====================================================================== */

/// @notice Production-mode venue with 1:1 wrap-passthrough so test math is simple.
contract TestableSynthraSpotVenue is SynthraSpotVenue {
    MockToken token;

    constructor(address _router, address _usdc, address _agent, MockToken _token)
        SynthraSpotVenue(_router, _usdc, _agent)
    {
        token = _token;
    }

    function _wrapNativeToErc20Usdc(uint256 nativeAmount) internal override returns (uint256) {
        // Simulate production: native USDC leaves venue (sent to wrap-sink), ERC-20 arrives.
        token.mint(address(this), nativeAmount);
        (bool ok,) = payable(address(0xdEaD)).call{value: nativeAmount}("");
        require(ok, "wrap-sink failed");
        return nativeAmount;
    }

    function _unwrapErc20UsdcToNative(uint256 erc20Amount) internal override returns (uint256) {
        // Inverse: ERC-20 burned, native USDC restored to venue (from cheatcode "mint").
        token.burn(address(this), erc20Amount);
        vm.deal(address(this), address(this).balance + erc20Amount);
        return erc20Amount;
    }

    // Forge cheat-code address for vm.deal in non-Test contract.
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
}

interface Vm {
    function deal(address, uint256) external;
}

/// @notice Minimal ERC-20 mock with mint/burn helpers for tests.
contract MockToken is IERC20 {
    string public name;
    uint8 public decimals;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    constructor(string memory _name, uint8 _decimals) {
        name = _name;
        decimals = _decimals;
    }

    function balanceOf(address a) external view returns (uint256) { return balances[a]; }
    function approve(address s, uint256 v) external returns (bool) { allowances[msg.sender][s] = v; return true; }
    function transfer(address to, uint256 v) external returns (bool) {
        require(balances[msg.sender] >= v, "insufficient");
        balances[msg.sender] -= v;
        balances[to] += v;
        return true;
    }
    function transferFrom(address from, address to, uint256 v) external returns (bool) {
        require(balances[from] >= v, "insufficient");
        if (allowances[from][msg.sender] != type(uint256).max) {
            require(allowances[from][msg.sender] >= v, "unauthorized");
            allowances[from][msg.sender] -= v;
        }
        balances[from] -= v;
        balances[to] += v;
        return true;
    }
    function mint(address to, uint256 v) external { balances[to] += v; }
    function burn(address from, uint256 v) external { require(balances[from] >= v, "insuf"); balances[from] -= v; }
}

/// @notice Mock Uniswap v3 SwapRouter02 — accepts exactInputSingle, swaps at fixed rates:
///   USDC → WETH at 0.5 (1 USDC = 0.5 WETH)
///   WETH → USDC at 2.0 (1 WETH = 2 USDC) — i.e. the inverse, round-trip is loss-less
contract MockSwapRouter is ISwapRouter02 {
    MockToken public weth;
    error InsufficientOutputAmount();

    constructor(MockToken _weth) {
        weth = _weth;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut)
    {
        // Pull tokenIn from caller
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Compute amountOut: if tokenIn is USDC-like (the mock token), out = in * 0.5 (to WETH)
        // If tokenIn is WETH, out = in * 2 (to USDC-like)
        if (params.tokenIn == address(weth)) {
            amountOut = params.amountIn * 2;
        } else {
            amountOut = params.amountIn / 2;
        }

        if (amountOut < params.amountOutMinimum) revert InsufficientOutputAmount();

        // Send tokenOut to recipient
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
    }
}
