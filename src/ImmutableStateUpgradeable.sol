// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IImmutableState} from "v4-periphery/src/interfaces/IImmutableState.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/// @title Immutable State
/// @notice A collection of immutable state variables, commonly used across multiple contracts
contract ImmutableStateUpgradeable is IImmutableState, Initializable {
    /// @inheritdoc IImmutableState
    IPoolManager public poolManager;

    /// @notice Thrown when the caller is not PoolManager
    error NotPoolManager();

    /// @notice Only allow calls from the PoolManager contract
    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function initialize(IPoolManager _poolManager) public virtual onlyInitializing {
        poolManager = _poolManager;
    }
}
