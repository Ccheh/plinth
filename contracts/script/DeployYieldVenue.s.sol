// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MockYieldVenue} from "../src/MockYieldVenue.sol";

/// @notice Deploys MockYieldVenue to Arc Testnet and seeds its yield reserve
///         with 0.01 USDC so payouts are backed.
contract DeployYieldVenueScript is Script {
    function run() external {
        vm.startBroadcast();

        MockYieldVenue venue = new MockYieldVenue();
        // Seed reserve so accrued yield is backed by on-chain balance
        venue.fundReserve{value: 0.01 ether}();

        vm.stopBroadcast();

        console.log("=== MockYieldVenue deployment ===");
        console.log("Address:    ", address(venue));
        console.log("Yield BPS:  ", venue.YIELD_BPS());
        console.log("Reserve:    ", address(venue).balance);
        console.log("Operator:   ", venue.operator());
    }
}
