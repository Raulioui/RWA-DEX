// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";

import {AssetPool} from "../src/AssetPool.sol";
import {ChainlinkCaller} from "../src/ChainlinkCaller.sol";
import {IGetChainlinkConfig} from "../src/interfaces/IGetChainlinkConfig.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {BrokerDollar} from "../src/BrokerDollar.sol";
import {BrokerGovernanceToken} from "../src/Governance/BrokerGovernanceToken.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {RWAGovernor} from "../src/Governance/RWAGovernor.sol";

contract DeployProtocol is Script {
    string constant ALPACA_MINT_SOURCE   = "./functions/sources/mintAsset.js";
    string constant ALPACA_REDEEM_SOURCE = "./functions/sources/redeemAsset.js";

    function run() external {
        IGetChainlinkConfig.GetChainlinkConfig memory cfg = getChainlinkConfig();

        string memory mintSource = vm.readFile(ALPACA_MINT_SOURCE);
        string memory redeemSource = vm.readFile(ALPACA_REDEEM_SOURCE);

        vm.startBroadcast();

        (
            ChainlinkCaller chainlinkCaller,
            AssetPool assetPool,
            BrokerDollar brokerDollar,
            BrokerGovernanceToken bgt,
            TimelockController timelock,
            RWAGovernor governor
        ) = deployProtocol(cfg.subId, cfg.functionsRouter, cfg.donId, mintSource, redeemSource);

        vm.stopBroadcast();
    }

    function getChainlinkConfig()
        public
        returns (IGetChainlinkConfig.GetChainlinkConfig memory)
    {
        HelperConfig helperConfig = new HelperConfig();
        (address functionsRouter, bytes32 donId, uint64 subId) = helperConfig.activeNetworkConfig();

        require(functionsRouter != address(0), "functionsRouter=0");
        require(donId != bytes32(0), "donId=0");
        require(subId != 0, "subId=0");

        return IGetChainlinkConfig.GetChainlinkConfig(subId, functionsRouter, donId);
    }

    function deployProtocol(
        uint64 subId,
        address functionsRouter,
        bytes32 donId,
        string memory mintSource,
        string memory redeemSource
    )
        internal
        returns (
            ChainlinkCaller chainlinkCaller,
            AssetPool assetPool,
            BrokerDollar brokerDollar,
            BrokerGovernanceToken bgt,
            TimelockController timelock,
            RWAGovernor governor
        )
    {
        // 1) Internal tokens
        brokerDollar = new BrokerDollar();
        bgt = new BrokerGovernanceToken();

        // 2) Chainlink Functions caller
        chainlinkCaller = new ChainlinkCaller(subId, functionsRouter, donId);

        // 3) AssetPool (initial owner = msg.sender (EOA broadcasting))
        assetPool = new AssetPool(address(chainlinkCaller), address(brokerDollar));

        // 4) Wire BrokerDollar <-> AssetPool
        brokerDollar.setAssetPool(address(assetPool));

        // 5) Beacon implementation for AssetToken
        AssetToken impl = new AssetToken();
        assetPool.initializeBeacon(address(impl));

        // 6) Configure ChainlinkCaller
        chainlinkCaller.setJsSources(mintSource, redeemSource);
        chainlinkCaller.setAssetPool(address(assetPool));

        // 7) Timelock (DEMO MODE: 0 delay)

uint256 minDelay = 0;
address[] memory proposers = new address[](0);
address[] memory executors = new address[](1); // ← Fix: size 1
executors[0] = address(0); // anyone can execute

timelock = new TimelockController(
    minDelay,
    proposers,
    executors,
    msg.sender // admin initially (deployer EOA)
);

        // 8) Governor
        governor = new RWAGovernor(bgt, timelock);

        // 9) Timelock roles
        bytes32 PROPOSER_ROLE  = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE  = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        bytes32 ADMIN_ROLE     = timelock.DEFAULT_ADMIN_ROLE();

        // Governor can propose + cancel
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));

        // execution is already open via constructor, but this is fine:
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        // IMPORTANT: allow deployer to schedule once (bootstrap)
        timelock.grantRole(PROPOSER_ROLE, msg.sender);

        // 10) Treasury funding (adjust to your supply/decimals)
        bgt.transfer(address(timelock), 500_000 ether);

        // 11) Transfer AssetPool ownership to timelock (ConfirmedOwner = 2-step)
        assetPool.transferOwnership(address(timelock));

        // 12) Timelock schedules + executes acceptOwnership() on AssetPool
        bytes32 salt = keccak256("accept-assetpool-ownership");
        bytes memory data = abi.encodeWithSignature("acceptOwnership()");

        timelock.schedule(
            address(assetPool),
            0,
            data,
            bytes32(0),
            salt,
            timelock.getMinDelay()
        );

        timelock.execute(
            address(assetPool),
            0,
            data,
            bytes32(0),
            salt
        );

        require(assetPool.owner() == address(timelock), "AssetPool owner != timelock");

        // 13) Clean up bootstrap proposer (optional but good practice)
        timelock.revokeRole(PROPOSER_ROLE, msg.sender);

        // 14) Remove deployer as admin (leave governance in control)
        timelock.revokeRole(ADMIN_ROLE, msg.sender);

        return (chainlinkCaller, assetPool, brokerDollar, bgt, timelock, governor);
    }
}
