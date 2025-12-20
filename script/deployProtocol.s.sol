// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";

import {AssetPool} from "../src/AssetPool.sol";
import {ChainlinkCaller} from "../src/ChainlinkCaller.sol";
import {IGetChainlinkConfig} from "../src/interfaces/IGetChainlinkConfig.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {BrokerDollar} from "../src/BrokerDollar.sol";
import {BrokerGovernanceToken} from "../src/Governance/BrokerGovernanceToken.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {RWAGovernor} from "../src/Governance/RWAGovernor.sol";

contract DeployProtocol is Script {
    string constant alpacaMintSource   = "./functions/sources/mintAsset.js";
    string constant alpacaRedeemSource = "./functions/sources/redeemAsset.js";

    string mintSource = vm.readFile(alpacaMintSource);
    string sellSource = vm.readFile(alpacaRedeemSource);

    function run() external {
        IGetChainlinkConfig.GetChainlinkConfig memory chainlinkValues = getChainlinkConfig();

        vm.startBroadcast(); // usa la PK que hayas configurado en Foundry

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

        console2.log("ChainlinkCaller:", chainlinkCallerAddr);
        console2.log("AssetPool:      ", assetPoolAddr);
        console2.log("BrokerDollar:   ", brokerDollarAddr);
        console2.log("BGT:            ", bgtAddr);
        console2.log("Timelock:       ", timelockAddr);
        console2.log("Governor:       ", governorAddr);
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
        BrokerGovernanceToken bgt = new BrokerGovernanceToken(); 
        // IMPORTANTE: que el constructor de BGT haga _mint(msg.sender, TOTAL_SUPPLY)

        // 2) Chainlink Functions caller
        ChainlinkCaller chainlinkCaller = new ChainlinkCaller(
            _subId,
            _functionsRouter,
            _donID
        );

        // 3) AssetPool (owner inicial = msg.sender del broadcast)
        AssetPool assetPool = new AssetPool(
            address(chainlinkCaller),
            address(brokerDollar)
        );

        // 4) BrokerDollar <-> AssetPool
        brokerDollar.setAssetPool(address(assetPool));

        // 5) Beacon de AssetToken
        AssetToken assetTokenImplementation = new AssetToken();
        assetPool.initializeBeacon(address(assetTokenImplementation));

        // 6) Configurar Chainlink caller
        chainlinkCaller.setJsSources(mintSource, sellSource);
        chainlinkCaller.setAssetPool(address(assetPool));

        // 7) TimelockController (gobernanza)
        uint256 minDelay = 2 days;

        address[] memory proposers = new address[](0); // nadie propone directo al timelock
        address[] memory executors = new address[](1);
        executors[0] = address(0);                     // cualquiera puede ejecutar

        TimelockController timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            msg.sender // admin inicial (tu EOA del broadcast)
        );

        // 8) Governor
        RWAGovernor governor = new RWAGovernor(
            bgt,
            timelock
        );

        // 9) Roles del timelock
        bytes32 PROPOSER_ROLE  = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE  = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        bytes32 ADMIN_ROLE     = timelock.DEFAULT_ADMIN_ROLE();

        // Governor puede proponer y cancelar
        timelock.grantRole(PROPOSER_ROLE,  address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));

        // Cualquiera puede ejecutar
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        // Al final te quitas tú de admin (quedará solo el timelock como self-admin)
        timelock.revokeRole(ADMIN_ROLE, msg.sender);

        // 10) Tesorería de la DAO (ajusta la cantidad a tu totalSupply real)
        bgt.transfer(address(timelock), 500_000 ether);

        // 11) AssetPool pasa a ser controlado por la gobernanza
        assetPool.transferOwnership(address(timelock));

        // (Opcional más adelante) que la DAO controle el mint de BGT:
        // bgt.transferOwnership(address(timelock));

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
