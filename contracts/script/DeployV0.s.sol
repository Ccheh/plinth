// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Plinth} from "../src/Plinth.sol";
import {MockVenue} from "../src/MockVenue.sol";

/// @notice Deploys Plinth v0 to Arc Testnet, plus two MockVenue contracts
///         that hackathon teams can use as placeholder execution venues
///         while integrating their real trading agents.
contract DeployV0Script is Script {
    function run() external {
        vm.startBroadcast();

        Plinth plinth = new Plinth();
        MockVenue venue1 = new MockVenue();
        MockVenue venue2 = new MockVenue();

        vm.stopBroadcast();

        console.log("=== Plinth v0 deployment ===");
        console.log("Chain ID:           ", block.chainid);
        console.log("Plinth:             ", address(plinth));
        console.log("MockVenue #1:       ", address(venue1));
        console.log("MockVenue #2:       ", address(venue2));
        console.log("INCEPTION_NAV:      ", plinth.INCEPTION_NAV());
        console.log("MAX_APPROVED_VENUES:", plinth.MAX_APPROVED_VENUES());
        console.log("MIN_DEPOSIT:        ", plinth.MIN_DEPOSIT());
    }
}
