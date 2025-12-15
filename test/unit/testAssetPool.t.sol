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
import {UpgradedAssetToken} from "../mocks/UpgradedAssetToken.sol";
import {BrokerGovernanceToken} from "../../src/Governance/BrokerGovernanceToken.sol";

contract TestAssetPool is Test {
    AssetPool assetPool;
    AssetToken assetToken;
    MockChainlinkCaller chainlinkCaller;
    BrokerDollar public brokerDollar;
    BrokerGovernanceToken public bgt;

    // Test addresses
    address public user = makeAddr("user1");
    address public unregisteredUser = makeAddr("unregisteredUser");
    address public owner = makeAddr("owner");

    // Test constants
    string public constant TICKET = "TSLA";
    string public constant NAME = "Tesla Stock Token";
    string public constant ACCOUNT_ID = "test-account-123";
    string public constant IMAGE_CID = "QmTestImageCID";

    string constant alpacaMintSource = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";
    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);

    uint256 public constant MINT_AMOUNT = 1000 * 1e6; // 1000 brokerDollar
    uint256 public constant TOKEN_AMOUNT = 10 * 1e18; // 10 Asset Tokens

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

    function testConstructorSetsParameters() public view {
        assertEq(address(assetPool.brokerDollar()), address(brokerDollar));
        assertEq(assetPool.chainlinkCaller(), address(chainlinkCaller));
        assertEq(assetPool.owner(), address(this));
    }

    /////////////////////
    // Initialization
    /////////////////////

    function testRevertsIfBeaconAlreadyInitialized() public {
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
        vm.startPrank(user);
        vm.expectRevert(AssetPool.AmountOutOfBounds.selector);
        assetPool.mintAsset(0, TICKET, 0);
    }

    function testRevertsMintIfAssetIsNotRegistered() public {
        vm.startPrank(user);
        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.redeemAsset(100 * 1e18, "NVDIA", 100 * 1e18);
    }

    function testRevertsIfAccountIdIsNotRegistered() public {
        vm.startPrank(unregisteredUser);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

        vm.expectRevert(AssetPool.UserNotRegistered.selector);
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testRevertsIfUsdAmountExceedsMax() public {
        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), 10_000 * 1e18);

        vm.expectRevert(AssetPool.AmountOutOfBounds.selector);
        assetPool.mintAsset(10_000 * 1e18, TICKET, 10_000 * 1e18);
    }

    function testRevertsIfUsdAmountBelowMin() public {
        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), 1 * 1e6);

        vm.expectRevert(AssetPool.AmountOutOfBounds.selector);
        assetPool.mintAsset(1 * 1e6, TICKET, 1 * 1e6);
    }

    function testRevertsMintForCooldown() public {
        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.expectRevert(AssetPool.RateLimited.selector);
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.stopPrank();
    }

    function testMintAsset() public {
        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

        bytes32 requestId = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        assertEq(brokerDollar.balanceOf(address(assetToken)), MINT_AMOUNT);
        assertEq(brokerDollar.balanceOf(user), brokerDollar.INITIAL_BALANCE() - MINT_AMOUNT);
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
        vm.startPrank(user);
        vm.expectRevert(AssetPool.InsufficientAmount.selector);
        assetPool.redeemAsset(0, TICKET, 0);
    }

    function testRevertsRedeemIfAssetIsNotRegistered() public {
        vm.startPrank(user);
        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.redeemAsset(100 * 1e18, "NVDIA", 100 * 1e18);
    }

    function testRevertsIfUserNotRegistered() public {
        address unregisteredUser = makeAddr("unregisteredUser");
        vm.startPrank(unregisteredUser);
        brokerDollar.approve(address(assetPool), MINT_AMOUNT); // TEMPORAL

        vm.expectRevert(AssetPool.UserNotRegistered.selector);
        assetPool.redeemAsset(100 * 1e18, TICKET, 100 * 1e18);
        vm.stopPrank();
    }

    function testRevertsRedeemForCooldown() public {

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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
        vm.expectRevert(AssetPool.AlreadyRegistered.selector);
        assetPool.registerUser("anotherAccountId");
        vm.stopPrank();
    }

    function testRegisterUser() public {
        vm.startPrank(user);

        assertEq(assetPool.userToAccountId(user), ACCOUNT_ID);
        vm.stopPrank();
    }

    /////////////////////
    // Cleanup User Expired Requests
    /////////////////////

    function testCleanUpUserExpiredRequests() public {

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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
        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.removeTokenRegistry("INVALID_TICKET");
    }

    function testRemoveToken() public {
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

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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
        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

        vm.startPrank(address(this));
        assetPool.emergencyPause();
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        assetPool.mintAsset(MINT_AMOUNT, TICKET, TOKEN_AMOUNT);

        vm.startPrank(address(this));
        assetPool.unpause();
        vm.stopPrank();

        vm.startPrank(user);
        bytes32 requestId2 = assetPool.mintAsset(
            MINT_AMOUNT,
            TICKET,
            TOKEN_AMOUNT
        );

        assertEq(brokerDollar.balanceOf(address(assetToken)), MINT_AMOUNT);
        assertEq(brokerDollar.balanceOf(user), brokerDollar.INITIAL_BALANCE() - MINT_AMOUNT);
        assertEq(assetPool.getUserRequests(user).length, 1);

        vm.startPrank(address(chainlinkCaller));

        assetToken.onFulfill(requestId2, TOKEN_AMOUNT, true);
        assertEq(assetToken.balanceOf(user), TOKEN_AMOUNT);
    }

    function testRedeemFunctionPause() public {

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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

        vm.startPrank(address(this));
        assetPool.emergencyPause();
        vm.stopPrank();

        vm.startPrank(user);
        assetToken.approve(address(assetPool), TOKEN_AMOUNT);

        vm.expectRevert();
        assetPool.redeemAsset(TOKEN_AMOUNT, TICKET, MINT_AMOUNT);

        vm.startPrank(address(this));
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

        vm.expectRevert(AssetPool.InvalidAsset.selector);
        assetPool.getUserPendingRequests(user, "INVALID_ASSET_TICKET");
    }

    function testGetUserPendingRequestsSingleRequest() public {

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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

        string[] memory tickets = new string[](1);
        tickets[0] = TICKET;

        (bool hasExpired, uint256 expiredCount) = assetPool
            .checkUserExpiredRequests(user, tickets);

        assertFalse(hasExpired);
        assertEq(expiredCount, 0);
    }

    function testCheckUserExpiredRequestsWithExpiredRequest() public {

        vm.startPrank(user);

        brokerDollar.approve(address(assetPool), MINT_AMOUNT);

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
