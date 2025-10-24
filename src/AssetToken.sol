// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IChainlinkCaller } from "./interfaces/IChainlinkCaller.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AssetToken
 * @notice This contract represents tokenized real-world assets (RWA) like stocks
 * @dev Integrates with Alpaca API through Chainlink Functions for price feeds and order execution
 */
contract AssetToken is ConfirmedOwner, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /////////////////////
    // Custom Errors
    /////////////////////

    error NotAllowedToMint();
    error NotAllowedToRedeem(); 
    error NotAllowedCaller();
    error RequestNotPending();
    error RequestExpiredError();
    error InvalidTimeout();
    error InvalidBatchSize();
    error RequestAlreadyProcessed();

    /////////////////////
    // Events
    /////////////////////

    event RefundIssued(
        address indexed requester, 
        uint256 amount, 
        MintOrRedeem mintOrRedeem,
        string reason
    );
    
    event RequestSuccess(
        bytes32 indexed requestId, 
        address indexed requester,
        uint256 tokenAmount, 
        MintOrRedeem mintOrRedeem
    );
    
    event RequestExpired(
        bytes32 indexed requestId, 
        address indexed requester, 
        uint256 amount, 
        MintOrRedeem mintOrRedeem
    );
    
    event RequestTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
    
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed to);

    /////////////////////
    // Storage
    /////////////////////

    /**
     * @notice Differentiates when the user is buying or selling an asset
     */
    enum MintOrRedeem {
        mint,
        redeem
    }

    enum RequestStatus {
        pending,
        fulfilled,
        error,
        expired
    }

    /**
     * @notice Created when a user wants to mint or redeem an asset
     * @param amount The amount of USD to mint or redeem
     * @param requester The address that made the request
     * @param mintOrRedeem Differentiates if the user is minting or redeeming an asset
     * @param status Current status of the request
     * @param deadline Timestamp when the request expires
     * @param createdAt Timestamp when the request was created
     */
    struct AssetRequest {
        uint256 amount;
        address requester;
        MintOrRedeem mintOrRedeem;
        RequestStatus status;
        uint256 deadline;
        uint256 createdAt;
    }

    // Default timeout: 1 hour (3600 seconds)
    uint256 public requestTimeout = 3600;
    
    // Minimum and maximum allowed timeouts
    uint256 public constant MIN_TIMEOUT = 300;   // 5 minutes
    uint256 public constant MAX_TIMEOUT = 86400; // 24 hours
    uint256 public constant MAX_CLEANUP_BATCH_SIZE = 50;

    // Core contracts
    address public immutable assetPool;
    address public immutable chainlinkCaller;
    IERC20 public immutable usdt;

    // Request tracking
    mapping(bytes32 => AssetRequest) public requestIdToRequest;

    /////////////////////
    // Modifiers
    /////////////////////

    modifier validTimeout(uint256 timeout) {
        if (timeout < MIN_TIMEOUT || timeout > MAX_TIMEOUT) revert InvalidTimeout();
        _;
    }

    modifier onlyAssetPool() {
        if (msg.sender != assetPool) revert NotAllowedToMint();
        _;
    }

    modifier onlyChainlinkCaller() {
        if (msg.sender != chainlinkCaller) revert NotAllowedCaller();
        _;
    }

    /////////////////////
    // Constructor
    /////////////////////

    /**
     * @notice Initializes the asset token contract
     * @param _assetPool Address of the AssetPool contract
     * @param _name Name of the token (e.g., "Tesla Stock Token")
     * @param _symbol Symbol of the token (e.g., "dTSLA")
     * @param _usdt USDT token contract address
     * @param _chainlinkCaller ChainlinkCaller contract address
     */
    constructor(
        address _assetPool,
        string memory _name,
        string memory _symbol,
        IERC20 _usdt,
        address _chainlinkCaller
    )
        ConfirmedOwner(_assetPool)
        ERC20(_name, _symbol)
    {
        assetPool = _assetPool;
        usdt = _usdt;
        chainlinkCaller = _chainlinkCaller;
    }

    /////////////////////
    // External Functions
    /////////////////////

    /**
     * @notice Initiates a mint request for asset tokens
     * @param usdAmount Amount of USD to convert to asset tokens
     * @param requester Address of the user requesting the mint
     * @param accountId External account ID for API integration
     * @return requestId Unique identifier for the request
     */
    function _mintAsset(
        uint256 usdAmount, 
        address requester, 
        string memory accountId
    )
        external
        onlyAssetPool
        returns (bytes32 requestId)
    {       
        // Send the request to Chainlink
        requestId = IChainlinkCaller(chainlinkCaller).requestMint(
            usdAmount,
            accountId,
            symbol()
        );

        uint256 deadline = block.timestamp + requestTimeout;

        requestIdToRequest[requestId] = AssetRequest({
            amount: usdAmount,
            requester: requester,
            mintOrRedeem: MintOrRedeem.mint,
            status: RequestStatus.pending,
            deadline: deadline,
            createdAt: block.timestamp
        });

        return requestId;
    }

    /**
     * @notice Initiates a redeem request for asset tokens
     * @param assetAmount Amount of asset tokens to redeem
     * @param requester Address of the user requesting the redemption
     * @param accountId External account ID for API integration
     * @return requestId Unique identifier for the request
     */
    function _redeemAsset(
        uint256 assetAmount, 
        address requester, 
        string memory accountId
    )
        external
        onlyAssetPool
        returns (bytes32 requestId)
    {
        requestId = IChainlinkCaller(chainlinkCaller).requestRedeem(
            assetAmount,
            accountId,
            symbol()
        );

        uint256 deadline = block.timestamp + requestTimeout;

        requestIdToRequest[requestId] = AssetRequest({
            amount: assetAmount,
            requester: requester,
            mintOrRedeem: MintOrRedeem.redeem,
            status: RequestStatus.pending,
            deadline: deadline,
            createdAt: block.timestamp
        });

        return requestId;
    }

    /**
     * @notice Callback function called by ChainlinkCaller when request is fulfilled
     * @param requestId The request ID that was fulfilled
     * @param tokenAmount The amount of tokens to mint/redeem (0 if error)
     * @param success Whether the external API call was successful
     */
    function onFulfill(
        bytes32 requestId, 
        uint256 tokenAmount, 
        bool success
    ) 
        external 
        nonReentrant 
        onlyChainlinkCaller 
    {
        AssetRequest storage request = requestIdToRequest[requestId];
        
        if (block.timestamp >= request.deadline) revert RequestExpiredError();
        if (request.status != RequestStatus.pending) revert RequestAlreadyProcessed();

        if (!success || tokenAmount == 0) {
            // Mark request as error and issue refund
            request.status = RequestStatus.error;
            _issueRefund(request, "API call failed or returned zero amount");
        } else {
            // Mark as fulfilled and process the transaction
            request.status = RequestStatus.fulfilled;

            if (request.mintOrRedeem == MintOrRedeem.mint) {
                _mint(request.requester, tokenAmount);
            } else {
                // For redemptions, transfer USDT from this contract to user
                usdt.safeTransfer(request.requester, tokenAmount); 
            }

            emit RequestSuccess(requestId, request.requester, tokenAmount, request.mintOrRedeem);
        }
    }

    /**
     * @notice Allows cleanup of expired requests and automatic refunds
     * @param requestIds Array of request IDs to clean up
     */
    function cleanupExpiredRequests(bytes32[] calldata requestIds) 
        external 
        nonReentrant 
    {
        if (requestIds.length > MAX_CLEANUP_BATCH_SIZE) revert InvalidBatchSize();

        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            AssetRequest storage request = requestIdToRequest[requestId];
            
            // Check if request is expired and still pending
            if (
                request.status == RequestStatus.pending && 
                block.timestamp > request.deadline
            ) {
                // Mark as expired
                request.status = RequestStatus.expired;
                
                emit RequestExpired(requestId, request.requester, request.amount, request.mintOrRedeem);
                
                // Issue refund
                _issueRefund(request, "Request expired");
            }
        }
    }

    /**
     * @notice Check if a request has expired
     * @param requestId The request ID to check
     * @return expired Whether the request has expired
     */
    function isRequestExpired(bytes32 requestId) external view returns (bool expired) {
        AssetRequest memory request = requestIdToRequest[requestId];
        return (
            request.status == RequestStatus.pending && 
            block.timestamp > request.deadline
        );
    }

    /**
     * @notice Get time remaining for a request
     * @param requestId The request ID to check
     * @return timeRemaining Seconds remaining (0 if expired)
     */
    function getTimeRemaining(bytes32 requestId) external view returns (uint256 timeRemaining) {
        AssetRequest memory request = requestIdToRequest[requestId];
        
        if (request.status != RequestStatus.pending || block.timestamp >= request.deadline) {
            return 0;
        }
        
        return request.deadline - block.timestamp;
    }

    /////////////////////
    // Owner Functions
    /////////////////////

    function _setRequestTimeout(uint256 newTimeout) 
        external 
        onlyOwner 
        validTimeout(newTimeout) 
    {
        uint256 oldTimeout = requestTimeout;
        requestTimeout = newTimeout;
        emit RequestTimeoutUpdated(oldTimeout, newTimeout);
    }

    function _expireRequests(bytes32[] calldata requestIds) 
        external 
        onlyOwner 
    {
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            AssetRequest storage request = requestIdToRequest[requestId];
            
            if (request.status == RequestStatus.pending) {
                request.status = RequestStatus.expired;
                
                emit RequestExpired(requestId, request.requester, request.amount, request.mintOrRedeem);
                
                // Issue refund
                _issueRefund(request, "Emergency expiration by owner");
            }
        }
    }

    /////////////////////
    // Internal Functions
    /////////////////////

    /**
     * @notice Internal function to issue refunds
     * @param request The request to refund
     * @param reason Reason for the refund
     */
    function _issueRefund(AssetRequest memory request, string memory reason) internal {
        if (request.mintOrRedeem == MintOrRedeem.mint) {
            // For mint requests, return USDT that was sent to this contract
            usdt.safeTransfer(request.requester, request.amount);
        } else {
            // For redeem requests, return the asset tokens from this contract
            _transfer(address(this), request.requester, request.amount);
        }

        emit RefundIssued(request.requester, request.amount, request.mintOrRedeem, reason);
    }

    /////////////////////
    // View Functions
    /////////////////////

    /**
     * @notice Get request details
     * @param requestId The request ID to query
     * @return request The request details
     */
    function getRequest(bytes32 requestId) external view returns (AssetRequest memory request) {
        return requestIdToRequest[requestId];
    }

    /**
     * @notice Get request details with expiration status
     * @param requestId The request ID to check
     * @return request The request details
     * @return isExpired Whether the request has expired
     * @return timeRemaining Seconds remaining (0 if expired)
     */
    function getRequestWithStatus(bytes32 requestId) 
        external 
        view 
        returns (
            AssetRequest memory request, 
            bool isExpired, 
            uint256 timeRemaining
        ) 
    {
        request = requestIdToRequest[requestId];
        
        if (request.status == RequestStatus.pending) {
            isExpired = block.timestamp > request.deadline;
            timeRemaining = isExpired ? 0 : request.deadline - block.timestamp;
        } else {
            isExpired = (request.status == RequestStatus.expired);
            timeRemaining = 0;
        }
    }

    /**
     * @notice Get contract configuration
     * @return timeout Current request timeout
     * @return minTimeout Minimum allowed timeout
     * @return maxTimeout Maximum allowed timeout
     * @return maxBatchSize Maximum cleanup batch size
     */
    function getConfig() 
        external 
        view 
        returns (
            uint256 timeout,
            uint256 minTimeout,
            uint256 maxTimeout,
            uint256 maxBatchSize
        )
    {
        return (requestTimeout, MIN_TIMEOUT, MAX_TIMEOUT, MAX_CLEANUP_BATCH_SIZE);
    }

    /**
     * @notice Check contract balances
     * @return usdtBalance USDT balance of this contract
     * @return assetBalance Asset token balance of this contract
     */
    function getBalances() external view returns (uint256 usdtBalance, uint256 assetBalance) {
        usdtBalance = usdt.balanceOf(address(this));
        assetBalance = balanceOf(address(this));
    }
}