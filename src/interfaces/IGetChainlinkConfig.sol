// SPDX-License-Identifier: MIt
pragma solidity 0.8.25;

interface IGetChainlinkConfig {
    struct GetChainlinkConfig {
        uint64 subId;
        address functionsRouter;
        bytes32 donId;
    }
}