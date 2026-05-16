// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PlinthSponsorPool} from "../src/PlinthSponsorPool.sol";

contract DeploySponsorPoolScript is Script {
    function run() external {
        vm.startBroadcast();
        PlinthSponsorPool sp = new PlinthSponsorPool();
        vm.stopBroadcast();
        console.log("PlinthSponsorPool:        ", address(sp));
        console.log("REWARD_PER_REVIEW:        ", sp.REWARD_PER_REVIEW());
        console.log("MAX_CLAIMS_PER_CYCLE:     ", sp.MAX_CLAIMS_PER_REFILL_CYCLE());
    }
}
