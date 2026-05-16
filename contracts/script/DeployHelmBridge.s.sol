// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {HelmPlinthBridge} from "../src/HelmPlinthBridge.sol";

/// @notice Deploys HelmPlinthBridge to Arc Testnet — 4th on-chain composition.
contract DeployHelmBridgeScript is Script {
    address constant PLINTH_V06 = 0x17B7B30d324Add96c5dC5d3259746695e94c92C9;
    address constant HELM = 0x47e6D5669d302C8Ed6B32189820f36C172a02691;

    function run() external {
        vm.startBroadcast();
        HelmPlinthBridge bridge = new HelmPlinthBridge(PLINTH_V06, HELM);
        vm.stopBroadcast();
        console.log("HelmPlinthBridge:        ", address(bridge));
        console.log("Wired to PlinthV06:      ", PLINTH_V06);
        console.log("Wired to Helm:           ", HELM);
    }
}
