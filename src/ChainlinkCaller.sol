// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/FunctionsClient.sol";
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol";
import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import {IAssetToken} from "./interfaces/IAssetToken.sol";

/**
 * @title ChainlinkCaller
 * @notice Connects the protocol with the alpaca API
*/

contract ChainlinkCaller is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    /////////////////////
    // Storage
    /////////////////////

    event FunctionsResult(bytes32 indexed id, bytes response, bytes err);

    mapping(bytes32 => address) public requestToToken;
    mapping(string => address) public authorizedTokens;

    modifier onlyAuthorizedToken(string memory ticket) {
        address tokenAddress = authorizedTokens[ticket];
        require(tokenAddress != address(0), "ChainlinkCaller: Token not registered");
        require(msg.sender == tokenAddress, "ChainlinkCaller: Not authorized");
        _; 
    }

    uint64 public subId;
    bytes32 public donID;
    address public assetPool;

    uint32 private constant GAS_LIMIT = 300_000;
    string public ALPACA_MINT_SOURCE;
    string public ALPACA_REDEEM_SOURCE;

    uint64 secretVersion;

    /////////////////////
    // Constructor
    /////////////////////

    constructor(
        uint64 _subId,
        address _functionsRouter,
        bytes32 _donID
    ) FunctionsClient(_functionsRouter) ConfirmedOwner(msg.sender) {
        subId = _subId;
        donID = _donID;
    }

    /////////////////////
    // External Functions
    /////////////////////

    function requestMint(uint256 usdAmount, string memory accountId, string memory ticket) external onlyAuthorizedToken(ticket) returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;

        // Initialize the request with JS code
        req._initializeRequestForInlineJavaScript(ALPACA_MINT_SOURCE); 
        req._addDONHostedSecrets(0, secretVersion);

        string[] memory args = new string[](3);
        args[0] = ticket;
        args[1] = usdAmount.toString();
        args[2] = accountId;
        req._setArgs(args);

        // Send the request and store the request ID
        requestId = _sendRequest(req._encodeCBOR(), subId, GAS_LIMIT, donID);

        requestToToken[requestId] = msg.sender;
    }

    function requestRedeem(uint256 assetAmount, string memory accountId, string memory ticket) external onlyAuthorizedToken(ticket) returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;

        // Initialize the request with JS code
        req._initializeRequestForInlineJavaScript(ALPACA_REDEEM_SOURCE); 
        req._addDONHostedSecrets(0, secretVersion);

        string[] memory args = new string[](3);
        args[0] = ticket;
        args[1] = accountId;
        args[2] = assetAmount.toString();
        req._setArgs(args);

        // Send the request and store the request ID
        requestId = _sendRequest(req._encodeCBOR(), subId, GAS_LIMIT, donID);
        requestToToken[requestId] = msg.sender;
    }

    /////////////////////
    // Internal Functions
    /////////////////////

    /**
     * @notice Callback function for fulfilling a request from Chainlink
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     */
    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    )
        internal
        override
    {

        address token = requestToToken[requestId];
    
        uint256 tokenAmount = uint256(bytes32(response));
        bool success = err.length == 0;

        if(!success) {
            emit FunctionsResult(requestId, response, err);
        }
 
        IAssetToken(token).onFulfill(requestId, tokenAmount, success);
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

    function setJsSources(string memory _mintSource, string memory _sellSource) external onlyOwner {
        ALPACA_MINT_SOURCE = _mintSource;
        ALPACA_REDEEM_SOURCE = _sellSource;
    }

    /////////////////////
    // Owner Functions
    /////////////////////

    function setAssetPool(address _assetPool) external onlyOwner {
        require(assetPool == address(0), "Asset pool already set");
        assetPool = _assetPool;
    }

    function setSecretVersion(uint64 _secretVersion) external onlyOwner {
        secretVersion = _secretVersion;
    }
}