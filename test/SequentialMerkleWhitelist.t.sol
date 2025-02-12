// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SequentialMerkleWhitelist} from "../src/SequentialMerkleWhitelist.sol";

contract SequentialMerkleWhitelistTest is Test {
    SequentialMerkleWhitelist public whitelist;
    
    // Test addresses
    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    
    // Test merkle values
    bytes32[] public tierRoots;
    bytes32[] public aliceProof;
    
    function setUp() public {
        // Create sample roots for each tier (12 tiers)
        tierRoots = new bytes32[](12);
        for(uint i = 0; i < 12; i++) {
            // For testing, we'll use simple roots
            // In production, these would be actual merkle roots
            tierRoots[i] = keccak256(abi.encodePacked(i));
        }

        // Create a simple proof for testing
        bytes32 aliceLeaf = keccak256(abi.encodePacked(ALICE));
        bytes32 bobLeaf = keccak256(abi.encodePacked(BOB));
        aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;
        
        whitelist = new SequentialMerkleWhitelist(tierRoots);
    }

    function testInitialState() public {
        assertEq(whitelist.currentRoot(), tierRoots[0]);
        assertEq(whitelist.currentTierIndex(), 0);
        assertEq(whitelist.nextSequenceTime(), block.timestamp + 1 days);
    }

    function testSequenceAdvancement() public {
        // Try to advance too early
        vm.expectRevert("Too early for next sequence");
        whitelist.advanceSequence();
        
        // Move time forward
        vm.warp(block.timestamp + 1 days);
        
        // Advance sequence
        whitelist.advanceSequence();
        
        // Check new state
        assertEq(whitelist.currentTierIndex(), 1);
        assertEq(whitelist.currentRoot(), tierRoots[1]);
    }

    function testCompleteCycle() public {
        for(uint i = 0; i < 11; i++) {
            vm.warp(block.timestamp + 1 days);
            whitelist.advanceSequence();
            assertEq(whitelist.currentTierIndex(), i + 1);
        }
        
        // Should not be able to advance past final tier
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("All tiers completed");
        whitelist.advanceSequence();
    }

    function testTierThresholds() public {
        // Test first tier (1%)
        assertEq(whitelist.getCurrentTierThreshold(), 0);
        
        // Advance to second tier (2%)
        vm.warp(block.timestamp + 1 days);
        whitelist.advanceSequence();
        assertEq(whitelist.getCurrentTierThreshold(), 1);
    }
}