// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.sol";
import { AssetPool } from "../src/AssetPool.sol";
import { ChainlinkCaller } from "../src/ChainlinkCaller.sol";
import { IGetChainlinkConfig } from "../src/interfaces/IGetChainlinkConfig.sol";
import { AssetToken } from "../src/AssetToken.sol";
import { BrokerDollar } from "../src/BrokerDollar.sol";
import { BrokerGovernanceToken } from "../src/Governance/BrokerGovernanceToken.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { RWAGovernor } from "../src/Governance/RWAGovernor.sol";

contract DeployProtocol is Script {
    string constant alpacaMintSource = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";
    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);

    function run() external {
        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = getChainlinkConfig();
        
        vm.startBroadcast();

        (
            address chainlinkCallerAddr,
            address assetPoolAddr,
            address brokerDollarAddr,
            address bgtAddr,
            address timelockAddr,
            address governorAddr
        ) = deployProtocol(
            chainlinkValues.subId,
            chainlinkValues.functionsRouter,
            chainlinkValues.donId
        );

        vm.stopBroadcast();
    }

    function getChainlinkConfig()
        public
        returns (IGetChainlinkConfig.GetChainlinkConfig memory)
    {
        HelperConfig helperConfig = new HelperConfig();
        (
            address functionsRouter,
            bytes32 donId,
            uint64 subId
        ) = helperConfig.activeNetworkConfig();

        if (functionsRouter == address(0) || donId == bytes32(0) || subId == 0) {
            revert("something is wrong");
        }

        return IGetChainlinkConfig.GetChainlinkConfig(
            subId,
            functionsRouter,
            donId
        );
    }

    function deployProtocol(
        uint64 _subId,
        address _functionsRouter,
        bytes32 _donID
    )
        public
        returns (
            address chainlinkCallerAddr,
            address assetPoolAddr,
            address brokerDollarAddr,
            address bgtAddr,
            address timelockAddr,
            address governorAddr
        )
    {
        // 1) Tokens internos
        BrokerDollar brokerDollar = new BrokerDollar();
        BrokerGovernanceToken bgt = new BrokerGovernanceToken(); // asumo que mintea todo el supply al deployer

        // 2) Chainlink caller
        ChainlinkCaller chainlinkCaller = new ChainlinkCaller(
            _subId,
            _functionsRouter,
            _donID
        );

        // 3) AssetPool
        AssetPool assetPool = new AssetPool(
            address(chainlinkCaller),
            address(brokerDollar)
        );

        // 4) Wire BrokerDollar <-> AssetPool
        brokerDollar.setAssetPool(address(assetPool));

        // 5) AssetToken beacon implementation
        AssetToken assetTokenImplementation = new AssetToken();
        assetPool.initializeBeacon(address(assetTokenImplementation));

        // 6) Configurar Chainlink caller
        chainlinkCaller.setJsSources(mintSource, sellSource);
        chainlinkCaller.setAssetPool(address(assetPool));

        // 7) TimelockController (gobernanza)
        uint256 minDelay = 2 days;

        // Arrays de roles: empezamos con proposers vacío, executors = cualquiera
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // address(0) = cualquiera puede ejecutar

        TimelockController timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            msg.sender // admin inicial (tu EOA durante el broadcast)
        );


        // 8) Governor
        RWAGovernor governor = new RWAGovernor(
            bgt,
            timelock
        );

        // 9) Configurar roles en el timelock
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        timelock.revokeRole(ADMIN_ROLE, msg.sender);

        // Governor puede proponer
        timelock.grantRole(PROPOSER_ROLE, address(governor));

        // Ejecutar: cualquiera
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        // 10) Mover parte del supply de BGT al timelock como tesorería de la DAO
        bgt.transfer(address(timelock), 500_000 ether);

        // 11) Transferir ownership de AssetPool al timelock para que la gobernanza controle el protocolo
        assetPool.transferOwnership(address(timelock));

        // (Opcional) si BrokerGovernanceToken es Ownable y quieres que la DAO controle el mint:
        // bgt.transferOwnership(address(timelock));

        // 12) Devolver direcciones útiles
        return (
            address(chainlinkCaller),
            address(assetPool),
            address(brokerDollar),
            address(bgt),
            address(timelock),
            address(governor)
        );
    }
}
