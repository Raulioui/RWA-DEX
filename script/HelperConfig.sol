// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { MockUSDC } from "../test/mocks/MockUSDC.sol";
import { MockLinkToken } from "../test/mocks/MockLinkToken.sol";

contract HelperConfig {
    NetworkConfig public activeNetworkConfig;

    mapping(uint256 chainId => uint64 ccipChainSelector) public chainIdToCCIPChainSelector;

    struct NetworkConfig {
        address functionsRouter;
        bytes32 donId;
        uint64 subId;
        address usdt;
    }

    mapping(uint256 => NetworkConfig) public chainIdToNetworkConfig;

    constructor() {
        chainIdToNetworkConfig[421614] = getArbitrumSepoliaConfig();
        chainIdToNetworkConfig[11155111] = getSepoliaConfig();
        chainIdToNetworkConfig[43113] = getAvalacheFuji();
        chainIdToNetworkConfig[80002] = getPolygonAmoyConfig();
        activeNetworkConfig = chainIdToNetworkConfig[block.chainid];
    }

    function getArbitrumSepoliaConfig() internal pure returns(NetworkConfig memory config) {
        config = NetworkConfig({
            functionsRouter: 0x234a5fb5Bd614a7AA2FfAB244D603abFA0Ac5C5C,
            donId: 0x66756e2d617262697472756d2d7365706f6c69612d3100000000000000000000,
            subId: 219,
            usdt: 0x80Efc4Bcb5797a952943512b10c1595aCdE821cC
        });
    }

    function getSepoliaConfig() internal pure returns (NetworkConfig memory config) {
        config = NetworkConfig({
            functionsRouter: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            donId: 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000,
            subId: 3130, // TO,
            usdt: 0xf9036AcAD099fCFee7DE247f309A24717aDa2fFD 
         });
    }

    function getAvalacheFuji() internal pure returns (NetworkConfig memory config) {
        config = NetworkConfig({
            functionsRouter: 0xA9d587a00A31A52Ed70D6026794a8FC5E2F5dCb0,
            donId: 0x66756e2d6176616c616e6368652d66756a692d31000000000000000000000000,
            subId: 15720,
            usdt: 0xCB40EA7Cd1A1791ebFC723C986e5C4803bbd3585 
         });
    }


    function getPolygonAmoyConfig() internal pure returns (NetworkConfig memory config) {
        config = NetworkConfig({
            functionsRouter: 0xC22a79eBA640940ABB6dF0f7982cc119578E11De,
            donId: 0x66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000,
            subId: 473, // TO,
            usdt: 0x1e29B2021541Fafd759C781508868FD5dc97a3f6 
         });
    }
}