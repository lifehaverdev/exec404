// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {EXEC404} from "../src/DN404EXEC.sol";

contract DeployScript is Script {
    function run() public returns (EXEC404) {

        // Create merkle roots for 12 days (in real deployment, these would be actual merkle roots)
        bytes32[] memory roots = new bytes32[](12);
        
        // First root is provided directly as bytes32
        roots[0] = 0x3f3b783b4f1d3b330569137d974e88bbab61b33f6e7c8b49ed0b1a8dd1b329d2; //test root
        
        // Rest are fake roots for testing
        for (uint i = 1; i < 12; i++) {
            // For testing, we'll use a simple root that allows any address
            // In production, you'd replace these with actual merkle roots
            roots[i] = keccak256(abi.encodePacked("day", i));
        }

        vm.startBroadcast();
        EXEC404 token = new EXEC404(roots);
        vm.stopBroadcast();

        return token;
    }
}