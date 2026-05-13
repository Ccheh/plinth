// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PlinthV05} from "../src/PlinthV05.sol";

/// @notice Deploys PlinthV05 to Arc Testnet. v0.5 is the security-hardened
///         successor to v0 (see docs/security-audit.md). MockVenue addresses
///         from the v0 deployment remain reusable — same interface,
///         independent of contract version.
contract DeployV05Script is Script {
    function run() external {
        vm.startBroadcast();

        PlinthV05 plinth = new PlinthV05();

        vm.stopBroadcast();

        console.log("=== PlinthV05 deployment ===");
        console.log("Chain ID:           ", block.chainid);
        console.log("PlinthV05:          ", address(plinth));
        console.log("INCEPTION_NAV:      ", plinth.INCEPTION_NAV());
        console.log("MAX_APPROVED_VENUES:", plinth.MAX_APPROVED_VENUES());
        console.log("MIN_DEPOSIT:        ", plinth.MIN_DEPOSIT());
        console.log("DEPOSIT_COOLDOWN:   ", plinth.DEPOSIT_COOLDOWN());
        console.log("MAX_PNL_MULTIPLE:   ", plinth.MAX_PNL_MULTIPLE());
        console.log("PNL_RATE_PCT:       ", plinth.PNL_RATE_PCT());
        console.log("PNL_RATE_WINDOW:    ", plinth.PNL_RATE_WINDOW());
        console.log("MAX_STRATEGY_LEN:   ", plinth.MAX_STRATEGY_LEN());
    }
}
