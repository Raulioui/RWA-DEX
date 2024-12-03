// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { OracleLib, AggregatorV3Interface } from "../libraries/OracleLib.sol";

/**
 * @title dTSLA
 * @notice This is our contract to make requests to the Alpaca API to mint TSLA-backed dTSLA tokens
 * @dev This contract is meant to be for educational purposes only
 */
contract dTSLA is FunctionsClient, ConfirmedOwner, ERC20, Pausable {
    using FunctionsRequest for FunctionsRequest.Request;
    using OracleLib for AggregatorV3Interface;
    using Strings for uint256;

    /**
     * @notice Events
    */
    
    event Response(bytes32 indexed requestId, uint256 character, bytes response, bytes err);

    /**
     * @notice Storage
    */

    error dTSLA__NotEnoughCollateral();
    error dTSLA__BelowMinimumRedemption();
    error dTSLA__RedemptionFailed();

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    uint32 private constant GAS_LIMIT = 300_000;
    uint64 immutable subId;

    // Check to get the router address for your supported network
    // https://docs.chain.link/chainlink-functions/supported-networks
    address functionsRouter;
    string mintSource;
    string redeemSource;

    // Check to get the donID for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    bytes32 donID;
    uint256 portfolioBalance;
    uint64 secretVersion;
    uint8 secretSlot;

    mapping(bytes32 requestId => dTslaRequest request) private requestIdToRequest;
    mapping(address user => uint256 amountAvailableForWithdrawal) private userToWithdrawalAmount;

    address public tslaUsdFeed;
    address public usdcUsdFeed;
    address public redemptionCoin;

    // This hard-coded value isn't great engineering. Please check with your brokerage
    // and update accordingly
    // For example, for Alpaca: https://alpaca.markets/support/crypto-wallet-faq
    uint256 public constant MINIMUM_REDEMPTION_COIN_REDEMPTION_AMOUNT = 100e18;

    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PORTFOLIO_PRECISION = 1e18;
    uint256 public constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 public constant COLLATERAL_PRECISION = 100;

    uint256 private constant TARGET_DECIMALS = 18;
    uint256 private constant PRECISION = 1e18;
    uint256 private immutable redemptionCoinDecimals;

    ///@notice Initializes the contract with the Chainlink router address and sets the contract owner
    constructor(
        uint64 _subId,
        string memory _mintSource,
        address _functionsRouter,
        bytes32 _donId,
        address _tslaPriceFeed,
        address _usdcPriceFeed,
        address _redemptionCoin,
        uint64 _secretVersion,
        uint8 _secretSlot
    )
        FunctionsClient(_functionsRouter)
        ConfirmedOwner(msg.sender)
        ERC20("Backed TSLA", "bTSLA")
    {
        mintSource = _mintSource;
        functionsRouter = _functionsRouter;
        donID = _donId;
        tslaUsdFeed = _tslaPriceFeed;
        usdcUsdFeed = _usdcPriceFeed;
        subId = _subId;
        redemptionCoin = _redemptionCoin;
        redemptionCoinDecimals = ERC20(redemptionCoin).decimals();

        secretVersion = _secretVersion;
        secretSlot = _secretSlot;
    }

    /**
     * @notice External Functions
    */

    /**
     * @notice Sends an HTTP request for buy TSLA.
     * @param assetsToBuy The amount of stocks to buy
     * @return requestId The ID of the request
     */
    function sendMintRequest(uint8 assetsToBuy)
        external
        onlyOwner
        whenNotPaused
        returns (bytes32 requestId)
    {       
        FunctionsRequest.Request memory req;

        // Initialize the request with JS code
        req._initializeRequestForInlineJavaScript(mintSource); 
        req._addDONHostedSecrets(secretSlot, secretVersion);

        bytes[] memory args = new bytes[](1);
        args[0] = abi.encode(assetsToBuy);
        req._setBytesArgs(args);

        // Send the request and store the request ID
        requestId = _sendRequest(req._encodeCBOR(), subId, GAS_LIMIT, donID);
        requestIdToRequest[requestId] = dTslaRequest(assetsToBuy * PRECISION, msg.sender, MintOrRedeem.mint);
        return requestId;
    }

    /*
     * @notice user sends a Chainlink Functions request to sell TSLA for redemptionCoin
     * @notice this will put the redemptionCoin in a withdrawl queue that the user must call to redeem
     * 
     * @dev Burn dTSLA
     * @dev Sell TSLA on brokerage
     * @dev Buy USDC on brokerage
     * @dev Send USDC to this contract for user to withdraw
     * 
     * @param amountdTsla - the amount of dTSLA to redeem
     */
    function sendRedeemRequest(uint256 amountdTsla) external whenNotPaused returns (bytes32 requestId) {
        // Should be able to just always redeem?
        // @audit potential exploit here, where if a user can redeem more than the collateral amount
        // Checks
        // Remember, this has 18 decimals
        uint256 amountTslaInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTsla));
        if (amountTslaInUsdc < MINIMUM_REDEMPTION_COIN_REDEMPTION_AMOUNT) {
            revert dTSLA__BelowMinimumRedemption();
        }

        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(redeemSource); // Initialize the request with JS code

        // Pass the amount of dTSLA to buy
        string[] memory args = new string[](1);
        args[0] = amountdTsla.toString();
        req._setArgs(args);

        // Send the request and store the request ID
        // We are assuming requestId is unique
        requestId = _sendRequest(req._encodeCBOR(), subId, GAS_LIMIT, donID);
        requestIdToRequest[requestId] = dTslaRequest(amountdTsla, msg.sender, MintOrRedeem.redeem);

        // External Interactions
        _burn(msg.sender, amountdTsla);
    }

    function withdraw() external whenNotPaused {
        uint256 amountToWithdraw = userToWithdrawalAmount[msg.sender];
        userToWithdrawalAmount[msg.sender] = 0;
        // Send the user their USDC
        bool succ = ERC20(redemptionCoin).transfer(msg.sender, amountToWithdraw);
        if (!succ) {
            revert dTSLA__RedemptionFailed();
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setSecretVersion(uint64 _secretVersion) external onlyOwner {
        secretVersion = _secretVersion;
    }

    function setSecretSlot(uint8 _secretSlot) external onlyOwner {
        secretSlot = _secretSlot;
    }

    function setRedeemSource(string memory _redeemSource) external onlyOwner {
        redeemSource = _redeemSource;
    }

    /**
     * @notice Internal Functions
    */

    /**
     * @notice Callback function for fulfilling a request from Chainlink
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     */
    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory /* err */
    )
        internal
        override
        whenNotPaused
    {
        if (requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.mint) {
            _mintFulFillRequest(requestId, response);
        } else {
            _redeemFulFillRequest(requestId, response);
        }
    }

    function _mintFulFillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = requestIdToRequest[requestId].amountOfToken;
        portfolioBalance = uint256(bytes32(response));

        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        if (amountOfTokensToMint != 0) {
            _mint(requestIdToRequest[requestId].requester, amountOfTokensToMint);
        }
        // Do we need to return anything?
    }

    /*
     * @notice the callback for the redeem request
     * At this point, USDC should be in this contract, and we need to update the user
     * That they can now withdraw their USDC
     * 
     * @param requestId - the requestId that was fulfilled
     * @param response - the response from the request, it'll be the amount of USDC that was sent
     */
    function _redeemFulFillRequest(bytes32 requestId, bytes memory response) internal {
        // This is going to have redemptioncoindecimals decimals
        uint256 usdcAmount = uint256(bytes32(response));
        uint256 usdcAmountWad;
        if (redemptionCoinDecimals < 18) {
            usdcAmountWad = usdcAmount * (10 ** (18 - redemptionCoinDecimals));
        }
        if (usdcAmount == 0) {
            // revert dTSLA__RedemptionFailed();
            // Redemption failed, we need to give them a refund of dTSLA
            // This is a potential exploit, look at this line carefully!!
            uint256 amountOfdTSLABurned = requestIdToRequest[requestId].amountOfToken;
            _mint(requestIdToRequest[requestId].requester, amountOfdTSLABurned);
            return;
        }

        userToWithdrawalAmount[requestIdToRequest[requestId].requester] += usdcAmount;
    }

    function _getCollateralRatioAdjustedTotalBalance(uint256 assetsToBuy) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(assetsToBuy);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    
    /**
     * @notice View & Pure Functions
    */

    function getPortfolioBalance() public view returns (uint256) {
        return portfolioBalance;
    }

    // TSLA USD has 8 decimal places, so we add an additional 10 decimal places
    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tslaUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getUsdcPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(usdcUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    /* 
     * Pass the USD amount with 18 decimals (WAD)
     * Return the redemptionCoin amount with 18 decimals (WAD)
     * 
     * @param usdAmount - the amount of USD to convert to USDC in WAD
     * @return the amount of redemptionCoin with 18 decimals (WAD)
     */
    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount * PRECISION) / getUsdcPrice();
    }

    function getTotalUsdValue() public view returns (uint256) {
        return (totalSupply() * getTslaPrice()) / PRECISION;
    }

    function getCalculatedNewTotalValue(uint256 addedNumberOfTsla) public view returns (uint256) {
        return ((totalSupply() + addedNumberOfTsla) * getTslaPrice()) / PRECISION;
    }

    function getRequest(bytes32 requestId) public view returns (dTslaRequest memory) {
        return requestIdToRequest[requestId];
    }

    function getWithdrawalAmount(address user) public view returns (uint256) {
        return userToWithdrawalAmount[user];
    }
}