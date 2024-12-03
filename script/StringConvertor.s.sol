// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.sol";
import { dTSLA } from "../../src/assets/dTSLA.sol";
import { IGetAssetReturnTypes } from "../../src/interfaces/IGetAssetReturnTypes.sol";

contract DeployDTsla is Script {
    string constant redeemSource = "./functions/sources/redeemTsla.js";

    function run() external {
        vm.startBroadcast();    
            string memory _redeemSource = vm.readFile(redeemSource);
            console2.log(_redeemSource);
            dTSLA(0x139d8f974e83C0DA47F54aa24f657030851723f5).setRedeemSource(_redeemSource);
        vm.stopBroadcast();
    }
}