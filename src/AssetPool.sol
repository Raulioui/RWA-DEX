// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IAssetToken } from "./interfaces/IAssetToken.sol";
import { AssetToken } from "../src/AssetToken.sol";
import { IChainlinkCaller } from "./interfaces/IChainlinkCaller.sol";

import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/** 
 * @title AssetPool
 * @author Rauloiui
 * @notice Factory contract that creates AssetToken instances using Beacon Proxy pattern
 * @dev All AssetToken proxies point to a single Beacon, enabling mass upgrades
 */
contract AssetPool is ConfirmedOwner, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /////////////////////
    // Custom Errors
    /////////////////////

    error UserNotRegistered();
    error InvalidAsset();
    error InsufficientAmount();
    error AlreadyRegistered();
    error InvalidAccountId();
    error AssetAlreadyExists();
    error ArrayLengthMismatch();
    error RateLimited();
    error AmountOutOfBounds();
    error BeaconNotInitialized();
    error InvalidImplementation();

    /////////////////////
    // Events
    /////////////////////

    event AssetMinted(
        address indexed user,
        string ticket,
        uint256 amountOfToken,
        bytes32 requestId
    );

    event AssetRedeemed(
        address indexed user,
        string ticket,
        uint256 amountOfToken,
        bytes32 requestId
    );

    event TokenRegistered(
        address token,
        string name,
        string ticket
    );

    event UserRegistered(
        address indexed user,
        string accountId
    );

    event ExpiredRequestsCleaned(uint256 count);

    event TokenRemoved(
        address token,
        string ticket
    );

    event AllTokensUpgraded(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    event BeaconCreated(
        address indexed beacon,
        address indexed implementation
    );

    /////////////////////
    // Constants
    /////////////////////

    uint256 public constant MAX_USD_AMOUNT = 10_000 * 1e6;
    uint256 public constant MIN_USD_AMOUNT = 10 * 1e6;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant REQUEST_COOLDOWN = 300;

    /////////////////////
    // Storage
    /////////////////////

    struct Asset {
        address assetAddress;  
        uint96 id;              
        string uri;
        string name;
    }

    IERC20 public immutable usdt;
    address public immutable chainlinkCaller;
    
    UpgradeableBeacon public assetTokenBeacon;
    
    uint96 public assetCounter;

    mapping(address => uint256) public userLastRequest;
    mapping(address => string) public userToAccountId;
    mapping(string assetTicket => Asset) public assetInfo;
    mapping(address => bytes32[]) public userRequests;

    string[] public assetTickets;

    /////////////////////
    // Modifiers
    /////////////////////

    modifier validUser() {
        if (bytes(userToAccountId[msg.sender]).length == 0) {
            revert UserNotRegistered();
        }
        _;
    }

    modifier rateLimited() {
        if (block.timestamp < userLastRequest[msg.sender] + REQUEST_COOLDOWN) {
            revert RateLimited();
        }
        userLastRequest[msg.sender] = block.timestamp;
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount < MIN_USD_AMOUNT || amount > MAX_USD_AMOUNT) {
            revert AmountOutOfBounds();
        }
        _;
    }

    modifier beaconInitialized() {
        if (address(assetTokenBeacon) == address(0)) {
            revert BeaconNotInitialized();
        }
        _;
    }

    /////////////////////
    // Constructor
    /////////////////////

    constructor(
        IERC20 _usdt,
        address _chainlinkCaller
    ) ConfirmedOwner(msg.sender) {
        require(address(_usdt) != address(0) && _chainlinkCaller != address(0), "Zero address");
        usdt = _usdt;
        chainlinkCaller = _chainlinkCaller;
    }

    /////////////////////
    // Initialization
    /////////////////////

    /**
     * @notice Initializes the UpgradeableBeacon with the AssetToken implementation
     * @param implementation Address of the AssetToken implementation contract
     */
    function initializeBeacon(address implementation) external onlyOwner {
        require(address(assetTokenBeacon) == address(0), "Beacon already initialized");
        require(implementation != address(0), "Invalid implementation");
        
        assetTokenBeacon = new UpgradeableBeacon(implementation, address(this));
        
        emit BeaconCreated(address(assetTokenBeacon), implementation);
    }

    /////////////////////
    // External Functions
    /////////////////////

    /**
     * @notice Mints an asset interacting with the RWA token
     */
    function mintAsset(uint256 usdAmount, string calldata ticket, uint256 assetAmountExpected) 
        external 
        nonReentrant 
        whenNotPaused 
        validUser 
        rateLimited 
        validAmount(usdAmount)
        returns (bytes32 requestId) 
    {
        Asset memory asset = assetInfo[ticket];
        if (asset.assetAddress == address(0)) revert InvalidAsset();

        usdt.safeTransferFrom(msg.sender, asset.assetAddress, usdAmount);

        string memory accountId = userToAccountId[msg.sender];
        
        requestId = IAssetToken(asset.assetAddress)._mintAsset(
            usdAmount,
            msg.sender,
            accountId,
            assetAmountExpected
        );

        userRequests[msg.sender].push(requestId);

        emit AssetMinted(msg.sender, ticket, usdAmount, requestId);
    }

    /**
     * @notice Redeems an asset interacting with the RWA token
     */
    function redeemAsset(uint256 assetAmount, string calldata ticket, uint256 usdAmountExpected) 
        external 
        nonReentrant 
        whenNotPaused 
        validUser 
        rateLimited
        returns (bytes32 requestId) 
    {
        if (assetAmount == 0) revert InsufficientAmount();

        Asset memory asset = assetInfo[ticket];
        if (asset.assetAddress == address(0)) revert InvalidAsset();

        IERC20(asset.assetAddress).safeTransferFrom(msg.sender, asset.assetAddress, assetAmount);

        string memory accountId = userToAccountId[msg.sender];
        
        requestId = IAssetToken(asset.assetAddress)._redeemAsset(
            assetAmount,
            msg.sender,
            accountId,
            usdAmountExpected
        );

        userRequests[msg.sender].push(requestId);
        emit AssetRedeemed(msg.sender, ticket, assetAmount, requestId);
    }

    /**
     * @notice Register a user with their account ID
     */
    function registerUser(string calldata accountId) external {
        if (bytes(accountId).length == 0) revert InvalidAccountId();
        if (bytes(userToAccountId[msg.sender]).length != 0) revert AlreadyRegistered();

        userToAccountId[msg.sender] = accountId;
        emit UserRegistered(msg.sender, accountId);
    }

    /**
     * @notice Clean up expired requests for a user
     */
    function cleanupUserExpiredRequests(
        address user, 
        string[] calldata tickets
    ) external {
        bytes32[] memory userRequestIds = userRequests[user];
        uint256 cleanedCount = 0;

        for (uint256 i = 0; i < tickets.length; i++) {
            Asset memory asset = assetInfo[tickets[i]];
            if (asset.assetAddress != address(0)) {
                bytes32[] memory expiredIds = _getExpiredRequestIds(
                    userRequestIds, 
                    asset.assetAddress
                );
                
                if (expiredIds.length > 0) {
                    IAssetToken(asset.assetAddress).cleanupExpiredRequests(expiredIds);
                    cleanedCount += expiredIds.length;
                }
            }
        }

        if (cleanedCount > 0) {
            emit ExpiredRequestsCleaned(cleanedCount);
        }
    }

    /////////////////////
    // Owner Functions
    /////////////////////

    /**
     * @notice Creates a new AssetToken registry using Beacon Proxy pattern
     * @param name Name of the token
     * @param ticket SSymbol of the token
     * @param imageCid CID of the image on IPFS
     */
    function createTokenRegistry(
        string calldata name,
        string calldata ticket,
        string calldata imageCid
    ) external onlyOwner beaconInitialized returns(address) {
        if (assetInfo[ticket].assetAddress != address(0)) revert AssetAlreadyExists();
        
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,string,string,address,address)",
            address(this),  
            name,           
            ticket,         
            address(usdt),  
            chainlinkCaller 
        );

        BeaconProxy proxy = new BeaconProxy(
            address(assetTokenBeacon),
            initData
        );

        address tokenAddress = address(proxy);

        usdt.approve(tokenAddress, type(uint256).max);
        IChainlinkCaller(chainlinkCaller).authorizeToken(ticket, tokenAddress);

        assetInfo[ticket] = Asset({
            id: assetCounter,
            assetAddress: tokenAddress,
            uri: imageCid,
            name: name
        });

        assetTickets.push(ticket);
        assetCounter++;

        emit TokenRegistered(tokenAddress, name, ticket);

        return tokenAddress;
    }

    /**
     * @notice Updates the implementation for all AssetToken proxies via the Beacon
     * @param newImplementation Address of the new AssetToken implementation contract
     */
    function upgradeAllAssetTokens(address newImplementation) external onlyOwner beaconInitialized {
        if (newImplementation == address(0)) revert InvalidImplementation();
        
        address oldImplementation = assetTokenBeacon.implementation();
        
        assetTokenBeacon.upgradeTo(newImplementation);
        
        emit AllTokensUpgraded(oldImplementation, newImplementation);
    }

    /**
     * @notice Remove a token registry (disable token)
     */
    function removeTokenRegistry(string calldata ticket) external onlyOwner {
        Asset memory asset = assetInfo[ticket];
        if (asset.assetAddress == address(0)) revert InvalidAsset();

        delete assetInfo[ticket];

        for (uint256 i = 0; i < assetTickets.length; i++) {
            if (keccak256(bytes(assetTickets[i])) == keccak256(bytes(ticket))) {
                assetTickets[i] = assetTickets[assetTickets.length - 1];
                assetTickets.pop();
                break;
            }
        }

        IChainlinkCaller(chainlinkCaller).deAuthorizeToken(ticket, asset.assetAddress);

        emit TokenRemoved(asset.assetAddress, ticket);
    }

    /**
     * @notice Set request timeout for a specific asset
     */
    function setRequestTimeout(uint256 newTimeout, address asset) external onlyOwner {
        IAssetToken(asset)._setRequestTimeout(newTimeout);
    }

    /**
     * @notice Emergency function to manually expire stuck requests
     */
    function expireRequests(bytes32[] calldata requestIds, address asset) external onlyOwner {
        IAssetToken(asset)._expireRequests(requestIds);
    }

    /**
     * @notice Emergency pause function
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /////////////////////
    // Internal Functions
    /////////////////////

    function _getExpiredRequestIds(
        bytes32[] memory userRequestIds, 
        address assetAddress
    ) internal view returns (bytes32[] memory expiredIds) {
        uint256 expiredCount = 0;

        for (uint256 i = 0; i < userRequestIds.length; i++) {
            if (IAssetToken(assetAddress).isRequestExpired(userRequestIds[i])) {
                expiredCount++;
            }
        }

        expiredIds = new bytes32[](expiredCount);
        uint256 index = 0;

        for (uint256 i = 0; i < userRequestIds.length && index < expiredCount; i++) {
            if (IAssetToken(assetAddress).isRequestExpired(userRequestIds[i])) {
                expiredIds[index] = userRequestIds[i];
                index++;
            }
        }
    }

    /////////////////////
    // View Functions
    /////////////////////

    function getCurrentImplementation() external view returns (address) {
        if (address(assetTokenBeacon) == address(0)) return address(0);
        return assetTokenBeacon.implementation();
    }

    function getBeaconAddress() external view returns (address) {
        return address(assetTokenBeacon);
    }

    function getUserPendingRequests(address user, string calldata ticket) 
        external 
        view 
        returns (IAssetToken.AssetRequest[] memory requests) 
    {
        if (bytes(userToAccountId[user]).length == 0) {
            revert UserNotRegistered();
        }

        Asset memory asset = assetInfo[ticket];
        if (asset.assetAddress == address(0)) revert InvalidAsset();

        bytes32[] memory userRequestIds = userRequests[user];
        uint256 pendingCount = 0;

        for (uint256 i = 0; i < userRequestIds.length; i++) {
            (IAssetToken.AssetRequest memory request, , ) = IAssetToken(asset.assetAddress)
                .getRequestWithStatus(userRequestIds[i]);
            
            if (request.requester == user && 
                request.status == IAssetToken.RequestStatus.pending) {
                pendingCount++;
            }
        }

        requests = new IAssetToken.AssetRequest[](pendingCount);
        uint256 index = 0;

        for (uint256 i = 0; i < userRequestIds.length && index < pendingCount; i++) {
            (IAssetToken.AssetRequest memory request, , ) = IAssetToken(asset.assetAddress)
                .getRequestWithStatus(userRequestIds[i]);
            
            if (request.requester == user && 
                request.status == IAssetToken.RequestStatus.pending) {
                requests[index] = request;
                index++;
            }
        }
    }

    function checkUserExpiredRequests(
        address user, 
        string[] calldata tickets
    ) external view returns (bool hasExpired, uint256 expiredCount) {
        bytes32[] memory userRequestIds = userRequests[user];
        
        for (uint256 i = 0; i < tickets.length; i++) {
            Asset memory asset = assetInfo[tickets[i]];
            if (asset.assetAddress != address(0)) {
                for (uint256 j = 0; j < userRequestIds.length; j++) {
                    if (IAssetToken(asset.assetAddress).isRequestExpired(userRequestIds[j])) {
                        expiredCount++;
                        hasExpired = true;
                    }
                }
            }
        }
    }

    function getAssetInfo(string calldata ticket) external view returns (Asset memory asset) {
        return assetInfo[ticket];
    }

    function isUserRegistered(address user) external view returns (bool registered) {
        return bytes(userToAccountId[user]).length > 0;
    }

    function getUserRequests(address user) external view returns (bytes32[] memory) {
        return userRequests[user];
    }

    function getAllTokenTickets() external view returns (string[] memory) {
        return assetTickets;
    }
}