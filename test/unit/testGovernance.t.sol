// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {AssetPool} from "../../src/AssetPool.sol";
import {BrokerDollar} from "../../src/BrokerDollar.sol";
import {AssetToken} from "../../src/AssetToken.sol";
import {MockChainlinkCaller} from "../mocks/MockChainlinkCaller.sol";
import {IGetChainlinkConfig} from "../../src/interfaces/IGetChainlinkConfig.sol";

// Governance
import {BrokerGovernanceToken} from "../../src/Governance/BrokerGovernanceToken.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {RWAGovernor} from "../../src/Governance/RWAGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {DeployProtocolTest} from "../../script/deployProtocolTest.s.sol";

contract TestGovernance is Test {
    AssetPool public assetPool;
    BrokerDollar public brokerDollar;
    MockChainlinkCaller public chainlinkCaller;
    BrokerGovernanceToken public bgt;
    TimelockController public timelock;
    RWAGovernor public governor;

    DeployProtocolTest public deployProtocol;

    address public userA;
    address public userB;

    // Test constants
    string public constant TICKET    = "TSLA";
    string public constant NAME      = "Tesla Stock Token";
    string public constant IMAGE_CID = "QmTestImageCID";

    function setUp() public {
        deployProtocol = new DeployProtocolTest();

        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = deployProtocol.getChainlinkConfig();

        (
            address chainlinkCallerAddr,
            address assetPoolAddr,
            address brokerDollarAddr,
            address bgtAddr,
            address timelockAddr,
            address governorAddr,
            address userAAddr,
            address userBAddr
        ) = deployProtocol.deployProtocol(
            chainlinkValues.subId,
            chainlinkValues.functionsRouter,
            chainlinkValues.donId
        );

        assetPool      = AssetPool(assetPoolAddr);
        brokerDollar   = BrokerDollar(brokerDollarAddr);
        chainlinkCaller = MockChainlinkCaller(chainlinkCallerAddr);
        bgt            = BrokerGovernanceToken(bgtAddr);
        timelock       = TimelockController(payable(timelockAddr));
        governor       = RWAGovernor(payable(governorAddr));

        userA = userAAddr;
        userB = userBAddr;

        // Delegate voting power to themselves so they can vote
        vm.prank(userA);
        bgt.delegate(userA);

        vm.prank(userB);
        bgt.delegate(userB);

        vm.prank(userA);
        assetPool.registerUser("ACCOUNT_ID");
    }

    //////////////////////////////////////
    // Constructor wiring
    //////////////////////////////////////

    function testConstructorSetsParameters() public view {
        assertEq(address(assetPool.brokerDollar()), address(brokerDollar), "Wrong BrokerDollar");
        assertEq(assetPool.chainlinkCaller(), address(chainlinkCaller),     "Wrong ChainlinkCaller");
        assertEq(assetPool.owner(), address(timelock),                      "Owner must be Timelock");
    }

    //////////////////////////////////////
    // Direct access restriction
    //////////////////////////////////////

    function testDirectCreateTokenRegistryRevertsForNonOwner() public {
        vm.prank(userA);
        vm.expectRevert(); // ConfirmedOwner will revert for not being owner
        assetPool.createTokenRegistry(NAME, TICKET, IMAGE_CID);
    }

    //////////////////////////////////////
    // Full governance flow:
    // propose -> vote -> queue -> execute
    //////////////////////////////////////

    function testGovernanceCanCreateTokenRegistry() public {
        // Verify that TSLA is now registered in AssetPool
        AssetPool.Asset memory asset = _createToken();

        assertTrue(asset.assetAddress != address(0), "Asset should be registered");
        assertEq(asset.name, NAME,        "Asset name mismatch");
        assertEq(asset.uri,  IMAGE_CID,   "Asset image CID mismatch");
    }

    function testProposalDefeatedIfNoVotes() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) =
            _buildCreateTokenProposal();

        vm.prank(userA);
        uint256 proposalId = governor.propose(targets, values, calldatas, "No votes test");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Defeated),
            "Proposal without votes should be Defeated"
        );
    }

    function testGovernanceCanSetRequestTimeout() public {
        AssetPool.Asset memory asset = _createToken();

        // build proposal
        address[] memory targetsRequest = new address[](1);
        targetsRequest[0] = address(assetPool);

        uint256[] memory valuesRequest = new uint256[](1);
        valuesRequest[0] = 0;

        uint256 newTimeout = 4000;

        bytes[] memory calldatasRequest = new bytes[](1);
        calldatasRequest[0] = abi.encodeWithSignature(
            "setRequestTimeout(uint256,address)",
            newTimeout,
            asset.assetAddress
        );

        string memory descriptionRequest = "Update request timeout";

        vm.prank(userA);
        uint256 proposalIdRequest = governor.propose(targetsRequest, valuesRequest, calldatasRequest, descriptionRequest);

        // Move forward past the voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        //  userA and userB vote "For" (1)
        vm.prank(userA);
        governor.castVote(proposalIdRequest, 1); // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(userB);
        governor.castVote(proposalIdRequest, 1);

        // Move forward past the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the proposal is succeeded
        assertEq(
            uint8(governor.state(proposalIdRequest)),
            uint8(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        // Queue the proposal in the Timelock
        bytes32 descriptionHashRequest = keccak256(bytes(descriptionRequest));

        vm.prank(userA);
        governor.queue(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        // Jump time forward to satisfy minDelay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute the proposal
        vm.prank(userA);
        governor.execute(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        (
            uint256 timeout,
            uint256 minTimeout,
            uint256 maxTimeout,
            uint256 maxBatchSize
        ) = AssetToken(asset.assetAddress).getConfig();

        assertEq(
            timeout,
            newTimeout,
            "Request timeout should be updated"
        );
    }

    function testGovernanceCanRemoveToken() public {
        AssetPool.Asset memory asset = _createToken();

        // build proposal
        address[] memory targetsRequest = new address[](1);
        targetsRequest[0] = address(assetPool);

        uint256[] memory valuesRequest = new uint256[](1);
        valuesRequest[0] = 0;

        bytes[] memory calldatasRequest = new bytes[](1);
        calldatasRequest[0] = abi.encodeWithSignature(
            "removeTokenRegistry(string)",
            TICKET
        );

        string memory descriptionRequest = "Remove token registry";

        vm.prank(userA);
        uint256 proposalIdRequest = governor.propose(targetsRequest, valuesRequest, calldatasRequest, descriptionRequest);

        // Move forward past the voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        //  userA and userB vote "For" (1)
        vm.prank(userA);
        governor.castVote(proposalIdRequest, 1); // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(userB);
        governor.castVote(proposalIdRequest, 1);

        // Move forward past the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the proposal is succeeded
        assertEq(
            uint8(governor.state(proposalIdRequest)),
            uint8(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        // Queue the proposal in the Timelock
        bytes32 descriptionHashRequest = keccak256(bytes(descriptionRequest));

        vm.prank(userA);
        governor.queue(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        // Jump time forward to satisfy minDelay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute the proposal
        vm.prank(userA);
        governor.execute(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        AssetPool.Asset memory removedAsset = assetPool.getAssetInfo(TICKET);
        assertTrue(removedAsset.assetAddress == address(0), "Asset should be removed");

    }

    function testGovernanceCanPauseAndUnpause() public {
        // build proposal
        address[] memory targetsRequest = new address[](1);
        targetsRequest[0] = address(assetPool);

        uint256[] memory valuesRequest = new uint256[](1);
        valuesRequest[0] = 0;

        bytes[] memory calldatasRequest = new bytes[](1);
        calldatasRequest[0] = abi.encodeWithSignature(
            "emergencyPause()"
        );

        string memory descriptionRequest = "Pause AssetPool";

        vm.prank(userA);
        uint256 proposalIdRequest = governor.propose(targetsRequest, valuesRequest, calldatasRequest, descriptionRequest);

        // Move forward past the voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        //  userA and userB vote "For" (1)
        vm.prank(userA);
        governor.castVote(proposalIdRequest, 1); // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(userB);
        governor.castVote(proposalIdRequest, 1);

        // Move forward past the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the proposal is succeeded
        assertEq(
            uint8(governor.state(proposalIdRequest)),
            uint8(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        // Queue the proposal in the Timelock
        bytes32 descriptionHashRequest = keccak256(bytes(descriptionRequest));

        vm.prank(userA);
        governor.queue(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        // Jump time forward to satisfy minDelay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute the proposal
        vm.prank(userA);
        governor.execute(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        assertTrue(assetPool.paused(), "AssetPool should be paused");

        // build proposal
        address[] memory targetsUnPause = new address[](1);
        targetsUnPause[0] = address(assetPool);

        uint256[] memory valuesUnPause = new uint256[](1);
        valuesUnPause[0] = 0;

        bytes[] memory calldatasUnPause = new bytes[](1);
        calldatasUnPause[0] = abi.encodeWithSignature(
            "unpause()"
        );

        string memory descriptionUnPause = "Un Pause AssetPool";

        vm.prank(userA);
        uint256 proposalIdUnPause = governor.propose(targetsUnPause, valuesUnPause, calldatasUnPause, descriptionUnPause);

        // Move forward past the voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        //  userA and userB vote "For" (1)
        vm.prank(userA);
        governor.castVote(proposalIdUnPause, 1); // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(userB);
        governor.castVote(proposalIdUnPause, 1);

        // Move forward past the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the proposal is succeeded
        assertEq(
            uint8(governor.state(proposalIdUnPause)),
            uint8(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        // Queue the proposal in the Timelock
        bytes32 descriptionHashUnPause = keccak256(bytes(descriptionUnPause));

        vm.prank(userA);
        governor.queue(
            targetsUnPause,
            valuesUnPause,
            calldatasUnPause,
            descriptionHashUnPause
        );

        // Jump time forward to satisfy minDelay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute the proposal
        vm.prank(userA);
        governor.execute(
            targetsUnPause,
            valuesUnPause,
            calldatasUnPause,
            descriptionHashUnPause
        );

        assertFalse(assetPool.paused(), "AssetPool should be unpaused");
    }

    function testGovernanceCanUpgreadeToken() public {
        // build proposal
        address[] memory targetsRequest = new address[](1);
        targetsRequest[0] = address(assetPool);

        uint256[] memory valuesRequest = new uint256[](1);
        valuesRequest[0] = 0;

        AssetToken newAssetTokenImplementation = new AssetToken();

        bytes[] memory calldatasRequest = new bytes[](1);
        calldatasRequest[0] = abi.encodeWithSignature(
            "upgradeAllAssetTokens(address)",
            address(newAssetTokenImplementation)
        );

        string memory descriptionRequest = "Update request timeout";

        vm.prank(userA);
        uint256 proposalIdRequest = governor.propose(targetsRequest, valuesRequest, calldatasRequest, descriptionRequest);

        // Move forward past the voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        //  userA and userB vote "For" (1)
        vm.prank(userA);
        governor.castVote(proposalIdRequest, 1); // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(userB);
        governor.castVote(proposalIdRequest, 1);

        // Move forward past the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the proposal is succeeded
        assertEq(
            uint8(governor.state(proposalIdRequest)),
            uint8(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        // Queue the proposal in the Timelock
        bytes32 descriptionHashRequest = keccak256(bytes(descriptionRequest));

        vm.prank(userA);
        governor.queue(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        // Jump time forward to satisfy minDelay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute the proposal
        vm.prank(userA);
        governor.execute(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        assertEq(
            address(assetPool.getCurrentImplementation()),
            address(newAssetTokenImplementation),
            "AssetToken implementation should be updated"
        );
    }

    function _createToken() public returns(AssetPool.Asset memory) {
        vm.prank(userA);
        address target = address(assetPool);
        uint256 value  = 0;
        bytes memory callData = abi.encodeWithSignature(
            "createTokenRegistry(string,string,string)",
            NAME,
            TICKET,
            IMAGE_CID
        );

        string memory description = "Add TSLA asset to AssetPool";

        address[] memory targets = new address[](1);
        targets[0] = target;

        uint256[] memory values = new uint256[](1);
        values[0] = value;

        bytes[] memory calldatas = new bytes[](1);

    
        proposalId = governor.propose(targets, values, calldatas, "Add TSLA asset to AssetPool");

        vm.roll(block.number + governor.votingDelay() + 1);

        governor.castVote(proposalId, 1);

        vm.prank(userB);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes("Add TSLA asset to AssetPool"));

        vm.prank(userA);
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        return assetPool.getAssetInfo(TICKET);
    }

    function _makePropose(
        address[] memory targetsRequest,
        uint256[] memory valuesRequest,
        bytes[] memory calldatasRequest,
        string memory descriptionRequest
    ) public {
        vm.prank(userA);
        uint256 proposalIdRequest = governor.propose(targetsRequest, valuesRequest, calldatasRequest, descriptionRequest);

        // Move forward past the voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        //  userA and userB vote "For" (1)
        governor.castVote(proposalIdRequest, 1); // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(userB);
        governor.castVote(proposalIdRequest, 1);

        // Move forward past the voting period
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the proposal is succeeded
        assertEq(
            uint8(governor.state(proposalIdRequest)),
            uint8(IGovernor.ProposalState.Succeeded),
            "Proposal should be Succeeded"
        );

        // Queue the proposal in the Timelock
        bytes32 descriptionHashRequest = keccak256(bytes(descriptionRequest));

        vm.prank(userA);
        governor.queue(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );

        // Jump time forward to satisfy minDelay
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Execute the proposal
        governor.execute(
            targetsRequest,
            valuesRequest,
            calldatasRequest,
            descriptionHashRequest
        );
    }
}
