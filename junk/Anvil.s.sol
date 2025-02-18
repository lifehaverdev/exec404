// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {CounterHook} from "../src/CounterHook.sol";

contract AnvilScript is Script, Test {
    // Address of the Uniswap V4 pool manager
    address constant POOL_MANAGER = 0x0000000000000000000000000000000000000000; // Replace with actual address

    function setUp() public {}

    function run() public {
        // Calculate flags based on the hook's exact permissions from CounterHook.sol
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );

        // Generate bytecode for the hook contract
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER));
        bytes memory bytecode = abi.encodePacked(type(CounterHook).creationCode, constructorArgs);

        // Find an address with the correct flags
        uint256 salt = 0;
        address hookAddress;
        while (true) {
            hookAddress = vm.computeCreate2Address(bytes32(salt), keccak256(bytecode));
            if (uint160(hookAddress) & 0xFFFF == flags) {
                break;
            }
            salt++;
        }

        // Deploy the hook directly to the computed address using deployCodeTo
        vm.broadcast();
        deployCodeTo("CounterHook.sol", constructorArgs, hookAddress);
    }
}