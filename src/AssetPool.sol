// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { IAssetToken } from "./interfaces/IAssetToken.sol";
import { IChainlinkCaller } from "./interfaces/IChainlinkCaller.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetToken } from "../src/AssetToken.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/** 
 * @title AssetPool
 * @author Rauloiui
 * @notice This contract is used as a bridge between the user and the RWA tokens
   of the protocol. The user can mint or redeem an asset by sending usdt,
   the owner sets the valids RWA tokens at the setTokenRegistry function.
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

    /////////////////////
    // Events
    /////////////////////

    event AssetMinted(
        address indexed user,
        string ticket,
        uint256 amountOfToken,
        bytes32 requestId,
        uint256 deadline
    );

    event AssetRedeemed(
        address indexed user,
        string ticket,
        uint256 amountOfToken,
        bytes32 requestId,
        uint256 deadline
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

    /////////////////////
    // Constants
    /////////////////////

    uint256 public constant MAX_USD_AMOUNT = 10_000 * 1e6; // 10k USDT
    uint256 public constant MIN_USD_AMOUNT = 10 * 1e6;      // 10 USDT
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant REQUEST_COOLDOWN = 300;         // 5 minutes

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
    
    uint256 public assetCounter;

    // Rate limiting
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

    /////////////////////
    // Constructor
    /////////////////////

    constructor(
        IERC20 _usdt,
        address _chainlinkCaller
    ) ConfirmedOwner(msg.sender) {
        require(address(_usdt) != address(0) && _chainlinkCaller != address(0) , "Zero address");
        usdt = _usdt;
        chainlinkCaller = _chainlinkCaller;
    }

    /////////////////////
    // External Functions
    /////////////////////

    /**
     * @notice Mints an asset interacting with the RWA token
     * @param usdAmount The amount of usdt deposited by the user for buy the asset
     * @param ticket The ticket of the asset to mint
     */
    function mintAsset(uint256 usdAmount, string calldata ticket) 
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

        // Transfer net amount to asset token contract
        usdt.safeTransferFrom(msg.sender, asset.assetAddress, usdAmount);

        string memory accountId = userToAccountId[msg.sender];
        
        requestId = IAssetToken(asset.assetAddress)._mintAsset(
            usdAmount,
            msg.sender,
            accountId
        );

        userRequests[msg.sender].push(requestId);

        // Get deadline from the asset token
        (, , uint256 timeRemaining) = IAssetToken(asset.assetAddress).getRequestWithStatus(requestId);
        uint256 deadline = block.timestamp + timeRemaining;

        emit AssetMinted(msg.sender, ticket, usdAmount, requestId, deadline);
    }

    /**
     * @notice Redeems an asset interacting with the RWA token
     * @param assetAmount The amount of assets to redeem
     * @param ticket The ticket of the asset to redeem
     */
    function redeemAsset(uint256 assetAmount, string calldata ticket) 
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

        string memory accountId = userToAccountId[msg.sender];
        
        IERC20(asset.assetAddress).safeTransferFrom(msg.sender, asset.assetAddress, assetAmount);

        requestId = IAssetToken(asset.assetAddress)._redeemAsset(
            assetAmount,
            msg.sender,
            accountId
        );

        userRequests[msg.sender].push(requestId);

        // Get deadline from the asset token
        (, , uint256 timeRemaining) = IAssetToken(asset.assetAddress).getRequestWithStatus(requestId);
        uint256 deadline = block.timestamp + timeRemaining;

        emit AssetRedeemed(msg.sender, ticket, assetAmount, requestId, deadline);
    }

    /**
     * @notice Register a user with their account ID
     * @param accountId The user's account ID for external API
     */
    function registerUser(string calldata accountId) external {
        if (bytes(accountId).length == 0) revert InvalidAccountId();
        if (bytes(userToAccountId[msg.sender]).length != 0) revert AlreadyRegistered();

        userToAccountId[msg.sender] = accountId;
        emit UserRegistered(msg.sender, accountId);
    }

    /**
     * @notice Clean up expired requests for a user
     * @param user The user address
     * @param tickets Array of asset tickets to check
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
     * @notice Create and register a new RWA token
     * @param name Name of the token
     * @param ticket Ticker symbol of the token
     * @param imageCid CID of the image uploaded to IPFS
     */
    function createTokenRegistry(
        string calldata name,
        string calldata ticket,
        string calldata imageCid
    ) external onlyOwner returns(address) {
        if (assetInfo[ticket].assetAddress != address(0)) revert AssetAlreadyExists();

        AssetToken token = new AssetToken(
            address(this), 
            name, 
            ticket, 
            usdt, 
            chainlinkCaller
        );

        assetInfo[ticket] = Asset({
            id: uint96(assetCounter),
            assetAddress: address(token),
            uri: imageCid,
            name: name
        });

        // Give approval for the token to spend USDT for refunds
        usdt.approve(address(token), type(uint256).max);

        IChainlinkCaller(chainlinkCaller).authorizeToken(ticket, address(token));

        assetTickets.push(ticket);

        assetCounter++;
        emit TokenRegistered(address(token), name, ticket);

        return address(token);
    }

    /**
     * @notice Remove a token registry (disable token)
     * @param ticket The ticket of the token to remove
     * @dev This doesn't destroy the token contract, just removes it from the registry
     * @dev Users with existing tokens can still redeem them directly from the token contract
     */
    function removeTokenRegistry(string calldata ticket) external onlyOwner {
        Asset memory asset = assetInfo[ticket];
        if (asset.assetAddress == address(0)) revert InvalidAsset();

        // Remove from mapping
        delete assetInfo[ticket];

        // Remove from array - find and replace with last element, then pop
        for (uint256 i = 0; i < assetTickets.length; i++) {
            if (keccak256(bytes(assetTickets[i])) == keccak256(bytes(ticket))) {
                // Move last element to current position
                assetTickets[i] = assetTickets[assetTickets.length - 1];
                // Remove last element
                assetTickets.pop();
                break;
            }
        }

        // Remove authorization from Chainlink caller
        IChainlinkCaller(chainlinkCaller).deAuthorizeToken(ticket, asset.assetAddress);

        emit TokenRemoved(asset.assetAddress, ticket);
    }

    /**
     * @notice Set request timeout for a specific asset
     * @param newTimeout New timeout in seconds
     * @param asset Address of the asset token
     */
    function setRequestTimeout(uint256 newTimeout, address asset) external onlyOwner {
        IAssetToken(asset)._setRequestTimeout(newTimeout);
    }

    /**
     * @notice Emergency function to manually expire stuck requests
     * @param requestIds Array of request IDs to expire
     * @dev Only use this if Chainlink fails to respond and requests are stuck
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

    /**
     * @notice Get expired request IDs for a specific asset from user's requests
     */
    function _getExpiredRequestIds(
        bytes32[] memory userRequestIds, 
        address assetAddress
    ) internal view returns (bytes32[] memory expiredIds) {
        uint256 expiredCount = 0;

        // Count expired requests first
        for (uint256 i = 0; i < userRequestIds.length; i++) {
            if (IAssetToken(assetAddress).isRequestExpired(userRequestIds[i])) {
                expiredCount++;
            }
        }

        // Create array and populate
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

    /**
     * @notice Get user's pending requests for a specific asset
     * @param user The user address
     * @param ticket The asset ticket
     * @return requests Array of request details
     */
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

        // Count pending requests first
        for (uint256 i = 0; i < userRequestIds.length; i++) {
            (IAssetToken.AssetRequest memory request, , ) = IAssetToken(asset.assetAddress)
                .getRequestWithStatus(userRequestIds[i]);
            
            if (request.requester == user && 
                request.status == IAssetToken.RequestStatus.pending) {
                pendingCount++;
            }
        }

        // Create array and populate
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

    /**
     * @notice Check if user has any expired requests
     * @param user The user address
     * @param tickets Array of asset tickets to check
     * @return hasExpired Whether user has expired requests
     * @return expiredCount Total number of expired requests
     */
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

    /**
     * @notice Get asset information by ticket
     * @param ticket The asset ticket
     * @return asset The asset information
     */
    function getAssetInfo(string calldata ticket) external view returns (Asset memory asset) {
        return assetInfo[ticket];
    }

    /**
     * @notice Check if user is registered
     * @param user The user address
     * @return registered Whether the user is registered
     */
    function isUserRegistered(address user) external view returns (bool registered) {
        return bytes(userToAccountId[user]).length > 0;
    }

    /**
     * @notice Get user requests
     * @param user The user address
     * @return Array of user's request IDs
     */
    function getUserRequests(address user) external view returns (bytes32[] memory) {
        return userRequests[user];
    }

    /**
     * @notice Get all registered token tickets
     * @return Array of all token tickets
     */
    function getAllTokenTickets() external view returns (string[] memory) {
        return assetTickets;
    }
}