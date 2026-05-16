// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MorphoVenueAdapter, IERC4626, IERC20} from "../src/MorphoVenueAdapter.sol";
import {IYieldVenue} from "../src/interfaces/IYieldVenue.sol";
import {PlinthV05} from "../src/PlinthV05.sol";

/// @notice Tests for MorphoVenueAdapter — covers both:
///   (1) placeholder mode (Morpho-not-yet-on-Arc), where the adapter behaves as a
///       pass-through holder so the scaffold is safe to deploy pre-Morpho-deployment
///   (2) production mode against a minimal mock ERC-4626 vault, proving the
///       shares↔assets accounting + principal/yield split works correctly
contract MorphoVenueAdapterTest is Test {
    MorphoVenueAdapter placeholder;
    MorphoVenueAdapter prod;
    MockErc4626Vault mockMorpho;
    MockUsdcErc20 underlying;
    PlinthV05 plinth;

    address operator = makeAddr("operator");
    address agent    = makeAddr("agent");
    address investor = makeAddr("investor");

    function setUp() public {
        plinth = new PlinthV05();
        underlying = new MockUsdcErc20();
        mockMorpho = new MockErc4626Vault(address(underlying));

        // Placeholder mode: addresses are sentinels; native USDC stays in adapter.
        vm.prank(operator);
        placeholder = new MorphoVenueAdapter(address(0xdEaD), address(0));

        // Production mode: real-shaped Morpho vault + ERC-20 underlying.
        // We use a wrap-pass-through subclass so msg.value ↔ ERC-20 amount 1:1.
        vm.prank(operator);
        prod = new TestableMorphoAdapter(address(mockMorpho), address(underlying), underlying);

        vm.deal(agent, 100 ether);
        vm.deal(investor, 100 ether);
        vm.warp(1_000_000);
    }

    /* ===================================================================== */
    /*               IYieldVenue interface conformance                        */
    /* ===================================================================== */

    function test_implementsIYieldVenue() public view {
        // Compiles only if MorphoVenueAdapter implements IYieldVenue end-to-end.
        IYieldVenue v = IYieldVenue(address(placeholder));
        assertEq(v.principalBalance(), 0);
        assertEq(v.accruedYield(), 0);
        assertEq(v.yieldVenueVersion(), "0.1.0");
    }

    function test_metadata_placeholder_vs_production() public view {
        assertEq(placeholder.yieldSource(), "morpho-arc-PLACEHOLDER");
        assertEq(prod.yieldSource(), "morpho-vault-v2");
        assertTrue(placeholder.isPlaceholder());
        assertFalse(prod.isPlaceholder());
    }

    /* ===================================================================== */
    /*               PLACEHOLDER MODE: pre-Morpho-on-Arc                      */
    /* ===================================================================== */

    function test_placeholder_acceptsFunds_butNoYield() public {
        vm.prank(agent);
        (bool ok,) = address(placeholder).call{value: 1 ether}("");
        assertTrue(ok);

        assertEq(placeholder.principalBalance(), 1 ether);
        assertEq(placeholder.currentBalance(), 1 ether);
        assertEq(placeholder.accruedYield(), 0);  // no yield in placeholder mode

        // Time passes — still no yield
        vm.warp(block.timestamp + 365 days);
        assertEq(placeholder.accruedYield(), 0);
        assertEq(placeholder.currentBalance(), 1 ether);
    }

    function test_placeholder_returnPrincipal_roundTrips() public {
        // Stage: create vault on Plinth with placeholder as the approved venue
        address[] memory venues = new address[](1);
        venues[0] = address(placeholder);
        vm.prank(agent);
        bytes32 vaultId = plinth.createVault{value: 0.01 ether}(venues, "placeholder-test");

        // Deploy capital to the placeholder venue
        vm.prank(agent);
        plinth.deployToVenue(vaultId, address(placeholder), 0.005 ether);
        assertEq(placeholder.principalBalance(), 0.005 ether);

        // Return it
        placeholder.returnPrincipal(
            payable(address(plinth)),
            vaultId,
            0.005 ether,
            plinth.returnFromVenue.selector
        );
        assertEq(placeholder.principalBalance(), 0);
    }

    /* ===================================================================== */
    /*               PRODUCTION MODE: against mock ERC-4626                   */
    /* ===================================================================== */

    function test_prod_deposit_routesToMorpho() public {
        // Pre-mint ERC-20 USDC to the adapter so the wrap step is a pass-through
        underlying.mint(address(prod), 0); // ensure exists

        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        // Adapter tracks principal
        assertEq(prod.principalBalance(), 1 ether);
        // Morpho mock now holds the underlying
        assertEq(underlying.balanceOf(address(mockMorpho)), 1 ether);
        // Adapter holds shares
        assertGt(IERC20(address(mockMorpho)).balanceOf(address(prod)), 0);
    }

    function test_prod_yield_accrues_throughMorpho() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(prod.currentBalance(), 1 ether);
        assertEq(prod.accruedYield(), 0);

        // Simulate Morpho yield: double the per-share value (numerator=4 → 2:1)
        mockMorpho.appreciateShares(4);
        assertEq(prod.currentBalance(), 2 ether);
        assertEq(prod.accruedYield(), 1 ether);  // 1 ether yield on top of 1 ether principal
        assertEq(prod.principalBalance(), 1 ether);  // principal unchanged
    }

    function test_prod_returnPrincipal_withdrawsFromMorpho() public {
        address[] memory venues = new address[](1);
        venues[0] = address(prod);
        vm.prank(agent);
        bytes32 vaultId = plinth.createVault{value: 0.01 ether}(venues, "prod-test");

        vm.prank(agent);
        plinth.deployToVenue(vaultId, address(prod), 0.005 ether);
        assertEq(prod.principalBalance(), 0.005 ether);
        assertEq(underlying.balanceOf(address(mockMorpho)), 0.005 ether);

        // Return principal
        prod.returnPrincipal(
            payable(address(plinth)),
            vaultId,
            0.005 ether,
            plinth.returnFromVenue.selector
        );
        assertEq(prod.principalBalance(), 0);
        // Morpho gave back the underlying
        assertEq(underlying.balanceOf(address(mockMorpho)), 0);
    }

    function test_prod_harvestYield_peelsOnlyTheYield() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);

        // 50% appreciation: 1 ether principal → 1.5 ether total → 0.5 ether yield
        mockMorpho.appreciateShares(3);  // 50% bump via /2 then *3
        assertEq(prod.currentBalance(), 1.5 ether);
        assertEq(prod.accruedYield(), 0.5 ether);

        // Harvest 0.3 of the 0.5 yield to the agent
        prod.harvestYield(payable(agent), 0.3 ether);
        // Principal untouched
        assertEq(prod.principalBalance(), 1 ether);
        // Remaining yield = 0.2 ether
        assertApproxEqAbs(prod.accruedYield(), 0.2 ether, 1);
    }

    function test_harvestYield_revertsWhenExceedsAccrual() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);
        // No yield accrued yet
        vm.expectRevert("exceeds accrued yield");
        prod.harvestYield(payable(agent), 0.001 ether);
    }

    function test_returnPrincipal_revertsWhenExceedsPrincipal() public {
        vm.prank(agent);
        (bool ok,) = address(prod).call{value: 1 ether}("");
        assertTrue(ok);
        vm.expectRevert("exceeds tracked principal");
        prod.returnPrincipal(payable(address(plinth)), bytes32(0), 2 ether, bytes4(0));
    }
}

