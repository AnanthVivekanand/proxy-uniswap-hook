// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {CounterUpgradeable} from "../src/CounterUpgradeable.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradesWithCreate2} from "../src/UpgradesWithCreate2.sol";
import {Options} from "oz-foundry-upgrades/Options.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract CounterScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        // compute where the implementation will be deployed
        address implementationAddress = computeCreateAddress(address(this), vm.getNonce(address(this)));
        
        // encode the initialization data for the implementation contract
        bytes memory implementationInitializeData = abi.encodeCall(CounterUpgradeable.initialize, POOLMANAGER);
        
        // Mine a salt that will produce a hook address with the correct permissions
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(ERC1967Proxy).creationCode, 
                            abi.encode(implementationAddress, implementationInitializeData));
        
        
        // ------------------------------------- //
        // Deploy the hook & proxy using CREATE2 //
        // ------------------------------------- //

        Options memory opts;
        address proxyAddress = UpgradesWithCreate2.deployUUPSProxy(
            "CounterUpgradeable.sol",
            implementationInitializeData,
            opts,
            salt
        );

        // treat our proxy as a CounterUpgradeable
        CounterUpgradeable counter = CounterUpgradeable(proxyAddress);

        // check that our proxy has an address that encodes the correct permissions
        Hooks.validateHookPermissions(counter, counter.getHookPermissions());
        
        require(proxyAddress == hookAddress, "CounterScript: hook address mismatch");
    }
}
