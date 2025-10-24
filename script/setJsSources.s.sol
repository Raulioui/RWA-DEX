// SPDX-Licence-Indentifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { DevOpsTools } from "foundry-devops/src/DevOpsTools.sol";
import { ChainlinkCaller } from "../src/ChainlinkCaller.sol";

contract SetJsSources is Script {
    string constant alpacaMintSource = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";

    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);

    function run() external  {
        vm.startBroadcast();
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("ChainlinkCaller", block.chainid);
        ChainlinkCaller(mostRecentlyDeployed).setJsSources(mintSource, sellSource);
        vm.stopBroadcast();
    }
}