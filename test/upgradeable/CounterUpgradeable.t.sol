// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {CounterUpgradeable} from "src/CounterUpgradeable.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "../utils/EasyPosm.sol";
import {Fixtures} from "../utils/Fixtures.sol";

import {BaseHookUpgradeable} from "src/BaseHookUpgradeable.sol";
import {CounterUpgradeableV2} from "./CounterUpgradeableV2.sol";

import {Upgrades} from "oz-foundry-upgrades/Upgrades.sol";
import {Options} from "oz-foundry-upgrades/Options.sol";

contract CounterUpgradeableTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    CounterUpgradeable hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the implementation contract to any address
        CounterUpgradeable implementation = new CounterUpgradeable();

        // Deploy the proxy to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        // From here on, we'll refer to the proxy as the "hook"
        // Deploy the hook to our address
        bytes memory implementationInitializeCall = abi.encodeCall(CounterUpgradeable.initialize, manager); // Add all the necessary arguments for the implementation contract
        bytes memory proxyConstructorArgs = abi.encode(implementation, implementationInitializeCall);
        deployCodeTo("ERC1967Proxy.sol:ERC1967Proxy", proxyConstructorArgs, flags);
        hook = CounterUpgradeable(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testUpgrade() public {
        Upgrades.upgradeProxy(address(hook), "CounterUpgradeableV2.sol:CounterUpgradeableV2", "");

        uint256 beforeSwapCount = hook.beforeSwapCount(poolId);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // assert that count increased by TWO (successful upgrade)
        assertEq(hook.beforeSwapCount(poolId), beforeSwapCount + 2);
    }
}