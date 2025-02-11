// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDN404.sol"; // We'll need to interface with DN404

contract DN404BondingCurve is ReentrancyGuard, Ownable {
    IDN404 public immutable token;
    
    // Price constants (can be adjusted based on requirements)
    uint256 public constant INITIAL_PRICE = 0.001 ether;
    uint256 public constant PRICE_INCREMENT = 0.0001 ether;
    
    constructor(address _token) Ownable(msg.sender) {
        token = IDN404(_token);
    }
    
    function calculatePrice(uint256 amount) public view returns (uint256) {
        // Basic linear bonding curve: price = initial_price + (current_supply * price_increment)
        uint256 currentSupply = token.totalSupply();
        return INITIAL_PRICE + (currentSupply * PRICE_INCREMENT);
    }
    
    function buy(uint256 amount) external payable nonReentrant {
        uint256 price = calculatePrice(amount);
        uint256 totalCost = price * amount;
        require(msg.value >= totalCost, "Insufficient payment");
        
        // Transfer tokens to buyer
        token.transfer(msg.sender, amount);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            (bool success, ) = msg.sender.call{value: msg.value - totalCost}("");
            require(success, "Refund failed");
        }
    }
    
    function sell(uint256 amount) external nonReentrant {
        uint256 price = calculatePrice(amount);
        uint256 payment = price * amount;
        
        // Transfer tokens from seller
        token.transferFrom(msg.sender, address(this), amount);
        
        // Send ETH to seller
        (bool success, ) = msg.sender.call{value: payment}("");
        require(success, "Payment failed");
    }
}