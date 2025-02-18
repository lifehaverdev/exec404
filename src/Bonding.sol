// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";

contract Bonding is Test {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    uint256 public reserve;

    uint256 public constant INITIAL_PRICE = 0.025 ether;   // Base price
    uint256 public constant MAX_SUPPLY = 4_440_000_000 ether; // 4.44B tokens

    function getPrice(uint256 supply) public view returns (uint256) {
        // Scale down supply by 1e24 for calculations assuming 10M tokens at a time
        uint256 scaledSupply = supply / 1e25;
        
        // Base price: 0.025 ether
        uint256 basePrice = INITIAL_PRICE;
        
        // Calculate polynomial terms using 4 gwei (4e9) to represent 4e-9
        // Convert scaledSupply to WAD format for mulWad
        uint256 scaledSupplyWad = scaledSupply * 1e18;
        
        // 4e-9s^3
        uint256 cubicTerm = FixedPointMathLib.mulWad(
            4 gwei,
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                scaledSupplyWad
            )
        );
        
        // 4e-9s^2
        uint256 quadraticTerm = FixedPointMathLib.mulWad(
            4 gwei,
            FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad)
        );
        
        // 4e-9s
        uint256 linearTerm = FixedPointMathLib.mulWad(4 gwei, scaledSupplyWad);
        
        uint256 finalPrice = basePrice + cubicTerm + quadraticTerm + linearTerm;
        //console.log("Final Price:", finalPrice);
        
        return finalPrice;
    }

    function calculateIntegral(uint256 lowerBound, uint256 upperBound) internal pure returns (uint256) {
        require(upperBound >= lowerBound, "Invalid bounds");
        
        // Calculate integral from 0 to upperBound and subtract integral from 0 to lowerBound
        uint256 upperIntegral = _calculateIntegralFromZero(upperBound);
        uint256 lowerIntegral = _calculateIntegralFromZero(lowerBound);
        
        return upperIntegral - lowerIntegral;
    }

    function _calculateIntegralFromZero(uint256 supply) internal pure returns (uint256) {
        // Scale down supply by 1e25 to match getPrice scaling
        uint256 scaledSupply = supply / 1e25;
        uint256 scaledSupplyWad = scaledSupply * 1e18;
        
        // Integrate base price: 0.025x
        uint256 basePart = (INITIAL_PRICE * supply) / 1e25;
        
        // Integrate 4e-9x^3 -> (4e-9/4)x^4
        uint256 quarticTerm = FixedPointMathLib.mulWad(
            1 gwei, // 4e9/4 = 1e9
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(
                    FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                    scaledSupplyWad
                ),
                scaledSupplyWad
            )
        );
        
        // Integrate 4e-9x^2 -> (4e-9/3)x^3
        uint256 cubicTerm = FixedPointMathLib.mulWad(
            FixedPointMathLib.mulDiv(4 gwei, 3, 1e18),  // 4e9/3
            FixedPointMathLib.mulWad(
                FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad),
                scaledSupplyWad
            )
        );
        
        // Integrate 4e-9x -> (4e-9/2)x^2
        uint256 quadraticTerm = FixedPointMathLib.mulWad(
            2 gwei,  // 4e9/2 = 2e9
            FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad)
        );
        
        return basePart + quarticTerm + cubicTerm + quadraticTerm;
    }

    function calculateCost(uint256 amount) public view returns (uint256) {
        uint256 startSupply = totalSupply;
        uint256 endSupply = totalSupply + amount;
        
        // Calculate cost using integral difference
        return calculateIntegral(startSupply, endSupply);
    }

    function buy(uint256 amount, uint256 maxCost) external payable {
        require(totalSupply + amount <= MAX_SUPPLY, "Exceeds max supply");

        uint256 totalCost = calculateCost(amount);
        require(totalCost <= maxCost, "Slippage exceeded");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        balances[msg.sender] += amount;
        totalSupply += amount;
        reserve += totalCost;

        // Refund excess payment
        if (msg.value > totalCost) {
            (bool success, ) = msg.sender.call{value: msg.value - totalCost}("");
            require(success, "Refund failed");
        }
    }

    function sell(uint256 amount, uint256 minRefund) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        uint256 endSupply = totalSupply - amount;
        uint256 refund = calculateIntegral(endSupply, totalSupply);

        require(refund >= minRefund, "Slippage exceeded");
        require(reserve >= refund, "Insufficient reserve");

        balances[msg.sender] -= amount;
        totalSupply -= amount;
        reserve -= refund;

        (bool success, ) = msg.sender.call{value: refund}("");
        require(success, "Refund failed");
    }

    receive() external payable {}
}