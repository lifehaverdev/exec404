// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import  "forge-std/Script.sol";
import "forge-std/console.sol";
import {SequentialMerkleWhitelist} from "../../src/components/SequentialMerkleWhitelist.sol";

contract DeploySequentialMerkleWhitelist is Script {
    // Test addresses to demonstrate the concept
    address[5] internal testAddresses = [
        address(0x1),
        address(0x2),
        address(0x3),
        address(0x4),
        address(0x5)
    ];

    function generateMockTierRoot(uint256 tierIndex) internal pure returns (bytes32) {
        // In production, this would be replaced with actual merkle root generation
        // based on token holder snapshots for each tier
        return keccak256(abi.encodePacked(tierIndex, "TIER_ROOT"));
    }

    function generateTierRoots() internal pure returns (bytes32[] memory) {
        bytes32[] memory roots = new bytes32[](12);
        
        // Generate a unique root for each tier
        for(uint256 i = 0; i < 12; i++) {
            roots[i] = generateMockTierRoot(i);
        }

        return roots;
    }

    function run() external returns (SequentialMerkleWhitelist) {
        bytes32[] memory tierRoots = generateTierRoots();
        
        vm.startBroadcast();
        SequentialMerkleWhitelist whitelist = new SequentialMerkleWhitelist(tierRoots);
        vm.stopBroadcast();
        
        // Log the roots for verification
        for(uint256 i = 0; i < tierRoots.length; i++) {
            console.log("Tier", i, "Root:", vm.toString(tierRoots[i]));
        }
        
        return whitelist;
    }
}