// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/components/Bonding.sol";

contract PumpBondingTest is Test {
    Bonding public bonding;
    address public user = makeAddr("user");
    function setUp() public {
        bonding = new Bonding();
        // Let's give the user much more ETH to work with
        vm.deal(user, 1_000_000_000_000_000_000_000 ether);
    }

    function testGetPrice() public {
        //console.log("\n=== Price Testing ===");
        
        // Test key supply points in 10M increments
        uint256[] memory supplyPoints = new uint256[](8);
        supplyPoints[0] = 0;                     // Start
        supplyPoints[1] = 10_000_000 ether;      // 10M (1 NFT)
        supplyPoints[2] = 100_000_000 ether;     // 100M (10 NFTs)
        supplyPoints[3] = 1_000_000_000 ether;   // 1B (100 NFTs)
        supplyPoints[4] = 2_000_000_000 ether;   // 2B (200 NFTs)
        supplyPoints[5] = 3_000_000_000 ether;   // 3B (300 NFTs)
        supplyPoints[6] = 4_000_000_000 ether;   // 4B (400 NFTs)
        supplyPoints[7] = 4_440_000_000 ether;   // 4.44B (444 NFTs)

        for(uint i = 0; i < supplyPoints.length; i++) {
            uint256 price = bonding.getPrice(supplyPoints[i]);
            console.log("Supply:", supplyPoints[i] / 1e18, "tokens");
            console.log("NFTs:", supplyPoints[i] / (10_000_000 ether));
            console.log("Price per 10M:", price / 1e18, "ETH");
            console.log("Price in USD:", (price * 2500) / 1e18, "USD");
            console.log("");
        }
    }

    function testCalculateCost() public {
        console.log("\n=== Cost Testing ===");
        
        // Test buying in 10M token increments from different starting points
        uint256[] memory amounts = new uint256[](6);
        amounts[0] = 100_000_000 ether;      // 10 NFTs (100M)
        amounts[1] = 500_000_000 ether;      // 50 NFTs (500M)
        amounts[2] = 1_000_000_000 ether;    // 100 NFTs (1B)
        amounts[3] = 1_000_000_000 ether;    // 100 NFTs (1B)
        amounts[4] = 1_000_000_000 ether;    // 100 NFTs (1B)
        amounts[5] = 840_000_000 ether;      // 84 NFTs (840M) to reach 4.44B

        uint256 currentSupply = 0;
        uint256 totalRaised = 0;  // Track total ETH raised

        for(uint i = 0; i < amounts.length; i++) {
            require(currentSupply + amounts[i] <= 4_440_000_000 ether, "Exceeds max supply");
            
            uint256 cost = bonding.calculateCost(amounts[i]);
            uint256 numNFTs = amounts[i] / (10_000_000 ether);
            
            totalRaised += cost;  // Add to running total
            
            console.log("=== Purchase", i + 1, "===");
            console.log("Current Supply: %s B tokens", currentSupply / 1e27);
            console.log("Purchase Amount: %s B tokens", amounts[i] / 1e27);
            console.log("NFTs Being Bought:", numNFTs);
            console.log("Total Cost: %s ETH", cost / 1e18);
            console.log("Cost in USD: %s USD", (cost * 2500) / 1e18);
            
            uint256 startPrice = bonding.getPrice(currentSupply);
            uint256 endPrice = bonding.getPrice(currentSupply + amounts[i]);
            console.log("Price at Start: %s ETH per NFT", startPrice / 1e18);
            console.log("Price at End: %s ETH per NFT", endPrice / 1e18);
            console.log("Price Increase: %s%%", ((endPrice - startPrice) * 100) / startPrice);
            console.log("");

            currentSupply += amounts[i];
            
            vm.deal(address(this), cost);
            bonding.buy{value: cost}(amounts[i], type(uint256).max);
        }

        console.log("=== Final Stats ===");
        console.log("Final Supply: %s B tokens", currentSupply / 1e27);
        console.log("Total ETH Raised: %s ETH", totalRaised / 1e18);
        console.log("Total USD Raised: %s USD", (totalRaised * 2500) / 1e18);
        console.log("Average Cost per NFT: %s ETH", (totalRaised / 444) / 1e18);
    }

    function testBondingCurveMetrics() public {
        console.log("\n=== Sequential Purchase Testing ===");
        
        uint256[] memory purchases = new uint256[](5);
        purchases[0] = 440_000_000 ether;    // First 440 NFTs
        purchases[1] = 1_000_000_000 ether;  // Next 1000 NFTs
        purchases[2] = 1_000_000_000 ether;  // Next 1000 NFTs
        purchases[3] = 1_000_000_000 ether;  // Next 1000 NFTs
        purchases[4] = 1_000_000_000 ether;  // Final 1000 NFTs

        uint256 totalRaised = 0;
        uint256 currentSupply = 0;

        for(uint i = 0; i < purchases.length; i++) {
            uint256 cost = bonding.calculateCost(purchases[i]);
            totalRaised += cost;
            currentSupply += purchases[i];
            
            console.log("Purchase", i + 1);
            console.log("Amount:", purchases[i] / 1e18, "tokens");
            console.log("NFTs:", purchases[i] / (1_000_000 ether));
            console.log("Cost:", cost / 1e18, "ETH");
            console.log("Total Supply:", currentSupply / 1e18);
            console.log("Total NFTs:", currentSupply / (1_000_000 ether));
            console.log("Total Raised:", totalRaised / 1e18, "ETH");
            console.log("Total Raised USD:", (totalRaised * 2500) / 1e18, "USD");
            console.log("");

            vm.deal(address(this), cost);
            bonding.buy{value: cost}(purchases[i], type(uint256).max);
        }
    }

    function testPriceProgression() public {
        console.log("\n=== Price Progression Analysis ===");
        
        // Test in 10M increments (1 NFT each)
        uint256 purchaseSize = 1_000_000 ether; // 10M tokens (1 NFT)
        uint256 numPurchases = 10; // Show first 10 NFTs
        console.log('first ten');
        for(uint i = 0; i < numPurchases; i++) {
            uint256 currentSupply = i * purchaseSize;
            uint256 price = bonding.getPrice(currentSupply);
            uint256 nextPrice = bonding.getPrice(currentSupply + purchaseSize);
            
            console.log("NFT #:", currentSupply / (1_000_000 ether));
            console.log("Current Price:", price , "ETH");
            console.log("Next Price:", nextPrice , "ETH");
            console.log("Price Increase:", ((nextPrice - price) * 100) / price, "%");
            console.log("USD Price:", (price * 2500) / 1e18, "USD");
            console.log("");
        }
        console.log('middle ten');
        for(uint i = 0; i < numPurchases; i++) {
            uint256 currentSupply = i * purchaseSize + 2_220_000_000 ether;
            uint256 price = bonding.getPrice(currentSupply);
            uint256 nextPrice = bonding.getPrice(currentSupply + purchaseSize);
            
            console.log("NFT #:", currentSupply / (1_000_000 ether));
            console.log("Current Price:", price , "ETH");
            console.log("Next Price:", nextPrice , "ETH");
            console.log("Price Increase:", ((nextPrice - price) * 100) / price, "%");
            console.log("USD Price:", (price * 2500) / 1e18, "USD");
            console.log("");
        }
        console.log('last ten');
        for(uint i = 0; i < numPurchases; i++) {
            uint256 currentSupply = i * purchaseSize + 4_430_000_000 ether;
            uint256 price = bonding.getPrice(currentSupply);
            uint256 nextPrice = bonding.getPrice(currentSupply + purchaseSize);
            
            console.log("NFT #:", currentSupply / (1_000_000 ether));
            console.log("Current Price:", price , "ETH");
            console.log("Next Price:", nextPrice , "ETH");
            console.log("Price Increase:", ((nextPrice - price) * 100) / price, "%");
            console.log("USD Price:", (price * 2500) / 1e18, "USD");
            console.log("");
        }
    }

    function testBuy() public {
        uint256 amount = 10_000_000 ether; // 10M tokens
        
        // Log the calculation steps
        console.log("Attempting to buy tokens:", amount / 1 ether);
        
        uint256 startSupply = bonding.totalSupply();
        console.log("Starting supply:", startSupply / 1 ether);
        
        uint256 endSupply = startSupply + amount;
        console.log("End supply:", endSupply / 1 ether);
        
        uint256 cost = bonding.calculateCost(amount);
        console.log("Calculated cost in ETH:", cost);
        
        uint256 maxCost = cost * 101 / 100; // Allow 1% slippage
        console.log("Max cost with slippage in ETH:", maxCost);
        
        vm.prank(user);
        bonding.buy{value: maxCost}(amount, maxCost);
        
        assertEq(bonding.balances(user), amount);
        assertEq(bonding.totalSupply(), amount);
        assertEq(bonding.reserve(), cost);
        
        // Log final state
        console.log("Final balance of user:", bonding.balances(user) / 1 ether);
        console.log("Final total supply:", bonding.totalSupply() / 1 ether);
        console.log("Final reserve:", bonding.reserve() / 1 ether);
    }

    function testSell() public {
        // First buy some tokens
        uint256 amount = 10_000_000 ether;
        uint256 buyCost = bonding.calculateCost(amount);
        uint256 maxCost = buyCost * 101 / 100;
        
        vm.startPrank(user);
        bonding.buy{value: maxCost}(amount, maxCost);
        
        // Now sell them
        uint256 expectedRefund = bonding.calculateCost(amount);
        uint256 minRefund = expectedRefund * 99 / 100; // Allow 1% slippage
        
        uint256 balanceBefore = user.balance;
        bonding.sell(amount, minRefund);
        uint256 balanceAfter = user.balance;
        
        assertEq(bonding.balances(user), 0);
        assertEq(bonding.totalSupply(), 0);
        assert(balanceAfter > balanceBefore);
        vm.stopPrank();
    }

    function testSlippageProtection() public {
        uint256 amount = 10_000_000 ether;
        uint256 cost = bonding.calculateCost(amount);
        uint256 maxCost = cost * 99 / 100; // Set max cost too low
        
        vm.prank(user);
        vm.expectRevert("Slippage exceeded");
        bonding.buy{value: cost}(amount, maxCost);
    }
}