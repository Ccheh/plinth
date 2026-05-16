// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CruciblePlinthBridge} from "../src/CruciblePlinthBridge.sol";

/// @notice Deploys CruciblePlinthBridge to Arc Testnet — 3rd on-chain
/// sibling-protocol composition Plinth ships.
///
/// Wires:
///   plinth   = PlinthV06          0x17B7B30d324Add96c5dC5d3259746695e94c92C9
///   crucible = CrucibleMarketV6   0x6535a3cbb4235746b732ab5d55c6b0988f381a20
contract DeployCrucibleBridgeScript is Script {
    address constant PLINTH_V06 = 0x17B7B30d324Add96c5dC5d3259746695e94c92C9;
    address constant CRUCIBLE_V6 = 0x6535a3CbB4235746B732aB5d55c6b0988F381A20;

    function run() external {
        vm.startBroadcast();

        CruciblePlinthBridge bridge = new CruciblePlinthBridge(PLINTH_V06, CRUCIBLE_V6);

        vm.stopBroadcast();

        console.log("=== CruciblePlinthBridge deployment ===");
        console.log("Chain ID:                   ", block.chainid);
        console.log("CruciblePlinthBridge:       ", address(bridge));
        console.log("  -> wired to PlinthV06:    ", PLINTH_V06);
        console.log("  -> wired to Crucible V6:  ", CRUCIBLE_V6);
        console.log("");
        console.log("This is the THIRD on-chain sibling-protocol composition Plinth ships:");
        console.log("  1. MandatePlinthBridge   (Mandate v0 + PlinthV05)  -- capability-bound credit");
        console.log("  2. CadencePlinthBridge   (Plinth + Cadence v2)     -- fee streaming");
        console.log("  3. CruciblePlinthBridge  (Plinth + Crucible v6)    -- quality-conditional fees");
    }
}
