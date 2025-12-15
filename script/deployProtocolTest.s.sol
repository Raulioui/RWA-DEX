// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {HelperConfig} from "./HelperConfig.sol";
import {AssetPool} from "../src/AssetPool.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {MockChainlinkCaller} from "../test/mocks/MockChainlinkCaller.sol";
import {BrokerDollar} from "../src/BrokerDollar.sol";

// Governance
import {BrokerGovernanceToken} from "../src/Governance/BrokerGovernanceToken.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {RWAGovernor} from "../src/Governance/RWAGovernor.sol";
import {IGetChainlinkConfig} from "../src/interfaces/IGetChainlinkConfig.sol";

contract DeployProtocolTest is Script {
    string constant alpacaMintSource = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";
    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);

    function run() external {
        // You still call this, even if MockChainlinkCaller ignores it
        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = getChainlinkConfig();

        vm.startBroadcast();

        (
            address chainlinkCallerAddr,
            address assetPoolAddr,
            address brokerDollarAddr,
            address bgtAddr,
            address timelockAddr,
            address governorAddr,
            address userA,
            address userB
        ) = deployProtocol(
            chainlinkValues.subId,
            chainlinkValues.functionsRouter,
            chainlinkValues.donId
        );

        vm.stopBroadcast();
    }

    function getChainlinkConfig()
        public
        returns (IGetChainlinkConfig.GetChainlinkConfig memory)
    {
        HelperConfig helperConfig = new HelperConfig();
        (
            address functionsRouter,
            bytes32 donId,
            uint64 subId
        ) = helperConfig.activeNetworkConfig();

        if (functionsRouter == address(0) || donId == bytes32(0) || subId == 0) {
            revert("something is wrong");
        }

        return IGetChainlinkConfig.GetChainlinkConfig(
            subId,
            functionsRouter,
            donId
        );
    }

    function deployProtocol(
    uint64 _subId,
    address _functionsRouter,
    bytes32 _donID
)
    public
    returns (
        address chainlinkCallerAddr,
        address assetPoolAddr,
        address brokerDollarAddr,
        address bgtAddr,
        address timelockAddr,
        address governorAddr,
        address userA,
        address userB
    )
{
    // --- Test users ---
    userA = vm.addr(1);
    userB = vm.addr(2);

    // --- Core protocol (test) ---
    MockChainlinkCaller chainlinkCaller = new MockChainlinkCaller();
    BrokerDollar brokerDollar = new BrokerDollar();

    AssetPool assetPool = new AssetPool(
        address(chainlinkCaller),
        address(brokerDollar)
    );

    brokerDollar.setAssetPool(address(assetPool));

    AssetToken assetTokenImplementation = new AssetToken();
    assetPool.initializeBeacon(address(assetTokenImplementation));

    chainlinkCaller.setJsSources(mintSource, sellSource);
    chainlinkCaller.setAssetPool(address(assetPool));

    BrokerGovernanceToken bgt = new BrokerGovernanceToken();

    // --- Timelock + Governor ---
    uint256 minDelay = 2 days;

    address[] memory proposers = new address[](1);
    proposers[0] = address(this); // this script is proposer
    address[] memory executors = new address[](0); // anyone can be executor

    TimelockController timelock = new TimelockController(
        minDelay,
        proposers,
        executors,
        address(this) // this script is DEFAULT_ADMIN_ROLE
    );

    RWAGovernor governor = new RWAGovernor(
        bgt,
        timelock
    );

    bytes32 PROPOSER_ROLE  = timelock.PROPOSER_ROLE();
    bytes32 EXECUTOR_ROLE  = timelock.EXECUTOR_ROLE();
    bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();

    timelock.grantRole(PROPOSER_ROLE,  address(governor));
    timelock.grantRole(CANCELLER_ROLE, address(governor));
    timelock.grantRole(EXECUTOR_ROLE,  address(0)); // anyone can execute

    // --- BGT distribution ---
    bgt.transfer(address(timelock), 500_000 ether);
    bgt.transfer(userA,             250_000 ether);
    bgt.transfer(userB,             250_000 ether);

    // --- Ownership: transfer + accept (two-step ConfirmedOwner) ---

    // step 1: current owner (this contract) sets pending owner
    assetPool.transferOwnership(address(timelock));

    // step 2: timelock accepts ownership
    vm.prank(address(timelock));
    assetPool.acceptOwnership();

    // --- Return addresses ---

    chainlinkCallerAddr = address(chainlinkCaller);
    assetPoolAddr       = address(assetPool);
    brokerDollarAddr    = address(brokerDollar);
    bgtAddr             = address(bgt);
    timelockAddr        = address(timelock);
    governorAddr        = address(governor);

    return (
        chainlinkCallerAddr,
        assetPoolAddr,
        brokerDollarAddr,
        bgtAddr,
        timelockAddr,
        governorAddr,
        userA,
        userB
    );
}

}
