// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "src/EXEC404.sol";
import "script/Deploy.s.sol";
import "test/EXEC404.t.sol";

contract DressRehearsalTest is EXEC404Test {

    function setUp() public override {
        // Setup whitelist and test user ETH balances
        address ;
        for (uint256 day = 0; day <= 12; day++) {
            for (uint256 userIndex = 0; userIndex <= day && userIndex < testUsers.length; userIndex++) {
                whitelistsByDay[day][testUsers[userIndex]] = true;
            }
        }

        for (uint256 i = 0; i < testUsers.length; i++) {
            vm.deal(testUsers[i], 10000 ether);
        }

        // Generate Merkle roots
        merkleRoots = generateMerkleRoots();

        // ✅ Deploy via real script
        DeployScript deployer = new DeployScript();

        vm.startPrank(0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6);
        token = deployer.internalDeploy(); // This executes your full deploy script logic
        token.configure(
            "https://monygroupmint.nyc3.digitaloceanspaces.com/cultexecbadges/public/metadata/",
            "https://ms2.fun/EXEC404/unrevealed.json",
            true
        );
        vm.stopPrank();
    }

    function setupLiquidityPool() internal override returns (uint256 lpTokens) {
        uint256 dailyAmount = token.MAX_SUPPLY() / 20;

        // Simulate buys on different days using Dress Rehearsal addresses
        console.log("Starting Dress Rehearsal buys");
        for (uint256 day = 0; day < 11; day++) {
            console.log("We got liquidityPair?", token.liquidityPair());
            vm.warp(token.LAUNCH_TIME() + (day * 1 days));

            address buyer = testUsers[day];
            bytes32[] memory proof = generateProof(day, buyer);

            uint256 cost = token.calculateCost(dailyAmount);
            vm.deal(buyer, cost + 0.1 ether); // give them a bit more just in case

            vm.startPrank(buyer);
            token.buyBonding{value: cost}(
                dailyAmount,
                cost,
                false,
                proof,
                string(abi.encodePacked("Dress day ", vm.toString(day)))
            );
            vm.stopPrank();
        }

        // Fast forward to liquidity deployment time
        vm.warp(token.LAUNCH_TIME() + 13 days);
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);

        uint256 contractETH = address(token).balance;
        uint256 contractTokens = token.balanceOf(address(token));

        console.log("\n=== Pre-Liquidity ===");
        console.log("Contract ETH:", contractETH);
        console.log("Contract Tokens:", contractTokens);

        (uint256 tokensUsed, uint256 ethUsed, uint256 lp) = token.deployLiquidity();
        lpTokens = lp;

        console.log("\n=== Liquidity Deployed ===");
        console.log("Tokens:", tokensUsed);
        console.log("ETH:", ethUsed);
        console.log("LP Tokens:", lpTokens);
        console.log("Liquidity Pair Token Bal:", token.balanceOf(token.liquidityPair()));

        vm.stopPrank();
    }


    function testDressRehearsal() public {

        assertEq(token.name(), "CULT EXECUTIVES");
        assertEq(token.symbol(), "EXEC");

        // LP setup and market test
        testMarket(); // simulate ongoing trading as normal
    }
}