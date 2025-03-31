// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Storage {
    // Store a uint256 at slot 0 using inline assembly
    function set(uint256 _value) public {
        assembly {
            sstore(0, _value) // Store value in slot 0
        }
    }

    function get() public view returns (uint256 value) {
        assembly {
            value := sload(0) // Load value from slot 0
        }
    }
}
