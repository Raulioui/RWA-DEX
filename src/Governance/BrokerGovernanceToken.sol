// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BrokerGovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /// @notice Suministro máximo total del token de gobernanza
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    /// @notice Cantidad sugerida como “bonus” por registro (si decides usarlo)
    uint256 public constant REGISTER_BONUS = 1_000 ether;

    constructor()
        ERC20("Broker Governance Token", "BGT")
        ERC20Permit("Broker Governance Token")
        Ownable(msg.sender) // OZ v5: pasas el owner inicial aquí
    {
        // Mint completo al deployer (tu EOA en el script de deploy)
        // Esto cuadra con el script que hace:
        // - 500k para el timelock
        // - el resto te queda a ti para repartir a usuarios / testers
        _mint(msg.sender, MAX_SUPPLY);
    }

    /// @notice Mint genérico, controlado por el owner (deployer o, más adelante, el timelock)
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }

    /// @notice Mint específico del “bonus de registro”
    /// @dev Lo usarías desde un contrato / script externo, NO automáticamente en registerUser on-chain en mainnet.
    function mintRegisterBonus(address to) external onlyOwner {
        require(
            totalSupply() + REGISTER_BONUS <= MAX_SUPPLY,
            "Max supply exceeded"
        );
        _mint(to, REGISTER_BONUS);
    }

    // Overrides requeridos por ERC20Votes

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(
        address owner
    ) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
