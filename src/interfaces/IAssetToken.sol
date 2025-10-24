// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IAssetToken
 * @notice Interface for AssetToken contract with deadline support
 */
interface IAssetToken {
    
    /////////////////////
    // Enums
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

    /////////////////////
    // Structs
    /////////////////////
    
    struct AssetRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
        RequestStatus status;
        uint256 deadline;
        uint256 createdAt;
    }

    /////////////////////
    // Events
    /////////////////////
    
    event RefundIssued(address indexed requester, uint256 amount, MintOrRedeem mintOrRedeem);
    event RequestSuccess(bytes32 requestId, uint256 tokenAmount, MintOrRedeem mintOrRedeem);
    event RequestExpired(bytes32 indexed requestId, address indexed requester, uint256 amount, MintOrRedeem mintOrRedeem);
    event RequestTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);

    /////////////////////
    // External Functions
    /////////////////////
    
    function _mintAsset(
        uint256 usdAmount, 
        address requester, 
        string memory accountId
    ) external returns (bytes32 requestId);

    function _redeemAsset(
        uint256 assetAmount, 
        address requester, 
        string memory accountId
    ) external returns (bytes32 requestId);

    function onFulfill(
        bytes32 requestId, 
        uint256 tokenAmount, 
        bool success
    ) external;

    function cleanupExpiredRequests(bytes32[] calldata requestIds) external;

    function isRequestExpired(bytes32 requestId) external view returns (bool expired);

    function getTimeRemaining(bytes32 requestId) external view returns (uint256 timeRemaining);

    function pause() external;

    function unpause() external;

    function setRequestTimeout(uint256 newTimeout) external;

    function emergencyExpireRequests(bytes32[] calldata requestIds) external;
    
    function _setRequestTimeout(uint256 newTimeout) external;

    function _expireRequests(bytes32[] calldata requestIds) external;

    function _emergencyWithdraw(
        address token, 
        uint256 amount, 
        address to
    ) external;

    /////////////////////
    // View Functions
    /////////////////////
    
    function getRequest(bytes32 requestId) external view returns (AssetRequest memory);

    function getRequestWithStatus(bytes32 requestId) 
        external 
        view 
        returns (
            AssetRequest memory request, 
            bool isExpired, 
            uint256 timeRemaining
        );

    function requestTimeout() external view returns (uint256);
}