/* ====================================================================== */
/*                 Test-only subclasses + mocks                            */
/* ====================================================================== */

/// @notice 1:1 pass-through wrap so test math is simple — production deployment
/// will override these hooks with the real native↔ERC20 conversion path.
contract TestableMorphoAdapter is MorphoVenueAdapter {
    MockUsdcErc20 token;

    constructor(address _vault, address _underlying, MockUsdcErc20 _token)
        MorphoVenueAdapter(_vault, _underlying)
    {
        token = _token;
    }

    function _wrapNativeToErc20(uint256 nativeAmount) internal override returns (uint256) {
        // Mint mock USDC into this contract so we can deposit to Morpho.
        token.mint(address(this), nativeAmount);
        return nativeAmount;
    }

    function _unwrapErc20ToNative(uint256 erc20Amount) internal override returns (uint256) {
        // Burn the ERC20 (simulates unwrap); native USDC was already sent to us
        // by Morpho's withdraw via a separate path. In real production, this is
        // the unwrap contract's `withdraw()` call. For the test we just balance:
        token.burn(address(this), erc20Amount);
        // Native USDC needs to exist on `this` — simulate by dealing to ourselves.
        vm.deal(address(this), address(this).balance + erc20Amount);
        return erc20Amount;
    }

    // Test helper: forge cheat from Test, since we can't import in non-Test contract.
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
}

