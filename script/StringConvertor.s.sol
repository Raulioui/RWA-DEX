// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.sol";

contract DeployDTsla is Script {
    string constant redeemSource = "./functions/sources/redeemAsset.js";

    function run() external {
        vm.startBroadcast();    
            string memory _redeemSource = vm.readFile(redeemSource);
            console2.log(_redeemSource);
            vm.stopBroadcast();
    }
}