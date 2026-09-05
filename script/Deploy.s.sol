// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.36;

import {Script} from "forge-std/Script.sol";
import {BlitzBoard} from "../src/BlitzBoard.sol";

contract Deploy is Script {
    BlitzBoard public blitz;

    function run() external {
        vm.startBroadcast();
        blitz = new BlitzBoard();
        vm.stopBroadcast();
    }
}
