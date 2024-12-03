// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.sol";
import { dTSLA } from "../../src/assets/dTSLA.sol";
import { IGetAssetReturnTypes } from "../../src/interfaces/IGetAssetReturnTypes.sol";

contract DeployDTsla is Script {
    string constant alpacaMintSource = "./functions/sources/mintTsla.js";

    function run() external {
        // Get params
        IGetAssetReturnTypes.GetAssetReturnType memory tslaReturnType = getdTslaRequirements();

        // Actually deploy
        vm.startBroadcast();
        deployDTSLA(
            tslaReturnType.subId,
            tslaReturnType.mintSource,
            tslaReturnType.functionsRouter,
            tslaReturnType.donId,
            tslaReturnType.assetFeed,
            tslaReturnType.usdcFeed,
            tslaReturnType.redemptionCoin,
            tslaReturnType.secretVersion,
            tslaReturnType.secretSlot
        );
        vm.stopBroadcast();
    }

    function getdTslaRequirements() public returns (IGetAssetReturnTypes.GetAssetReturnType memory) {
        HelperConfig helperConfig = new HelperConfig();
        (
            HelperConfig.Assets memory assets,
            address usdcFeed, /*address ethFeed*/
            ,
            address functionsRouter,
            bytes32 donId,
            uint64 subId,
            address redemptionCoin,
            ,
            ,
            ,
            uint64 secretVersion,
            uint8 secretSlot
        ) = helperConfig.activeNetworkConfig();

        if (
            assets.tslaPriceFeed == address(0) || usdcFeed == address(0) || functionsRouter == address(0) || donId == bytes32(0)
                || subId == 0
        ) {
            revert("something is wrong");
        }
        string memory mintSource = vm.readFile(alpacaMintSource);
        return IGetAssetReturnTypes.GetAssetReturnType(
            subId,
            mintSource,
            functionsRouter,
            donId,
            assets.tslaPriceFeed,
            usdcFeed,
            redemptionCoin,
            secretVersion,
            secretSlot
        );
    }

    function deployDTSLA(
        uint64 subId,
        string memory mintSource,
        address functionsRouter,
        bytes32 donId,
        address assetFeed,
        address usdcFeed,
        address redemptionCoin,
        uint64 secretVersion,
        uint8 secretSlot
    )
        public
        returns (dTSLA)
    {
        dTSLA dTsla = new dTSLA(
            subId,
            mintSource,
            functionsRouter,
            donId,
            assetFeed,
            usdcFeed,
            redemptionCoin,
            secretVersion,
            secretSlot
        );
        return dTsla;
    }
}