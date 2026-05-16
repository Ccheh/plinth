// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PlinthV06} from "../src/PlinthV06.sol";
import {CadencePlinthBridge} from "../src/CadencePlinthBridge.sol";

/// @notice Deploys PlinthV06 + CadencePlinthBridge to Arc Testnet.
///
/// v0.6 vs v0.5:
///   - PlinthV06 adds on-chain RiskGuard (4 enforced risk signals)
///   - CadencePlinthBridge is the second on-chain sibling-protocol composition
///     (first was MandatePlinthBridge for capability-bound credit)
///
/// PaymentEscrowV2 (Cadence) is at 0xc95b1b20f91901206ba3ea94bbc7313e7cd82f8d
/// on Arc Testnet (deployed from the Ccheh/arc402 repo earlier).
contract DeployV06Script is Script {
    address constant CADENCE_PAYMENT_ESCROW_V2 = 0xC95B1b20f91901206Ba3eA94BBC7313E7Cd82f8D;

    function run() external {
        vm.startBroadcast();

        PlinthV06 plinth = new PlinthV06();
        CadencePlinthBridge bridge = new CadencePlinthBridge(
            address(plinth),
            CADENCE_PAYMENT_ESCROW_V2
        );

        vm.stopBroadcast();

        console.log("=== Plinth v0.6 deployment ===");
        console.log("Chain ID:                  ", block.chainid);
        console.log("PlinthV06:                 ", address(plinth));
        console.log("CadencePlinthBridge:       ", address(bridge));
        console.log("  -> wired to PlinthV06:   ", address(plinth));
        console.log("  -> wired to Cadence v2:  ", CADENCE_PAYMENT_ESCROW_V2);
        console.log("");
        console.log("=== Inherited v0.5 constants ===");
        console.log("INCEPTION_NAV:             ", plinth.INCEPTION_NAV());
        console.log("MIN_DEPOSIT:               ", plinth.MIN_DEPOSIT());
        console.log("DEPOSIT_COOLDOWN:          ", plinth.DEPOSIT_COOLDOWN());
        console.log("MAX_PNL_MULTIPLE:          ", plinth.MAX_PNL_MULTIPLE());
        console.log("PNL_RATE_PCT:              ", plinth.PNL_RATE_PCT());
        console.log("");
        console.log("=== New v0.6 RiskGuard parameters ===");
        console.log("MAX_VENUE_CONCENTRATION_BPS:", plinth.MAX_VENUE_CONCENTRATION_BPS());
        console.log("NAV_FLOOR_BPS:             ", plinth.NAV_FLOOR_BPS());
        console.log("WHALE_DEPOSIT_BPS:         ", plinth.WHALE_DEPOSIT_BPS());
    }
}
