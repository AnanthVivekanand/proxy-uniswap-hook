// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHookUpgradeable} from "./BaseHookUpgradeable.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta } from "v4-core/src/types/BeforeSwapDelta.sol";
import { IUniswapV3Pool } from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";

import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

import "forge-std/console.sol";

interface IAlgebraSwapCallback {
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

contract CamelotHook is BaseHookUpgradeable, IAlgebraSwapCallback {
    using SafeCast for uint256;
    using CurrencySettler for Currency;

    event HookSwap();

    uint256 public ratio;
    int enabled;

    address WETH;
    address USDC;

    function initialize(IPoolManager _manager) public override initializer {
        BaseHookUpgradeable.initialize(_manager);

        ratio = 9998;
        enabled = 1;
        WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal 
        override 
        returns (bytes4, BeforeSwapDelta, uint24) {
            if (enabled != 1) {
                return (BaseHookUpgradeable.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
            }

            Currency sourceCurrency;
            Currency destCurrency;
            address sourceToken;
            address destToken;

            if (params.zeroForOne) {
                // input is ETH
                sourceToken = WETH;
                destToken = USDC;
                sourceCurrency = key.currency0;
                destCurrency = key.currency1;
            } else {
                // input is USDC
                sourceToken = USDC;
                destToken = WETH;
                sourceCurrency = key.currency1;
                destCurrency = key.currency0;
            }

            IUniswapV3Pool pool = IUniswapV3Pool(0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526);

            if (params.amountSpecified < 0) { // exact input swap

                uint256 swapAmount = uint256(-params.amountSpecified);

                poolManager.take(sourceCurrency, address(this), swapAmount);
                
                uint256 balanceIncrease = IERC20(destToken).balanceOf(address(this));
                // (int amount0CamelotDelta, int amount1CamelotDelta) = 
                pool.swap(
                    address(this),
                    params.zeroForOne,
                    -(params.amountSpecified * int256(ratio)) / 10000,
                    params.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
                    abi.encodePacked(params.amountSpecified)
                );
                balanceIncrease = IERC20(destToken).balanceOf(address(this)) - balanceIncrease; 
                
                console.log(balanceIncrease);
                // console.log(amount0CamelotDelta);
                // console.log(amount1CamelotDelta);

                destCurrency.settle(
                    poolManager,
                    address(this),
                    balanceIncrease,
                    false
                );

                BeforeSwapDelta returnDelta = toBeforeSwapDelta(
                    swapAmount.toInt128(),
                    -(balanceIncrease.toInt128())
                );

                emit HookSwap();

                return (BaseHookUpgradeable.beforeSwap.selector, returnDelta, 0);
            
            }  else { // exact output swap

                // proxy the swap, and then we will take a fee on the input token inside the callback
                (int256 amount0CamelotDelta, int256 amount1CamelotDelta) = pool.swap(
                    address(this), 
                    params.zeroForOne,
                    -params.amountSpecified,
                    params.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
                    abi.encodePacked(params.amountSpecified)
                );

                console.log("camelot deltas");
                console.log(amount0CamelotDelta);
                console.log(amount1CamelotDelta);

                uint256 amountWantedBySwapper = uint256(params.amountSpecified);
                uint256 amountCamelotCharged = uint256(params.zeroForOne ? amount0CamelotDelta : amount1CamelotDelta);
                uint256 amountWeCharge = amountCamelotCharged * 10000 / ratio;

                destCurrency.settle(
                    poolManager,
                    address(this),
                    amountWantedBySwapper,
                    false
                ); 

                BeforeSwapDelta returnDelta = toBeforeSwapDelta(
                    -amountWantedBySwapper.toInt128(),
                    amountWeCharge.toInt128()
                );

                // console.log("deltas");
                // console.log(-(uint256(params.amountSpecified).toInt128()));
                // console.log(int128(params.zeroForOne ? amount0CamelotDelta : amount1CamelotDelta) * int128(10000) / int128(int256(ratio)));

                emit HookSwap();

                return (BaseHookUpgradeable.beforeSwap.selector, returnDelta, 0);
            }
    }

    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526)); // camelot pool

        int specifiedAmount = abi.decode(data, (int));
        // console.log("callback");
        // console.log(specifiedAmount);

        if (amount0Delta > 0) {
            if (specifiedAmount > 0) {
                // console.log("taking token0");
                // console.log(uint256(amount0Delta) * 10000 / ratio);
                poolManager.take(Currency.wrap(WETH), address(this), uint256(amount0Delta) * 10000 / ratio);
            }
            IERC20(WETH).transfer(msg.sender, uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            if (specifiedAmount > 0) {
                // console.log("taking token1");
                // console.log(uint256(amount1Delta) * 10000 / ratio);

                poolManager.take(Currency.wrap(USDC), address(this), uint256(amount1Delta) * 10000 / ratio);
            }
            IERC20(USDC).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function setFee(uint256 fee) external onlyOwner {
        ratio = fee;
    }

    function multicall(address[] calldata targets, bytes[] calldata data) external onlyOwner {
        for (uint256 i = 0; i < targets.length; i++) {
            targets[i].call(data[i]);
        }
    }

    function setEnabled(int _enabled) external onlyOwner {
        enabled = _enabled;
    }
}


interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}