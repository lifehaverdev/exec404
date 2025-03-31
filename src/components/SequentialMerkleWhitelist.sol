// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";

contract SequentialMerkleWhitelist {
    // Array of merkle roots for each tier
    bytes32[] public tierRoots;
    
    // Current tier index
    uint256 public currentTierIndex;
    
    // Timestamp for the next sequence update
    uint256 public nextSequenceTime;
    
    // Time interval between sequences
    uint256 public constant SEQUENCE_INTERVAL = 1 days;


    event SequenceUpdated(uint256 indexed tierIndex, bytes32 root, uint256 nextSequenceTime);
    event WhitelistInitialized(bytes32[] roots);

    constructor(bytes32[] memory _tierRoots) {
        require(_tierRoots.length == 12, "Invalid roots length");
        tierRoots = _tierRoots;
        nextSequenceTime = block.timestamp + SEQUENCE_INTERVAL;
        emit WhitelistInitialized(_tierRoots);
    }

    function currentRoot() public view returns (bytes32) {
        return tierRoots[currentTierIndex];
    }

    function isWhitelisted(
        bytes32[] calldata proof,
        address account
    ) public view returns (bool) {
        return MerkleProofLib.verify(
            proof,
            currentRoot(),
            keccak256(abi.encodePacked(account))
        );
    }

    function advanceSequence() external {
        require(block.timestamp >= nextSequenceTime, "Too early for next sequence");
        require(currentTierIndex < tierRoots.length - 1, "All tiers completed");
        
        currentTierIndex++;
        nextSequenceTime = block.timestamp + SEQUENCE_INTERVAL;
        
        emit SequenceUpdated(
            currentTierIndex,
            currentRoot(),
            nextSequenceTime
        );
    }

    function getCurrentTierThreshold() external view returns (uint256) {
        return currentTierIndex;
    }

    function getRemainingTiers() external view returns (uint256) {
        return tierRoots.length - currentTierIndex - 1;
    }

    // Check if whitelist period is complete
    function isWhitelistComplete() public view returns (bool) {
        return currentTierIndex >= tierRoots.length - 1;
    }

    modifier onlyWhitelisted(bytes32[] calldata proof) {
        // If whitelist period is over, allow all
        if (!isWhitelistComplete()) {
            // For convenience, allow empty proof to signal no attempt at verification
            if (proof.length == 0) {
                require(false, "Whitelist still active");
            }
            require(isWhitelisted(proof, msg.sender), "Not whitelisted");
        }
        _;
    }

    // Example usage:
    function protectedFunction(bytes32[] calldata proof) 
        external 
        onlyWhitelisted(proof) 
        returns (bool) 
    {
        return true;
    }

    // Another example
    function anotherProtectedFunction(bytes32[] calldata proof, uint256 someParam) 
        external 
        onlyWhitelisted(proof) 
    {
        // Function logic here
    }
}