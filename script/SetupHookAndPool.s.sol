// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { UniversalRouter } from "universal-router/contracts/UniversalRouter.sol";
import { Commands } from "universal-router/contracts/libraries/Commands.sol";
import { PoolManager } from "v4-core/src/PoolManager.sol";
import { IV4Router } from "v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "v4-periphery/src/libraries/Actions.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency } from "v4-core/src/types/Currency.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import {Constants} from "v4-core/src/../test/utils/Constants.sol";

import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradesWithCreate2} from "../src/UpgradesWithCreate2.sol";
import {Options} from "oz-foundry-upgrades/Options.sol";

import { CamelotHook } from "../src/CamelotHook.sol";

contract SetupHookAndPool is Script {
    function run() external {
        vm.startBroadcast();

        // Define contract and token addresses
        address router = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3; // UniversalRouter
        address poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32; // PoolManager
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Permit2
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        address token0 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH 
        address token1 = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        // set up hook
        // compute where the implementation will be deployed
        address implementationAddress = computeCreateAddress(address(msg.sender), vm.getNonce(address(msg.sender)));
        
        // encode the initialization data for the implementation contract
        IPoolManager manager = IPoolManager(address(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32));
        bytes memory implementationInitializeData = abi.encodeCall(CamelotHook.initialize, manager);
        
        // Mine a salt that will produce a hook address with the correct permissions
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(ERC1967Proxy).creationCode, 
                            abi.encode(implementationAddress, implementationInitializeData));
        
        
        // ------------------------------------- //
        // Deploy the hook & proxy using CREATE2 //
        // ------------------------------------- //

        Options memory opts;
        address proxyAddress = UpgradesWithCreate2.deployUUPSProxy(
            "CamelotHook.sol:CamelotHook",
            implementationInitializeData,
            opts,
            salt
        );

        // treat our proxy as a CounterUpgradeable
        CamelotHook hook = CamelotHook(proxyAddress);

        // check that our proxy has an address that encodes the correct permissions
        Hooks.validateHookPermissions(hook, hook.getHookPermissions());
        
        require(proxyAddress == hookAddress, "CounterScript: hook address mismatch");

        // Prepare PoolKey for the Uniswap V4 pool
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0, // TODO: Replace with actual fee tier
            tickSpacing: 10, // TODO: Replace with actual tick spacing
            hooks: hook // TODO: Replace with actual hooks contract if needed
        });

        manager.initialize(key, Constants.SQRT_PRICE_1_1);

        vm.stopBroadcast();
    }
}