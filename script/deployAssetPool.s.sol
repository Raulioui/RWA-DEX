// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.sol";
import {AssetPool} from "../src/AssetPool.sol";
import {ChainlinkCaller} from "../src/ChainlinkCaller.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DevOpsTools } from "foundry-devops/src/DevOpsTools.sol";
import { IGetChainlinkConfig } from "../src/interfaces/IGetChainlinkConfig.sol";

contract DeployAssetPool is Script {

    function run() external {
        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = getChainlinkConfig();

        vm.startBroadcast();
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("ChainlinkCaller", block.chainid);
        ChainlinkCaller chainlinkCaller = ChainlinkCaller(mostRecentlyDeployed);

        deployAssetPool(
            IERC20(chainlinkValues.usdt),
            address(chainlinkCaller)
        );

        vm.stopBroadcast();
    }

    function getChainlinkConfig() public returns (IGetChainlinkConfig.GetChainlinkConfig memory) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address functionsRouter,
            bytes32 donId,
            uint64 subId,
            address usdt
        ) = helperConfig.activeNetworkConfig();

        if (
            functionsRouter == address(0) || donId == bytes32(0) || subId == 0
        ) {
            revert("something is wrong");
        }
        return IGetChainlinkConfig.GetChainlinkConfig(
            subId,
            functionsRouter,
            donId,
            usdt
        );
    }

    function deployAssetPool(
        IERC20 usdt, 
        address chainlinkCaller
    ) public returns (AssetPool) {
        AssetPool assetPool = new AssetPool(
            usdt,
            chainlinkCaller
        );
        return assetPool;
    }
}