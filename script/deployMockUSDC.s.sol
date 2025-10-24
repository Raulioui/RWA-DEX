// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

contract DeployMockUSDC is Script {
    function run() external {  
        vm.startBroadcast();
            new MockUSDC();
        vm.stopBroadcast();
    }
}