interface Vm {
    function deal(address, uint256) external;
}

/// @notice Minimal mock ERC-20 supporting mint/burn for adapter testing.
contract MockUsdcErc20 is IERC20 {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalSupply;

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
    function mint(address to, uint256 v) external {
        balances[to] += v;
        totalSupply += v;
    }
    function burn(address from, uint256 v) external {
        require(balances[from] >= v, "insufficient");
        balances[from] -= v;
        totalSupply -= v;
    }
}

/// @notice Minimal ERC-4626-shaped mock vault. Tracks shares per depositor;
/// `appreciateShares(numerator)` simulates yield accrual by making each share
/// worth `numerator/2` units of asset.
/// Implements both IERC4626 and IERC20 surfaces by declaring the function
/// signatures directly (not via `is IERC4626, IERC20`) to avoid name-clash
/// override complexity in the test mock.
contract MockErc4626Vault {
    IERC20 public underlying;
    mapping(address => uint256) public shares;
    uint256 public totalShares;
    uint256 public totalAssetsBacking;

    // Appreciation: convertToAssets(shares) = shares * appreciationNumerator / 2
    // Default (numerator=2) → 1:1. Set numerator=3 → +50% yield. numerator=4 → +100%.
    uint256 public appreciationNumerator = 2;

    constructor(address _underlying) {
        underlying = IERC20(_underlying);
    }

    function asset() external view returns (address) { return address(underlying); }
    function totalAssets() external view returns (uint256) { return totalAssetsBacking; }

    function balanceOf(address a) external view returns (uint256) { return shares[a]; }
    function approve(address, uint256) external pure returns (bool) { return true; }
    function transfer(address, uint256) external pure returns (bool) { return true; }
    function transferFrom(address, address, uint256) external pure returns (bool) { return true; }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalShares == 0) return assets;
        return assets * 2 / appreciationNumerator;
    }

    function convertToAssets(uint256 sharesAmt) public view returns (uint256) {
        return sharesAmt * appreciationNumerator / 2;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        underlying.transferFrom(msg.sender, address(this), assets);
        uint256 mintedShares = convertToShares(assets);
        shares[receiver] += mintedShares;
        totalShares += mintedShares;
        totalAssetsBacking += assets;
        return mintedShares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        uint256 burnedShares = convertToShares(assets);
        require(shares[owner] >= burnedShares, "insufficient shares");
        shares[owner] -= burnedShares;
        totalShares -= burnedShares;
        totalAssetsBacking -= assets;
        underlying.transfer(receiver, assets);
        return burnedShares;
    }

    function redeem(uint256 sharesAmt, address receiver, address owner) external returns (uint256) {
        uint256 assetsOut = convertToAssets(sharesAmt);
        require(shares[owner] >= sharesAmt, "insufficient");
        shares[owner] -= sharesAmt;
        totalShares -= sharesAmt;
        totalAssetsBacking -= assetsOut;
        underlying.transfer(receiver, assetsOut);
        return assetsOut;
    }

    /// Simulate Morpho-style appreciation. Default numerator=2 (1:1).
    /// appreciateShares(3) → +50% yield. appreciateShares(4) → +100%. etc.
    function appreciateShares(uint256 numerator) external {
        appreciationNumerator = numerator;
    }
}
