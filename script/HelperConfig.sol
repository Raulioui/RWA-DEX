// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { MockFunctionsRouter } from "../test/mocks/MockFunctionsRouter.sol";
import { MockUSDC } from "../test/mocks/MockUSDC.sol";
import { MockLinkToken } from "../test/mocks/MockLinkToken.sol";

contract HelperConfig {
    NetworkConfig public activeNetworkConfig;

    mapping(uint256 chainId => uint64 ccipChainSelector) public chainIdToCCIPChainSelector;

    struct Assets {
        address tslaPriceFeed;
        address ibtaPriceFeed;
    }

    struct NetworkConfig {
        Assets assets;
        address usdcPriceFeed;
        address ethUsdPriceFeed;
        address functionsRouter;
        bytes32 donId;
        uint64 subId;
        address redemptionCoin;
        address linkToken;
        address ccipRouter;
        uint64 ccipChainSelector;
        uint64 secretVersion;
        uint8 secretSlot;
    }

    mapping(uint256 => NetworkConfig) public chainIdToNetworkConfig;

    // Mocks
    MockV3Aggregator public tslaFeedMock;
    MockV3Aggregator public ethUsdFeedMock;
    MockV3Aggregator public usdcFeedMock;
    MockUSDC public usdcMock;
    MockLinkToken public linkTokenMock;

    MockFunctionsRouter public functionsRouterMock;

    // TSLA USD, ETH USD, and USDC USD both have 8 decimals
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_ANSWER = 2000e8;
    int256 public constant INITIAL_ANSWER_USD = 1e8;

    constructor() {
        chainIdToNetworkConfig[137] = getPolygonConfig();
        chainIdToNetworkConfig[80_001] = getMumbaiConfig();
        chainIdToNetworkConfig[11155111] = getSepoliaConfig();
        chainIdToNetworkConfig[11155420] = getOptimismSepoliaConfig();
        chainIdToNetworkConfig[421614] = getArbitrumSepoliaConfig();
        activeNetworkConfig = chainIdToNetworkConfig[block.chainid];
    }

    function getPolygonConfig() internal pure returns (NetworkConfig memory config) {
        config = NetworkConfig({
            assets: Assets({
                tslaPriceFeed: 0x567E67f456c7453c583B6eFA6F18452cDee1F5a8,
                ibtaPriceFeed: 0x5c13b249846540F81c093Bc342b5d963a7518145
            }),
            usdcPriceFeed: 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7,
            ethUsdPriceFeed: 0xF9680D99D6C9589e2a93a78A04A279e509205945,
            functionsRouter: 0xdc2AAF042Aeff2E68B3e8E33F19e4B9fA7C73F10,
            donId: 0x66756e2d706f6c79676f6e2d6d61696e6e65742d310000000000000000000000,
            subId: 0, // TODO
            // USDC on Polygon
            redemptionCoin: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
            linkToken: 0xb0897686c545045aFc77CF20eC7A532E3120E0F1,
            ccipRouter: 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe,
            ccipChainSelector: 4_051_577_828_743_386_545,
            secretVersion: 0, // fill in!
            secretSlot: 0 // fill in!
         });
        // minimumRedemptionAmount: 30e6 // Please see your brokerage for min redemption amounts
        // https://alpaca.markets/support/crypto-wallet-faq
    }

    function getMumbaiConfig() internal pure returns (NetworkConfig memory config) {
        config = NetworkConfig({
            assets : Assets({
                tslaPriceFeed: 0x1C2252aeeD50e0c9B64bDfF2735Ee3C932F5C408, // this is LINK / USD but it'll work fine
                ibtaPriceFeed: 0x5c13b249846540F81c093Bc342b5d963a7518145
            }),
            usdcPriceFeed: 0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0,
            ethUsdPriceFeed: 0x0715A7794a1dc8e42615F059dD6e406A6594651A,
            functionsRouter: 0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C,
            donId: 0x66756e2d706f6c79676f6e2d6d756d6261692d31000000000000000000000000,
            subId: 1396,
            // USDC on Mumbai
            redemptionCoin: 0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747,
            linkToken: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            ccipRouter: 0x1035CabC275068e0F4b745A29CEDf38E13aF41b1,
            ccipChainSelector: 12_532_609_583_862_916_517,
            secretVersion: 0, // fill in!
            secretSlot: 0 // fill in!
         });
        // minimumRedemptionAmount: 30e6 // Please see your brokerage for min redemption amounts
        // https://alpaca.markets/support/crypto-wallet-faq
    }

    function getArbitrumSepoliaConfig() internal pure returns(NetworkConfig memory config) {
        config = NetworkConfig({
            assets: Assets({
                tslaPriceFeed: 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298,
                ibtaPriceFeed: 0x0000000000000000000000000000000000000000
            }),
            usdcPriceFeed: 0x0153002d20B96532C639313c2d54c3dA09109309,
            ethUsdPriceFeed: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165,
            functionsRouter: 0x234a5fb5Bd614a7AA2FfAB244D603abFA0Ac5C5C,
            donId: 0x66756e2d617262697472756d2d7365706f6c69612d3100000000000000000000,
            subId: 217, 
            redemptionCoin: 0xbC47901f4d2C5fc871ae0037Ea05c3F614690781,
            linkToken: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
            ccipRouter: 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165,
            ccipChainSelector: 3478487238524512106,
            secretVersion: 0, // fill in!
            secretSlot: 0 // fill in!
        });
    }

    function getOptimismSepoliaConfig() internal pure returns(NetworkConfig memory config) {
        config = NetworkConfig({
            assets: Assets({
                tslaPriceFeed: 0x53f91dA33120F44893CB896b12a83551DEDb31c6,
                ibtaPriceFeed: 0x0000000000000000000000000000000000000000
            }),
            usdcPriceFeed: 0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C,
            ethUsdPriceFeed: 0x61Ec26aA57019C486B10502285c5A3D4A4750AD7,
            functionsRouter: 0xC17094E3A1348E5C7544D4fF8A36c28f2C6AAE28,
            donId: 0x66756e2d6f7074696d69736d2d7365706f6c69612d3100000000000000000000,
            subId: 239, 
            redemptionCoin: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7,
            linkToken: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
            ccipRouter: 0x114A20A10b43D4115e5aeef7345a1A71d2a60C57,
            ccipChainSelector: 5224473277236331295,
            secretVersion: 0, // fill in!
            secretSlot: 0 // fill in!
        });
    }

    function getSepoliaConfig() internal pure returns (NetworkConfig memory config) {
        config = NetworkConfig({
            assets: Assets({
                tslaPriceFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF, // this is LINK / USD but it'll work fine
                ibtaPriceFeed: 0x5c13b249846540F81c093Bc342b5d963a7518145
            }),
            usdcPriceFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E,
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            functionsRouter: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            donId: 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000,
            subId: 3130,
            // USDC on Mumbai
            redemptionCoin: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            ccipRouter: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            ccipChainSelector: 16_015_286_601_757_825_753,
            secretVersion: 0, // fill in!
            secretSlot: 0 // fill in!
         });
        // minimumRedemptionAmount: 30e6 // Please see your brokerage for min redemption amounts
        // https://alpaca.markets/support/crypto-wallet-faq
    }
}