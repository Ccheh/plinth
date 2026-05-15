// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MandatePlinthBridge, IMandateExternal, IPlinthExternal} from "../src/MandatePlinthBridge.sol";

/// @notice Deploys MandatePlinthBridge wiring the existing Mandate v0
/// (0xfbbdaec0…) and PlinthV05 (0xba1b087b…) contracts on Arc Testnet.
contract DeployMandateBridgeScript is Script {
    function run() external {
        // Existing deployments on Arc Testnet
        IMandateExternal mandate = IMandateExternal(0xfBBDAeC05E0061ADeb955896DFF183fdd412E6E4);
        IPlinthExternal  plinth  = IPlinthExternal(0xBA1b087B0aC77B398C250A9Fd7e298F3f96AddC7);

        vm.startBroadcast();
        MandatePlinthBridge bridge = new MandatePlinthBridge(mandate, plinth);
        vm.stopBroadcast();

        console.log("=== MandatePlinthBridge deployment ===");
        console.log("Bridge:    ", address(bridge));
        console.log("Mandate:   ", address(mandate));
        console.log("Plinth:    ", address(plinth));
    }
}
