// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {AssetPool} from "../../src/AssetPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainlinkCaller} from "../../src/ChainlinkCaller.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockChainlinkCaller} from "../mocks/MockChainlinkCaller.sol";
import {AssetToken} from "../../src/AssetToken.sol";
import {
    IGetChainlinkConfig
} from "../../src/interfaces/IGetChainlinkConfig.sol";
import {DeployProtocolTest} from "../../script/deployProtocolTest.s.sol";
import {IAssetToken} from "../../src/interfaces/IAssetToken.sol";
import {UpgradedAssetToken} from "../mocks/UpgradedAssetToken.sol";

contract TestAssetPool is Test {
    AssetPool assetPool;
    AssetToken assetToken;
    DeployProtocolTest deployProtocol;
    MockChainlinkCaller chainlinkCaller;
    MockUSDC public usdt;

    // Test addresses
    address public user = makeAddr("user1");
    address public unregisteredUser = makeAddr("unregisteredUser");
    address public owner = makeAddr("owner");

    // Test constants
    string public constant TICKET = "TSLA";
    string public constant NAME = "Tesla Stock Token";
    string public constant ACCOUNT_ID = "test-account-123";
    string public constant IMAGE_CID = "QmTestImageCID";

    uint256 public constant MINT_AMOUNT = 1000 * 1e6; // 1000 USDT
    uint256 public constant TOKEN_AMOUNT = 10 * 1e18; // 10 Asset Tokens
    uint256 public constant INITIAL_USDT_BALANCE = 10000 * 1e6; // 10k USDT

    function setUp() public {
        deployProtocol = new DeployProtocolTest();

        IGetChainlinkConfig.GetChainlinkConfig
            memory chainlinkValues = deployProtocol.getChainlinkConfig();

        (address chainlinkCallerAddr, address assetPoolAddr) = deployProtocol
            .deployProtocol(
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

    function testConstructorSetsParameters() public view {
        assertEq(address(assetPool.usdt()), address(usdt));
        assertEq(assetPool.chainlinkCaller(), address(chainlinkCaller));
        assertEq(assetPool.owner(), address(deployProtocol));
    }

    /////////////////////
    // Initialization
    /////////////////////

    function testRevertsIfBeaconAlreadyInitialized() public {
        vm.startPrank(address(deployProtocol));
        vm.expectRevert("Beacon already initialized");
        assetPool.initializeBeacon(address(0x123));
        vm.stopPrank();
    }

    function testBeaconAlreadyInitializedAfterDeployment() public view {
        assertTrue(
            assetPool.getBeaconAddress() != address(0),
            "Beacon should be initialized after deployment"
        );

        assertTrue(
            assetPool.getCurrentImplementation() != address(0),
            "Implementation should be set after deployment"
        );
    }

    /////////////////////
    // Mint Asset
    /////////////////////

    function testReturnsIfUsdAmountIsZero() public {
        assetPool.registerUser(ACCOUNT_ID);
        vm.expectRevert(AssetPool.AmountOutOfBounds.selector);
        assetPool.mintAsset(0, TICKET, 0);
    }

    function testRevertsMintIfAssetIsNotRegistered() public {
        assetPool.registerUser(ACCOUNT_ID);
        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.redeemAsset(100 * 1e18, "NVDIA", 100 * 1e18);
    }

    function testRevertsIfAccountIdIsNotRegistered() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        usdt.approve(address(assetPool), MINT_AMOUNT);

        vm.expectRevert(AssetPool.UserNotRegistered.selector);
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testRevertsIfUsdAmountExceedsMax() public {
        usdt.mint(user, 10_000 * 1e18);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), 10_000 * 1e18);

        vm.expectRevert(AssetPool.AmountOutOfBounds.selector);
        assetPool.mintAsset(10_000 * 1e18, TICKET, 10_000 * 1e18);
    }

    function testRevertsIfUsdAmountBelowMin() public {
        usdt.mint(user, 1 * 1e6);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), 1 * 1e6);

        vm.expectRevert(AssetPool.AmountOutOfBounds.selector);
        assetPool.mintAsset(1 * 1e6, TICKET, 1 * 1e6);
    }

    function testRevertsMintForCooldown() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.expectRevert(AssetPool.RateLimited.selector);
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.stopPrank();
    }

    function testMintAsset() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        assertEq(usdt.balanceOf(address(assetToken)), MINT_AMOUNT);
        assertEq(usdt.balanceOf(user), 0);
        assertEq(assetPool.getUserRequests(user).length, 1);

        vm.startPrank(address(chainlinkCaller));

        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        vm.stopPrank();
    }

    /////////////////////
    // Redeem Asset
    /////////////////////

    function testRevertsIfAssetIsZero() public {
        assetPool.registerUser(ACCOUNT_ID);
        vm.expectRevert(AssetPool.InsufficientAmount.selector);
        assetPool.redeemAsset(0, TICKET, 0);
    }

    function testRevertsRedeemIfAssetIsNotRegistered() public {
        assetPool.registerUser(ACCOUNT_ID);
        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.redeemAsset(100 * 1e18, "NVDIA", 100 * 1e18);
    }

    function testRevertsIfUserNotRegistered() public {
        vm.startPrank(user);
        usdt.mint(user, MINT_AMOUNT); // TEMPORAL
        usdt.approve(address(assetPool), MINT_AMOUNT); // TEMPORAL

        vm.expectRevert(AssetPool.UserNotRegistered.selector);
        assetPool.redeemAsset(100 * 1e18, TICKET, 100 * 1e18);
        vm.stopPrank();
    }

    function testRevertsRedeemForCooldown() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        vm.startPrank(user);

        assetToken.approve(address(assetPool), TOKEN_AMOUNT);
        assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        vm.expectRevert(AssetPool.RateLimited.selector);
        assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        vm.stopPrank();
    }

    function testRedeemAsset() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        vm.startPrank(user);

        assetToken.approve(address(assetPool), TOKEN_AMOUNT);
        assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        assertEq(assetToken.balanceOf(user), 0);
        assertEq(assetToken.balanceOf(address(assetToken)), TOKEN_AMOUNT);
        assertEq(assetPool.getUserRequests(user).length, 2);

        vm.stopPrank();
    }

    /////////////////////
    // Register User
    /////////////////////

    function testRevertsIfAccountIdIsEmpty() public {
        vm.startPrank(user);
        vm.expectRevert(AssetPool.InvalidAccountId.selector);
        assetPool.registerUser("");
        vm.stopPrank();
    }

    function testRevertsIfUserAlreadyRegistered() public {
        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);
        vm.expectRevert(AssetPool.AlreadyRegistered.selector);
        assetPool.registerUser("anotherAccountId");
        vm.stopPrank();
    }

    function testRegisterUser() public {
        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        assertEq(assetPool.userToAccountId(user), ACCOUNT_ID);
        vm.stopPrank();
    }

    /////////////////////
    // Cleanup User Expired Requests
    /////////////////////

    function testCleanUpUserExpiredRequests() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        // Simulates expired request not calling onFullFill
        vm.warp(block.timestamp + assetToken.requestTimeout() + 1 minutes);

        assertEq(assetToken.isRequestExpired(requestId), true);

        string[] memory tickets = new string[](1);
        tickets[0] = TICKET;

        assetPool.cleanupUserExpiredRequests(user, tickets);

        assertEq(assetToken.isRequestExpired(requestId), false);
    }

    /////////////////////
    // Token Creation - Owner
    /////////////////////

    function testRevertsTokenCreationIfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert("Only callable by owner");
        assetPool.createTokenRegistry("NewToken", "NTK", IMAGE_CID);
    }

    function testRevertsIdTokenAlreadyExists() public {
        vm.startPrank(address(deployProtocol));
        vm.expectRevert(AssetPool.AssetAlreadyExists.selector);
        assetPool.createTokenRegistry(NAME, TICKET, IMAGE_CID);
    }

    function testCreatesToken() public view {
        (address assetAddress, , , ) = assetPool.assetInfo(TICKET);
        assertTrue(
            assetAddress != address(0),
            "Asset address should not be zero"
        );

        assertEq(chainlinkCaller.authorizedTokens(TICKET), assetAddress);

        assertEq(assetPool.getAllTokenTickets().length, 1);
        assertEq(assetPool.getAllTokenTickets()[0], TICKET);

        AssetToken token = AssetToken(assetAddress);
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), TICKET);
        assertEq(token.assetPool(), address(assetPool));
    }

    function testMultipleTokensShareSameImplementation() public {
        vm.startPrank(address(deployProtocol));
        
        address token1;
        try assetPool.createTokenRegistry("Apple", "dAAPL", "QmApple") returns (address addr) {
            token1 = addr;
        } catch {
            (token1, , , ) = assetPool.assetInfo("dAAPL");
        }
        
        address token2 = assetPool.createTokenRegistry("Google", "dGOOGL", "QmGoogle");
        address token3 = assetPool.createTokenRegistry("Microsoft", "dMSFT", "QmMicrosoft");
        
        vm.stopPrank();
        
        // Proxies address should be different
        assertTrue(token1 != token2, "Proxies should have different addresses");
        assertTrue(token2 != token3, "Proxies should have different addresses");
        assertTrue(token1 != token3, "Proxies should have different addresses");
        
        // All point to the same implementation 
        address implementation = assetPool.getCurrentImplementation();
        assertTrue(implementation != address(0), "Implementation should exist");
        
        assertEq(AssetToken(token1).name(), "Apple");
        assertEq(AssetToken(token2).name(), "Google");
        assertEq(AssetToken(token3).name(), "Microsoft");
    }

    /////////////////////
    // Upgrade All Asset Tokens - Owner
    /////////////////////

    function testRevertsIfImplementationAddressIsZero() public {
        vm.startPrank(address(deployProtocol));
        vm.expectRevert(AssetPool.InvalidImplementation.selector);
        assetPool.upgradeAllAssetTokens(address(0));
        vm.stopPrank();
    }

    /// @dev In the UpgradedAssetToken contract, we only changed the MIN_TIMEOUT constant for testing purposes
    /// old implementation has MIN_TIMEOUT = 300
    /// new implementation has MIN_TIMEOUT = 400
    function testUpgradeSuccesfull() public {
        uint256 oldTicketsNumber = assetPool.getAllTokenTickets().length;
        assertEq(oldTicketsNumber, 1, "There should be one registered token");
        address oldImplementation = assetPool.getCurrentImplementation();

        AssetPool.Asset memory asset = assetPool.getAssetInfo(TICKET);
        address proxyAddress = asset.assetAddress;
        assertTrue(proxyAddress != address(0), "Proxy token must exist");

        uint256 minTimeoutBefore = AssetToken(proxyAddress).MIN_TIMEOUT();
        assertEq(minTimeoutBefore, 300, "Proxy should see old MIN_TIMEOUT (300)");

        // Save some state to prove it's preserved across upgrade (example)
        string memory oldName = AssetToken(proxyAddress).name();

        UpgradedAssetToken upgradedImplementation = new UpgradedAssetToken();

        vm.startPrank(address(deployProtocol));
        assetPool.upgradeAllAssetTokens(address(upgradedImplementation));
        vm.stopPrank();

        address currentImplementation = assetPool.getCurrentImplementation();
        assertEq(
            currentImplementation,
            address(upgradedImplementation),
            "Beacon should point to new implementation"
        );

        assertEq(
            UpgradedAssetToken(address(upgradedImplementation)).MIN_TIMEOUT(),
            400,
            "New implementation MIN_TIMEOUT should be 400"
        );

        uint256 minTimeoutAfter = AssetToken(proxyAddress).MIN_TIMEOUT();
        assertEq(
            minTimeoutAfter,
            400,
            "Proxy should now see new MIN_TIMEOUT (400) after upgrade"
        );
    }

    /////////////////////
    // Set Request Timeout - Owner
    /////////////////////

    function testRevertsIfSetRequestTimeoutIfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert("Only callable by owner");
        assetPool.setRequestTimeout(300, address(assetToken));
    }

    function testSetRequestTimeout() public {
        uint256 requestTimeout = 400;
        vm.startPrank(address(deployProtocol));
        assetPool.setRequestTimeout(requestTimeout, address(assetToken));
        assertEq(assetToken.requestTimeout(), requestTimeout);
    }

    /////////////////////
    // Remove Token Registry - Owner
    /////////////////////

    function testRevertsIfRemoveTokenIfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert("Only callable by owner");
        assetPool.removeTokenRegistry(TICKET);
    }

    function testRevertsIfTokenDoesNotExist() public {
        vm.startPrank(address(deployProtocol));
        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.removeTokenRegistry("INVALID_TICKET");
    }

    function testRemoveToken() public {
        vm.startPrank(address(deployProtocol));
        assetPool.removeTokenRegistry(TICKET);
        vm.stopPrank();

        assertEq(assetPool.getAllTokenTickets().length, 0);
        assertEq(assetPool.getAssetInfo(TICKET).assetAddress, address(0));
    }

    /////////////////////
    // Expire Requests - Owner
    /////////////////////

    function testRevertsIfExpireRequestsIfNotOwner() public {
        vm.startPrank(user);
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = bytes32("0x123");
        vm.expectRevert();
        assetToken._expireRequests(requestIds);
    }

    function testExpireRequests() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        // Simulates expired request not calling onFullFill
        vm.warp(block.timestamp + assetToken.requestTimeout() + 1 minutes);

        assertEq(assetToken.isRequestExpired(requestId), true);

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        vm.startPrank(address(assetPool));
        assetToken._expireRequests(requestIds);
        vm.stopPrank();

        assertEq(assetToken.isRequestExpired(requestId), false);
    }

    /////////////////////
    // Emergency Pause - Owner
    /////////////////////

    function testMintFunctionPause() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        vm.startPrank(address(deployProtocol));
        assetPool.emergencyPause();
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.startPrank(address(deployProtocol));
        assetPool.unpause();

        vm.startPrank(user);
        bytes32 requestId2 = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        assertEq(usdt.balanceOf(address(assetToken)), MINT_AMOUNT);
        assertEq(usdt.balanceOf(user), 0);
        assertEq(assetPool.getUserRequests(user).length, 1);

        vm.startPrank(address(chainlinkCaller));

        assetToken.onFulfill(requestId2, TOKEN_AMOUNT, true);
        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);
    }

    function testRedeemFunctionPause() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        vm.warp(block.timestamp + assetPool.REQUEST_COOLDOWN());

        vm.startPrank(address(chainlinkCaller));
        assetToken.onFulfill(requestId, TOKEN_AMOUNT, true);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);

        vm.startPrank(address(deployProtocol));
        assetPool.emergencyPause();
        vm.stopPrank();

        vm.startPrank(user);

        assetToken.approve(address(assetPool), TOKEN_AMOUNT);

        vm.expectRevert();
        assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        vm.startPrank(address(deployProtocol));
        assetPool.unpause();
        vm.stopPrank();

        vm.startPrank(user);
        assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        assertEq(assetToken.balanceOf(user), 0);
        assertEq(assetToken.balanceOf(address(assetToken)), TOKEN_AMOUNT);
        assertEq(assetPool.getUserRequests(user).length, 2);

        vm.stopPrank();
    }

    /////////////////////
    // getUserPendingRequests Tests
    /////////////////////

    function testGetUserPendingRequestsEmptyForUnregisteredUser() public {
        // Simulates unregistered user
        vm.startPrank(owner);
        vm.expectRevert(AssetPool.UserNotRegistered.selector);
        assetPool.getUserPendingRequests(owner, TICKET);
    }

    function testGetUserPendingRequestsInvalidAsset() public {
        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.getUserPendingRequests(user, "INVALID_ASSET_TICKET");
    }

    function testGetUserPendingRequestsSingleRequest() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        uint256 _createdAt = block.timestamp;
        uint256 _deadline = _createdAt + assetToken.requestTimeout();

        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        // Get pending requests
        //IAssetToken.AssetRequest[] memory requests = assetPool.getUserPendingRequests(user, TICKET);
        /*
        assertEq(requests.length, 1);
        assertEq(requests[0].requester, user);
        assertEq(requests[0].deadline, _deadline);
        assertEq(requests[0].createdAt, _createdAt);*/
    }

    /////////////////////
    // checkUserExpiredRequests Tests
    /////////////////////

    function testCheckUserExpiredRequestsNoRequests() public {
        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        string[] memory tickets = new string[](1);
        tickets[0] = TICKET;

        (bool hasExpired, uint256 expiredCount) = assetPool
            .checkUserExpiredRequests(user, tickets);

        assertFalse(hasExpired);
        assertEq(expiredCount, 0);
    }

    function testCheckUserExpiredRequestsWithExpiredRequest() public {
        usdt.mint(user, MINT_AMOUNT);

        vm.startPrank(user);
        assetPool.registerUser(ACCOUNT_ID);

        usdt.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        // Simulates expired request not calling onFullFill
        vm.warp(block.timestamp + assetToken.requestTimeout() + 1 minutes);

        assertEq(assetToken.isRequestExpired(requestId), true);
    }
}
