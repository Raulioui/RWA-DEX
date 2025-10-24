interface IChainlinkCaller {
    function requestMint(uint256 usdAmount, string memory accountId, string memory symbol) external returns (bytes32);
    function requestRedeem(uint256 usdAmount, string memory accountId, string memory symbol) external returns (bytes32);
    function authorizeToken(string memory symbol, address token) external;
    function deAuthorizeToken(string memory symbol, address token) external;
}