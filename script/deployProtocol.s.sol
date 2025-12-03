// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.sol";
import {AssetPool} from "../src/AssetPool.sol";
import {ChainlinkCaller} from "../src/ChainlinkCaller.sol";
import { IGetChainlinkConfig } from "../src/interfaces/IGetChainlinkConfig.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockChainlinkCaller} from "../test/mocks/MockChainlinkCaller.sol";
import { AssetToken } from "../src/AssetToken.sol";

contract DeployProtocol is Script {
    string constant alpacaMintSource = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";
    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);

    function run() external {
        // Get params
        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = getChainlinkConfig();
        
        vm.startBroadcast();

        // Actually deploy
        deployProtocol(
            chainlinkValues.subId,
            chainlinkValues.functionsRouter,
            chainlinkValues.donId,
            chainlinkValues.usdt
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

    function deployProtocol(
        uint64 _subId,
        address _functionsRouter,
        bytes32 _donID,
        address _usdt
    ) public returns(address, address) {

        ChainlinkCaller chainlinkCaller = new ChainlinkCaller(
            _subId,
            _functionsRouter,
            _donID
        );

        MockChainlinkCaller mockChainlinkCaller = new MockChainlinkCaller();

        AssetPool assetPool = new AssetPool(
            IERC20(_usdt),
            address(chainlinkCaller)
        );

        AssetToken assetTokenImplementation = new AssetToken();
        assetPool.initializeBeacon(address(assetTokenImplementation));

        chainlinkCaller.setJsSources(mintSource, sellSource);
        chainlinkCaller.setAssetPool(address(assetPool));
        
        return (address(chainlinkCaller), address(assetPool));
    }
}