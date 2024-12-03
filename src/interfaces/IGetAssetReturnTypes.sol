// SPDX-License-Identifier: MIt
pragma solidity 0.8.25;

interface IGetAssetReturnTypes {

    struct GetAssetReturnType {
        uint64 subId;
        string mintSource;
        address functionsRouter;
        bytes32 donId;
        address assetFeed;
        address usdcFeed;
        address redemptionCoin;
        uint64 secretVersion;
        uint8 secretSlot;
    }
}