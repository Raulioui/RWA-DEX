// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;


import {Test, console2} from "forge-std/Test.sol";
import {AssetPool} from "../../src/AssetPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainlinkCaller} from "../../src/ChainlinkCaller.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockChainlinkCaller} from "../mocks/MockChainlinkCaller.sol";
import {AssetToken} from "../../src/AssetToken.sol";
import {IGetChainlinkConfig} from "../../src/interfaces/IGetChainlinkConfig.sol";
import {DeployProtocolTest} from "../../script/deployProtocolTest.s.sol";
import {IAssetToken} from "../../src/interfaces/IAssetToken.sol";

contract TestAssetToken is Test {
    AssetPool assetPool;
    AssetToken assetToken;
    DeployProtocolTest deployProtocol;
    MockChainlinkCaller chainlinkCaller;
    MockUSDC public usdt;
    
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
    
    uint256 public constant MINT_AMOUNT = 1000 * 1e6; // 1000 USDT
    uint256 public constant TOKEN_AMOUNT = 10 * 1e18; // 10 Asset Tokens
    uint256 public constant INITIAL_USDT_BALANCE = 10000 * 1e6; // 10k USDT

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
        deployProtocol = new DeployProtocolTest();

        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = deployProtocol.getChainlinkConfig();

        (address chainlinkCallerAddr, address assetPoolAddr) = deployProtocol.deployProtocol(
            chainlinkValues.subId,
            chainlinkValues.functionsRouter,
            chainlinkValues.donId,
            chainlinkValues.usdt
        );

        usdt = MockUSDC(chainlinkValues.usdt);
        assetPool = AssetPool(assetPoolAddr);
        chainlinkCaller = MockChainlinkCaller(chainlinkCallerAddr);

        // Create first token
        vm.startPrank(address(deployProtocol));
        address token = assetPool.createTokenRegistry(NAME, TICKET, IMAGE_CID);
        vm.stopPrank();
        
        // Authorize tokens
        vm.startPrank(address(assetPool));
        chainlinkCaller.authorizeToken(TICKET, token);
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
        assetToken._mintAsset(MINT_AMOUNT, user, "accountId");
    }

    function testMintAssetInToken() public {
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);

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
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
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
        assetToken._redeemAsset(MINT_AMOUNT, user, "accountId");
    }

    function testRedeemAssetInToken() public {
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        vm.startPrank(user);
        assetToken.approve(address(assetPool), TOKEN_AMOUNT);
        bytes32 requestIdRedeem = assetPool.redeemAsset(TOKEN_AMOUNT, TICKET);
        
        vm.startPrank(address(chainlinkCaller));
        vm.expectEmit(true, true, true, true);
        emit RequestSuccess(requestIdRedeem, user, MINT_AMOUNT, AssetToken.MintOrRedeem.redeem);
        assetToken.onFulfill(requestIdRedeem, MINT_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), 0);
        assertEq(usdt.balanceOf(user), MINT_AMOUNT);

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
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);

        // Simulate expired request
        vm.warp(block.timestamp + request.deadline + 1);

        vm.expectRevert(AssetToken.RequestExpiredError.selector);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, MINT_AMOUNT, true);
        vm.stopPrank();
    }

    function testRevertsIfRequestAlreadyProcessed() public {
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);

        vm.expectRevert(AssetToken.RequestAlreadyProcessed.selector);
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
    }

    function testRefundMintIfRequestFailed() public {
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);

        // Mint completed
        assertEq(usdt.balanceOf(user), 0);

        vm.expectEmit(true, true, true, true);
        emit RefundIssued(user, MINT_AMOUNT, AssetToken.MintOrRedeem.mint, "API call failed or returned zero amount");

        vm.startPrank(address(chainlinkCaller));
        // Simulates an error in the Chainlink fulfillment
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, false);

        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);
    }

    function testRefundRedeemIfRequestFailed() public {
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        usdt.mint(address(assetToken), 10 * 1e18);

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        vm.startPrank(user);

        assetToken.approve(address(assetPool), TOKEN_AMOUNT);
        bytes32 requestIdRedeem = assetPool.redeemAsset(TOKEN_AMOUNT, TICKET);

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
        usdt.mint(user, MINT_AMOUNT); 

        // FIrst Request
        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId1 = assetPool.mintAsset(MINT_AMOUNT, TICKET);

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        // Second Request
        usdt.mint(user, MINT_AMOUNT); 
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId2 = assetPool.mintAsset(MINT_AMOUNT, TICKET);

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
        // Multiplied by 2 because there were two mint requests of the same user
        assertEq(usdt.balanceOf(user), 2 * MINT_AMOUNT);
    }

    function testCleanupDoesNotAffectNonExpiredRequests() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
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
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);

        // Simulate expired request
        vm.warp(block.timestamp + request.deadline + 1);

        bool isExpired = assetToken.isRequestExpired(requestId);
        assertTrue(isExpired);
    }

    function testGetTimeRemaining() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
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
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
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
        vm.startPrank(address(deployProtocol));
        uint256 invalidTimeout = assetToken.MIN_TIMEOUT() - 1;
        vm.expectRevert(AssetToken.InvalidTimeout.selector);
        assetPool.setRequestTimeout(invalidTimeout, address(assetToken));
    }

    function testRevertsIfTimeoutIsTooHight() public {
        vm.startPrank(address(deployProtocol));
        uint256 invalidTimeout = assetToken.MAX_TIMEOUT() + 1;
        vm.expectRevert(AssetToken.InvalidTimeout.selector);
        assetPool.setRequestTimeout(invalidTimeout, address(assetToken));
    }

    function testSetRequestTimeout() public {
        uint256 newTimeout = 7200; // 2 hours
        uint256 oldTimeout = assetToken.requestTimeout();

        vm.expectEmit(true, true, true, true);
        emit RequestTimeoutUpdated(oldTimeout, newTimeout);

        vm.startPrank(address(deployProtocol));
        assetPool.setRequestTimeout(newTimeout, address(assetToken));
        vm.stopPrank();

        assertEq(assetToken.requestTimeout(), newTimeout);
    }

    /////////////////////
    // Expire stuck requests - Owner
    /////////////////////

    function testRevertsExpireRequestsIfNotOwner() public {
        bytes32[] memory requestIds = new bytes32[](1);
        vm.expectRevert("Only callable by owner");
        assetToken._expireRequests(requestIds);
    }

    function testExpireRequests() public {
        usdt.mint(user, MINT_AMOUNT); 

        vm.startPrank(user); 
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        
        bytes32 requestId = assetPool.mintAsset(MINT_AMOUNT, TICKET);
        AssetToken.AssetRequest memory request = assetToken.getRequest(requestId);

        // Usdt transfered
        assertEq(usdt.balanceOf(user), 0);

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
        assertEq(usdt.balanceOf(user), MINT_AMOUNT);
    }

    /////////////////////
    // Edge Cases and Security Tests
    /////////////////////

    function testMultipleUsersSimultaneous() public {
        usdt.mint(user, MINT_AMOUNT);
        usdt.mint(user2, MINT_AMOUNT);

        // User 1 mint
        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId1 = assetPool.mintAsset(MINT_AMOUNT, TICKET);
        vm.stopPrank();

        // User 2 mint
        vm.startPrank(user2);
        assetPool.registerUser(ACCOUNT_ID_2);
        usdt.approve(address(assetPool), MINT_AMOUNT);
        bytes32 requestId2 = assetPool.mintAsset(MINT_AMOUNT, TICKET);
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