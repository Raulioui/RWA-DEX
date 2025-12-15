// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;


import {Test, console2} from "forge-std/Test.sol";
import {AssetPool} from "../../src/AssetPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainlinkCaller} from "../../src/ChainlinkCaller.sol";
import {BrokerDollar} from "../../src/BrokerDollar.sol";
import {MockChainlinkCaller} from "../mocks/MockChainlinkCaller.sol";
import {AssetToken} from "../../src/AssetToken.sol";
import {IGetChainlinkConfig} from "../../src/interfaces/IGetChainlinkConfig.sol";
import {IAssetToken} from "../../src/interfaces/IAssetToken.sol";
import {BrokerGovernanceToken} from "../../src/Governance/BrokerGovernanceToken.sol";

contract TestAssetToken is Test {
    AssetPool assetPool;
    AssetToken assetToken;
    MockChainlinkCaller chainlinkCaller;
    BrokerDollar brokerDollar;
    BrokerGovernanceToken bgt;

    // Test addresses
    address public user = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unregisteredUser = makeAddr("unregisteredUser");
    address public owner = makeAddr("owner");
    
    // Test constants
    string public constant TICKET = "TSLA";
    string public constant NAME = "Tesla Stock Token";
    string public constant ACCOUNT_ID = "test-account-123";
    string public constant ACCOUNT_ID_2 = "test-account-456";
    string public constant IMAGE_CID = "QmTestImageCID";

    string constant alpacaMintSource = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";
    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);
    
    uint256 public constant MINT_AMOUNT = 1000 * 1e6; // 1000 brokerDollar
    uint256 public constant TOKEN_AMOUNT = 10 * 1e18; // 10 Asset Tokens

    // Events for testing
    event RefundIssued(
        address indexed requester,
        uint256 amount,
        AssetToken.MintOrRedeem mintOrRedeem,
        string reason
    );
    
    event RequestSuccess(
        bytes32 indexed requestId,
        address indexed requester,
        uint256 tokenAmount,
        AssetToken.MintOrRedeem mintOrRedeem
    );
    
    event RequestExpired(
        bytes32 indexed requestId,
        address indexed requester,
        uint256 amount,
        AssetToken.MintOrRedeem mintOrRedeem
    );
    
    event RequestTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
    
    function setUp() public {
        chainlinkCaller = new MockChainlinkCaller();
        brokerDollar = new BrokerDollar();

        assetPool = new AssetPool(
            address(chainlinkCaller),
            address(brokerDollar)
        );

        brokerDollar.setAssetPool(address(assetPool));

        AssetToken assetTokenImplementation = new AssetToken();
        assetPool.initializeBeacon(address(assetTokenImplementation));

        chainlinkCaller.setJsSources(mintSource, sellSource);
        chainlinkCaller.setAssetPool(address(assetPool));

        bgt = new BrokerGovernanceToken();

        // Create first token
        address token = assetPool.createTokenRegistry(NAME, TICKET, IMAGE_CID);
        vm.stopPrank();

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        vm.stopPrank();

        assetToken = AssetToken(token);
    }

    /////////////////////
    // Constructor
    /////////////////////

    function testTokenCreation() public view {
        assertEq(assetToken.name(), NAME);
        assertEq(assetToken.symbol(), TICKET);
        assertEq(assetToken.assetPool(), address(assetPool));
        assertEq(assetToken.chainlinkCaller(), address(chainlinkCaller));

        (uint256 timeout, uint256 minTimeout, uint256 maxTimeout, uint256 maxBatchSize) = assetToken.getConfig();
        assertEq(timeout, 3600); // 1 hour default
        assertEq(minTimeout, 300); // 5 minutes
        assertEq(maxTimeout, 86400); // 24 hours
        assertEq(maxBatchSize, 50);
    }

    /////////////////////
    // Mint Asset
    /////////////////////

    function testRevertsMintIfCallerIsNotAssetPool() public {
        vm.expectRevert(AssetToken.NotAllowedToMint.selector);
        assetToken._mintAsset(MINT_AMOUNT, user, "accountId", TOKEN_AMOUNT);
    }

    function testMintAssetInToken() public {


        vm.startPrank(user); 
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.startPrank(address(chainlinkCaller));
        // Fulfill the request
        vm.expectEmit(true, true, true, true);
        emit RequestSuccess(requestId, user, TOKEN_AMOUNT, AssetToken.MintOrRedeem.mint);
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);
        
        // Assert individual fields
        assertEq(request.amount, MINT_AMOUNT);
        assertEq(request.requester, user);
        assertEq(uint256(request.mintOrRedeem), uint256(AssetToken.MintOrRedeem.mint));
        assertEq(uint256(request.status), uint256(AssetToken.RequestStatus.fulfilled));
        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        // Test timestamps
        assertTrue(request.deadline > block.timestamp);
        assertTrue(request.createdAt <= block.timestamp);
        assertEq(request.deadline, request.createdAt + assetToken.requestTimeout());
    }

    function testMintWithZeroTokenAmount() public {

        vm.startPrank(user);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit RefundIssued(user, MINT_AMOUNT, AssetToken.MintOrRedeem.mint, "API call failed or returned zero amount");
        
        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, 0, true); // Zero token amount

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);
        assertEq(uint256(request.status), uint256(AssetToken.RequestStatus.error));
        assertEq(assetToken.balanceOf(user), 0);
    }

    /////////////////////
    // Redeem Asset
    /////////////////////

    function testRevertsRedeemIfCallerIsNotAssetPool() public {
        vm.expectRevert(AssetToken.NotAllowedToMint.selector);
        assetToken._redeemAsset(MINT_AMOUNT, user, "accountId", TOKEN_AMOUNT);
    }

    function testRedeemAssetInToken() public {
        vm.startPrank(user); 
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        vm.startPrank(user);
        assetToken.approve(address(assetPool), TOKEN_AMOUNT);
        bytes32 requestIdRedeem = assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);
        
        vm.startPrank(address(chainlinkCaller));
        vm.expectEmit(true, true, true, true);
        emit RequestSuccess(requestIdRedeem, user, MINT_AMOUNT, AssetToken.MintOrRedeem.redeem);
        assetToken.onFulfill(requestIdRedeem, MINT_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), 0);
        assertEq(brokerDollar.balanceOf(user), brokerDollar.INITIAL_BALANCE());

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestIdRedeem);

        // Assert individual fields
        assertEq(request.amount, TOKEN_AMOUNT);
        assertEq(request.requester, user);
        assertEq(uint256(request.mintOrRedeem), uint256(AssetToken.MintOrRedeem.redeem));
        assertEq(uint256(request.status), uint256(AssetToken.RequestStatus.fulfilled));

        // Test timestamps
        assertTrue(request.deadline > block.timestamp);
        assertTrue(request.createdAt <= block.timestamp);
        assertEq(request.deadline, request.createdAt + assetToken.requestTimeout());
    }

    /////////////////////
    // Fullfillment
    /////////////////////

    function testRevertsIfCallerIsNotChainlinkCaller() public {
        vm.expectRevert(AssetToken.NotAllowedCaller.selector);
        assetToken.onFulfill(bytes32("test"), 1e18, true);
    }

    function testRevertsIfRequestExpired() public {


        vm.startPrank(user); 

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);

        // Simulate expired request
        vm.warp(block.timestamp + request.deadline + 1);

        vm.expectRevert(AssetToken.RequestExpiredError.selector);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, MINT_AMOUNT, true);
        vm.stopPrank();
    }

    function testRevertsIfRequestAlreadyProcessed() public {


        vm.startPrank(user); 

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);

        vm.expectRevert(AssetToken.RequestAlreadyProcessed.selector);
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
    }

    function testRefundMintIfRequestFailed() public {
        vm.startPrank(user); 

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, MINT_AMOUNT);

        // Mint completed
        assertEq(brokerDollar.balanceOf(user), brokerDollar.INITIAL_BALANCE() - MINT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit RefundIssued(user, MINT_AMOUNT, AssetToken.MintOrRedeem.mint, "API call failed or returned zero amount");

        vm.startPrank(address(chainlinkCaller));
        // Simulates an error in the Chainlink fulfillment
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, false);

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);
    }

    function testRefundRedeemIfRequestFailed() public {


        vm.startPrank(user); 

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        //brokerDollar.mint(address(assetToken), 10 * 1e18);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        vm.startPrank(user);

        assetToken.approve(address(assetPool), TOKEN_AMOUNT);
        bytes32 requestIdRedeem = assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        vm.expectEmit(true, true, true, true);
        emit RefundIssued(user, TOKEN_AMOUNT, AssetToken.MintOrRedeem.redeem, "API call failed or returned zero amount");

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestIdRedeem, MINT_AMOUNT, false);
        vm.stopPrank();

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestIdRedeem);

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);
        assertEq(uint256(request.status), uint256(AssetToken.RequestStatus.error));
    }

    /////////////////////
    // Clean Expired Requests
    /////////////////////

    function testRevertsIfBatchSizeIsLarge() public {
        uint256 invalidBatchSize = assetToken.MAX_CLEANUP_BATCH_SIZE() + 1;
        bytes32[] memory requestIds = new bytes32[](invalidBatchSize);
        vm.expectRevert(AssetToken.InvalidBatchSize.selector);
        assetToken.cleanupExpiredRequests(requestIds);
    }

    function testCleanUpExpiredRequests() public {
        // FIrst Request
        vm.startPrank(user); 
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId1 = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        // Second Request

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId2 = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        // Expire both requests
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId2);
        vm.warp(block.timestamp + request.deadline + 1);

        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        vm.expectEmit(true, true, true, true);
        emit RequestExpired(requestId1, user, MINT_AMOUNT, AssetToken.MintOrRedeem.mint);
        vm.expectEmit(true, true, true, true);
        emit RequestExpired(requestId2, user, MINT_AMOUNT, AssetToken.MintOrRedeem.mint);

        assetToken.cleanupExpiredRequests(requestIds);

        AssetToken.AssetRequest memory request1 = assetToken.getRequest(requestId1);
        AssetToken.AssetRequest memory request2 = assetToken.getRequest(requestId2);

        assertEq(uint256(request1.status), uint256(AssetToken.RequestStatus.expired));
        assertEq(uint256(request2.status), uint256(AssetToken.RequestStatus.expired));
        // Refund completed
        assertEq(brokerDollar.balanceOf(user),  brokerDollar.INITIAL_BALANCE());
    }

    function testCleanupDoesNotAffectNonExpiredRequests() public {

        vm.startPrank(user);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        // Don't advance time - request should not be expired
        assetToken.cleanupExpiredRequests(requestIds);

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);
        assertEq(uint256(request.status), uint256(AssetToken.RequestStatus.pending));
    }

    /////////////////////
    // Check Request Status
    /////////////////////

    function testCheckIfRequestExpired() public {


        vm.startPrank(user); 

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);

        // Simulate expired request
        vm.warp(block.timestamp + request.deadline + 1);

        bool isExpired = assetToken.isRequestExpired(requestId);
        assertTrue(isExpired);
    }

    function testGetTimeRemaining() public {

        vm.startPrank(user);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);
        uint256 timeRemaining = assetToken.getTimeRemaining(requestId);
        
        assertEq(timeRemaining, request.deadline - block.timestamp);

        // After expiration
        vm.warp(request.deadline + 1);
        timeRemaining = assetToken.getTimeRemaining(requestId);
        assertEq(timeRemaining, 0);
    }

    function testGetRequestWithStatus() public {

        vm.startPrank(user);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();

        (
            AssetToken.AssetRequest memory request,
            bool isExpired,
            uint256 timeRemaining
        ) = assetToken.getRequestWithStatus(requestId);

        assertFalse(isExpired);
        assertGt(timeRemaining, 0);
        assertEq(uint256(request.status), uint256(AssetToken.RequestStatus.pending));

        // After expiration
        vm.warp(request.deadline + 1);
        (, isExpired, timeRemaining) = assetToken.getRequestWithStatus(requestId);
        
        assertTrue(isExpired);
        assertEq(timeRemaining, 0);
    }

    /////////////////////
    // Set Request Timeout - Owner
    /////////////////////

    function testRevertsIfTimeoutIsTooLow() public {
        uint256 invalidTimeout = assetToken.MIN_TIMEOUT() - 1;
        vm.expectRevert(AssetToken.InvalidTimeout.selector);
        assetPool.setRequestTimeout(invalidTimeout, address(assetToken));
    }

    function testRevertsIfTimeoutIsTooHight() public {
        uint256 invalidTimeout = assetToken.MAX_TIMEOUT() + 1;
        vm.expectRevert(AssetToken.InvalidTimeout.selector);
        assetPool.setRequestTimeout(invalidTimeout, address(assetToken));
    }

    function testSetRequestTimeout() public {
        uint256 newTimeout = 7200; // 2 hours
        uint256 oldTimeout = assetToken.requestTimeout();

        vm.expectEmit(true, true, true, true);
        emit RequestTimeoutUpdated(oldTimeout, newTimeout);

        assetPool.setRequestTimeout(newTimeout, address(assetToken));
        vm.stopPrank();

        assertEq(assetToken.requestTimeout(), newTimeout);
    }

    /////////////////////
    // Expire stuck requests - Owner
    /////////////////////

    function testRevertsExpireRequestsIfNotOwner() public {
        bytes32[] memory requestIds = new bytes32[](1);
        vm.expectRevert();
        assetToken._expireRequests(requestIds);
    }

    function testExpireRequests() public {
        vm.startPrank(user); 

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);

        // brokerDollar transfered
        assertEq(brokerDollar.balanceOf(user), brokerDollar.INITIAL_BALANCE() - MINT_AMOUNT);

        // Simulate expired request
        vm.warp(block.timestamp + request.deadline + 1);

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        vm.startPrank(address(assetPool));
        assetToken._expireRequests(requestIds);
        vm.stopPrank();

        AssetToken.AssetRequest memory updatedRequest = assetToken.getRequest(requestId);
        assertEq(uint256(updatedRequest.status), uint256(AssetToken.RequestStatus.expired));

        // Refund completed
        assertEq(brokerDollar.balanceOf(user),  brokerDollar.INITIAL_BALANCE());
    }

    /////////////////////
    // Edge Cases and Security Tests
    /////////////////////

    function testMultipleUsersSimultaneous() public {
        // User 1 mint
        vm.startPrank(user);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId1 = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();

        // User 2 mint
        vm.startPrank(user2);
        assetPool.registerUser(ACCOUNT_ID_2);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId2 = assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();

        // Fulfill both
        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId1, TOKEN_AMOUNT, true);
        assetToken.onFulfill(requestId2, TOKEN_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);
        assertEq(assetToken.balanceOf(user2), TOKEN_AMOUNT);
    }

}