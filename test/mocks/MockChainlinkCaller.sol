
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IAssetToken } from "../../src/interfaces/IAssetToken.sol";

/**
 * @title MockChainlinkCaller  
 * @notice Mock contract to simulate ChainlinkCaller behavior for testing
 */
contract MockChainlinkCaller {
    // Events that match the real ChainlinkCaller
    event RequestSent(bytes32 indexed requestId);
        
    // Storage for tracking requests
    mapping(bytes32 => address) public requestToToken;
        
    // Counter for generating unique request IDs
    uint256 private requestCounter;

    string public ALPACA_MINT_SOURCE;
    string public ALPACA_REDEEM_SOURCE;

    address public assetPool;

    mapping(string => address) public authorizedTokens;

    modifier onlyAuthorizedToken(string memory ticket) {
        address tokenAddress = authorizedTokens[ticket];
        require(tokenAddress != address(0), "ChainlinkCaller: Token not registered");
        require(msg.sender == tokenAddress, "ChainlinkCaller: Not authorized");
        _;
    }

    function requestMint(uint256 usdAmount, string memory accountId, string memory ticket) 
        external 
        onlyAuthorizedToken(ticket)
        returns (bytes32 requestId) 
    {
        // Generate a unique request ID
        requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, requestCounter++));
        
        // Store the request mapping
        requestToToken[requestId] = msg.sender;
        
        emit RequestSent(requestId);
        
        return requestId;
    }

    function requestRedeem(uint256 assetAmount, string memory accountId, string memory ticket) 
        external 
        onlyAuthorizedToken(ticket)
        returns (bytes32 requestId) 
    {
        // Generate a unique request ID
        requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, requestCounter++));
        
        // Store the request mapping
        requestToToken[requestId] = msg.sender;
        
        emit RequestSent(requestId);
        
        // Don't call onFulfill immediately - that will be done separately
        return requestId;
    }

    // Test helper to automatically fulfill with the same amount (for simple tests)
    function fulfillMintRequest(bytes32 requestId, uint256 tokenAmount) external {
        fulfillRequest(requestId, tokenAmount, true);
    }

    // Test helper to fulfill with error
    function fulfillRequestWithError(bytes32 requestId) external {
        fulfillRequest(requestId, 0, false);
    }

    // Test helper function to simulate fulfillment
    function fulfillRequest(bytes32 requestId, uint256 tokenAmount, bool success) public {
        address token = requestToToken[requestId];
        require(token != address(0), "Invalid request ID");
        
        IAssetToken(token).onFulfill(requestId, tokenAmount, success);
    }

    function setJsSources(string memory _mintSource, string memory _sellSource) external {
        ALPACA_MINT_SOURCE = _mintSource;
        ALPACA_REDEEM_SOURCE = _sellSource;
    }

    function setAssetPool(address _assetPool) external {
        require(assetPool == address(0), "Asset pool already set");
        assetPool = _assetPool;
    }

    function authorizeToken(string memory ticket, address token) external {
        require(msg.sender == assetPool, "Not allowed to authorize");
        
        authorizedTokens[ticket] = token;
    }

    function deAuthorizeToken(string memory ticket, address token) external {
        require(msg.sender == assetPool, "Not allowed to deauthorize");
        address registeredToken = authorizedTokens[ticket];
        require(registeredToken == token, "Token address mismatch");

        delete authorizedTokens[ticket];
    }


}