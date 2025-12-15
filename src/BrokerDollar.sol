// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BrokerDollar is ERC20, Ownable {
address public assetPool;
    uint256 public constant INITIAL_BALANCE = 10_000 ether;

    constructor() ERC20("Broker Dollar", "bUSD") Ownable(msg.sender) {}

    function setAssetPool(address _assetPool) external onlyOwner {
        require(assetPool == address(0), "AssetPool already set");
        require(_assetPool != address(0), "Zero address");
        assetPool = _assetPool;
    }

    function mintOnRegister(address user) external {
        require(msg.sender == assetPool, "Only AssetPool");
        _mint(user, INITIAL_BALANCE);
    }
}