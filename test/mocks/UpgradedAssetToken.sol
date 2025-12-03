// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IChainlinkCaller } from "../../src/interfaces/IChainlinkCaller.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AssetToken (Upgradeable)
 * @notice Upgraded Tokenized real-world assets compatible with Beacon Proxy pattern
 * @dev The MIN_TIMEOUT of this contract has been changed for testing purposes
 */
contract UpgradedAssetToken is 
    Initializable,
    ERC20Upgradeable, 
    OwnableUpgradeable,
    ReentrancyGuard
{
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

    /////////////////////
    // Storage
    /////////////////////

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

    struct AssetRequest {
        uint256 amount;
        address requester;
        MintOrRedeem mintOrRedeem;
        RequestStatus status;
        uint256 deadline;
        uint256 createdAt;
        uint256 amountExpected;
    }

    mapping(address user => AssetRequest[] requests) private userToRequests;

    uint256 public requestTimeout;

    uint256 public constant MIN_TIMEOUT = 400;
    uint256 public constant MAX_TIMEOUT = 86400;
    uint256 public constant MAX_CLEANUP_BATCH_SIZE = 50;

    uint256 public constant MAX_SLIPPAGE_BASIS_POINTS = 102;
    uint256 public constant MIN_SLIPPAGE_BASIS_POINTS = 98;

    address public assetPool;
    address public chainlinkCaller;
    IERC20 public usdt;

    mapping(bytes32 => AssetRequest) public requestIdToRequest;

    /////////////////////
    // Modifiers
    /////////////////////

    modifier validTimeout(uint256 timeout) {
        if (timeout < MIN_TIMEOUT || timeout > MAX_TIMEOUT)
            revert InvalidTimeout();
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

    constructor() {
        _disableInitializers();
    }

    /////////////////////
    // Initialization
    /////////////////////

    /**
     * @notice Initialize the AssetToken contract
     * @dev This function is called automatically when the BeaconProxy is created
     * @param _assetPool Address of the AssetPool contract
     * @param _name Name of the token (e.g., "Tesla Stock Token")
     * @param _symbol Symbol of the token (e.g., "dTSLA")
     * @param _usdt USDT token contract address
     * @param _chainlinkCaller ChainlinkCaller contract address
     */
    function initialize(
        address _assetPool,
        string memory _name,
        string memory _symbol,
        address _usdt,
        address _chainlinkCaller
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init(_assetPool);

        assetPool = _assetPool;
        usdt = IERC20(_usdt);
        chainlinkCaller = _chainlinkCaller;
        requestTimeout = 3600; // 1 hour default
    }

    /////////////////////
    // External Functions
    /////////////////////

    function _mintAsset(
        uint256 usdAmount,
        address requester,
        string memory accountId,
        uint256 assetAmountExpected
    ) external onlyAssetPool returns (bytes32 requestId) {
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
            createdAt: block.timestamp,
            amountExpected: assetAmountExpected
        });

        userToRequests[requester].push(requestIdToRequest[requestId]);

        return requestId;
    }

    function _redeemAsset(
        uint256 assetAmount,
        address requester,
        string memory accountId,
        uint256 usdAmountExpected
    ) external onlyAssetPool returns (bytes32 requestId) {
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
            createdAt: block.timestamp,
            amountExpected: usdAmountExpected
        });

        userToRequests[requester].push(requestIdToRequest[requestId]);

        return requestId;
    }

    function onFulfill(
        bytes32 requestId,
        uint256 tokenAmount,
        bool success
    ) external nonReentrant onlyChainlinkCaller {
        AssetRequest storage request = requestIdToRequest[requestId];

        if (block.timestamp >= request.deadline) revert RequestExpiredError();
        if (request.status != RequestStatus.pending)
            revert RequestAlreadyProcessed();

        if (!success || tokenAmount == 0) {
            request.status = RequestStatus.error;
            _issueRefund(request, "API call failed or returned zero amount");
        } else {
            if (request.mintOrRedeem == MintOrRedeem.mint) {
                uint256 upperBound = (request.amountExpected *
                    MAX_SLIPPAGE_BASIS_POINTS) / 100;
                uint256 lowerBound = (request.amountExpected *
                    MIN_SLIPPAGE_BASIS_POINTS) / 100;

                if (tokenAmount > upperBound || tokenAmount < lowerBound) {
                    request.status = RequestStatus.error;
                    _issueRefund(request, "Slippage too high on mint");
                    return;
                }

                _mint(request.requester, tokenAmount);
                request.status = RequestStatus.fulfilled;
            } else {
                uint256 upperBound = (request.amountExpected *
                    MAX_SLIPPAGE_BASIS_POINTS) / 100;
                uint256 lowerBound = (request.amountExpected *
                    MIN_SLIPPAGE_BASIS_POINTS) / 100;

                if (tokenAmount > upperBound || tokenAmount < lowerBound) {
                    request.status = RequestStatus.error;
                    _issueRefund(request, "Slippage too high on redeem");
                    return;
                }

                usdt.safeTransfer(request.requester, tokenAmount);
                request.status = RequestStatus.fulfilled;
            }

            emit RequestSuccess(
                requestId,
                request.requester,
                tokenAmount,
                request.mintOrRedeem
            );
        }
    }

    function cleanupExpiredRequests(
        bytes32[] calldata requestIds
    ) external nonReentrant {
        if (requestIds.length > MAX_CLEANUP_BATCH_SIZE)
            revert InvalidBatchSize();

        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            AssetRequest storage request = requestIdToRequest[requestId];

            if (
                request.status == RequestStatus.pending &&
                block.timestamp > request.deadline
            ) {
                request.status = RequestStatus.expired;

                emit RequestExpired(
                    requestId,
                    request.requester,
                    request.amount,
                    request.mintOrRedeem
                );

                _issueRefund(request, "Request expired");
            }
        }
    }

    function isRequestExpired(
        bytes32 requestId
    ) external view returns (bool expired) {
        AssetRequest memory request = requestIdToRequest[requestId];
        return (request.status == RequestStatus.pending &&
            block.timestamp > request.deadline);
    }

    function getTimeRemaining(
        bytes32 requestId
    ) external view returns (uint256 timeRemaining) {
        AssetRequest memory request = requestIdToRequest[requestId];

        if (
            request.status != RequestStatus.pending ||
            block.timestamp >= request.deadline
        ) {
            return 0;
        }

        return request.deadline - block.timestamp;
    }

    /////////////////////
    // Owner Functions
    /////////////////////

    function _setRequestTimeout(
        uint256 newTimeout
    ) external onlyOwner validTimeout(newTimeout) {
        uint256 oldTimeout = requestTimeout;
        requestTimeout = newTimeout;
        emit RequestTimeoutUpdated(oldTimeout, newTimeout);
    }

    function _expireRequests(bytes32[] calldata requestIds) external onlyOwner {
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            AssetRequest storage request = requestIdToRequest[requestId];

            if (request.status == RequestStatus.pending) {
                request.status = RequestStatus.expired;

                emit RequestExpired(
                    requestId,
                    request.requester,
                    request.amount,
                    request.mintOrRedeem
                );

                _issueRefund(request, "Emergency expiration by owner");
            }
        }
    }

    /////////////////////
    // Internal Functions
    /////////////////////

    function _issueRefund(
        AssetRequest memory request,
        string memory reason
    ) internal {
        if (request.mintOrRedeem == MintOrRedeem.mint) {
            usdt.safeTransfer(request.requester, request.amount);
        } else {
            _transfer(address(this), request.requester, request.amount);
        }

        emit RefundIssued(
            request.requester,
            request.amount,
            request.mintOrRedeem,
            reason
        );
    }

    /////////////////////
    // View Functions
    /////////////////////

    function getUserRequests(
        address user
    ) external view returns (AssetRequest[] memory) {
        return userToRequests[user];
    }

    function getRequest(
        bytes32 requestId
    ) external view returns (AssetRequest memory request) {
        return requestIdToRequest[requestId];
    }

    function getRequestWithStatus(
        bytes32 requestId
    )
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
        return (
            requestTimeout,
            MIN_TIMEOUT,
            MAX_TIMEOUT,
            MAX_CLEANUP_BATCH_SIZE
        );
    }

    function getBalances()
        external
        view
        returns (uint256 usdtBalance, uint256 assetBalance)
    {
        usdtBalance = usdt.balanceOf(address(this));
        assetBalance = balanceOf(address(this));
    }
    
    /**
     * @notice Returns the version of the contract
     * @dev Useful to verify that the upgrade was performed correctly
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}