// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {Core} from "oz-foundry-upgrades/internal/Core.sol";
import {Upgrades} from "oz-foundry-upgrades/Upgrades.sol";
import {Options} from "oz-foundry-upgrades/Options.sol";
import {Utils} from "oz-foundry-upgrades/internal/Utils.sol";

library UpgradesWithCreate2 {
    /**
     * @dev Deploys a UUPS proxy with a salt using the given contract as the implementation.
     *
     * @param contractName Name of the contract to use as the implementation, e.g. "MyContract.sol" or "MyContract.sol:MyContract" or artifact path relative to the project root directory
     * @param initializerData Encoded call data of the initializer function to call during creation of the proxy, or empty if no initialization is required
     * @param opts Common options
     * @param salt Salt to use for the CREATE2 deployment of the proxy
     * @return Proxy address
     */
    function deployUUPSProxy(
        string memory contractName,
        bytes memory initializerData,
        Options memory opts,
        bytes32 salt
    ) internal returns (address) {
        address impl = Upgrades.deployImplementation(contractName, opts);

        return _deploy("ERC1967Proxy.sol:ERC1967Proxy", abi.encode(impl, initializerData), opts, salt);
    }

    function _deploy(
        string memory contractName,
        bytes memory constructorData,
        Options memory opts,
        bytes32 salt
    ) private returns (address) {
        bytes memory creationCode = Vm(Utils.CHEATCODE_ADDRESS).getCode(contractName);
        address deployedAddress = _deployFromBytecodeWithSalt(abi.encodePacked(creationCode, constructorData), salt);
        if (deployedAddress == address(0)) {
            revert(
                string(
                    abi.encodePacked(
                        "Failed to deploy contract ",
                        contractName,
                        ' using constructor data "',
                        string(constructorData),
                        '"'
                    )
                )
            );
        }
        return deployedAddress;
    }

    function _deployFromBytecodeWithSalt(bytes memory bytecode, bytes32 salt) private returns (address) {
        address addr;
        /// @solidity memory-safe-assembly
        assembly {
            addr := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        return addr;
    }

}