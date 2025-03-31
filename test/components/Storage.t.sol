// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "../../src/components/Storage.sol";

contract StorageTest is Test {
    Storage storageContract;

    function setUp() public {
        storageContract = new Storage();
    }

    function testSetAndGet() public {
        uint256 testValue = 42;
        storageContract.set(testValue);
        uint256 number = storageContract.get();
        assertEq(number, testValue);
    }

    function testStorageSlot() public {
        uint256 testValue = 12345;
        storageContract.set(testValue);

        // Read storage slot 0 directly
        bytes32 storedValue = vm.load(address(storageContract), bytes32(uint256(0)));

        assertEq(uint256(storedValue), testValue);
    }
}
