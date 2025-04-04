// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SEPEXEC404.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";
import "../src/mocks/MockCULT.sol";

// Custom interfaces for V3 interactions
interface IPositionManager {
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IUniswapV3Pool {
    //function token0() external view returns (address);
    //function token1() external view returns (address);
    //function fee() external view returns (uint24);
    //function positions(uint256 tokenId) external view returns (uint128 liquidity, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128, uint128 tokensOwed0, uint128 tokensOwed1);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}


interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Router002 {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}


contract SEPEXEC404Test is Test {
    // Sepolia addresses
    address constant ROUTER = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;
    address constant V3ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant POSITIONMANAGER = 0x1238536071E1c677A632429e3655c799b22cDA52;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant FACTORY3 = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    
    // Test addresses for merkle tree testing
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");
    address emma = makeAddr("emma");
    address frank = makeAddr("frank");
    address grace = makeAddr("grace");
    address henry = makeAddr("henry");
    address ivy = makeAddr("ivy");
    address jack = makeAddr("jack");
    address kelly = makeAddr("kelly");
    address larry = makeAddr("larry");

    // Optional: Create an array for easier iteration
    address[] internal testUsers;
    
    
    // Contract instances
    SEPEXEC404 public token;
    DN404Mirror public mirror;
    MockCULT public mockCult;
    address public colaBottles = 0x73eB323474B0597d3E20fBC4084D0E93f133a1ED;
    
    // Merkle tree roots
    bytes32[] public merkleRoots;
    mapping(uint256 => mapping(address => bool)) public whitelistsByDay;
    
    function setUp() public {
        // Fork Sepolia
        vm.createSelectFork(vm.envString("SEP_RPC"));
        
        // Mark V3 contracts as persistent
        vm.makePersistent(ROUTER);  // V2 Router
        vm.makePersistent(0xE592427A0AEce92De3Edee1F18E0157C05861564);  // V3 Router
        vm.makePersistent(0x10D14F3Df52A22134444Bbd9c62DBaB593C58d22);  // V3 Factory
        
        testUsers = [alice, bob, carol, dave, emma, frank, grace, henry, ivy, jack, kelly, larry];
        
        // Deploy mock CULT
        mockCult = new MockCULT();
        
        // Create initial V3 liquidity pool for mock CULT/WETH
        IPositionManager posManager = IPositionManager(POSITIONMANAGER);
        
        // Mint some CULT tokens to alice for liquidity
        mockCult.transfer(alice, 1000000 * 1e18);
        
        vm.startPrank(alice);
        // Approve CULT tokens for position manager
        mockCult.approve(POSITIONMANAGER, type(uint256).max);
        
        // Create and initialize the pool
        posManager.createAndInitializePoolIfNecessary(
            address(mockCult),
            WETH,
            10000, // 1% fee tier
            uint160(1 << 96) // Initial sqrtPriceX96
        );
        
        // Add initial liquidity
        IPositionManager.MintParams memory params = IPositionManager.MintParams({
            token0: address(mockCult),
            token1: WETH,
            fee: 10000,
            tickLower: -50000,  // Reduced from -887220
            tickUpper: 50000,   // Reduced from 887220
            amount0Desired: 1000000 * 1e18,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: alice,
            deadline: block.timestamp + 1000
        });
        
        // Add liquidity
        vm.deal(alice, 10 ether); // Give alice some ETH for liquidity
        posManager.mint{value: 1 ether}(params);
        vm.stopPrank();
        
        // Set up whitelists for each day (0-12) procedurally
        for (uint256 day = 0; day <= 12; day++) {
            // Each day includes users from index 0 up to the current day (inclusive)
            for (uint256 userIndex = 0; userIndex <= day && userIndex < testUsers.length; userIndex++) {
                whitelistsByDay[day][testUsers[userIndex]] = true;
            }
        }

        // Generate merkle roots properly
        merkleRoots = generateMerkleRoots();
        
        // Deploy SEPEXEC404 as the real operator
        address OPERATOR = 0x6A0a993cc824457734EC7Cac50744a34EcAf34D4;
        vm.startPrank(OPERATOR);
        token = new SEPEXEC404(
            merkleRoots,
            address(mockCult),
            colaBottles // Test cola bottles
        );
        
        token.configure(
            "https://api.example.com/token/",
            "https://api.example.com/unrevealed.json",
            true
        );
        vm.stopPrank();
        
        // Setup initial balances
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    function testConstructorAndImmutables() public {
        // Verify immutable values are set correctly
        assertEq(address(token.CULT()), address(mockCult));
        // private variables now
        //assertEq(address(token.OPERATOR_NFT()), colaBottles);
        //assertEq(address(token.router()), ROUTER);
        //assertEq(address(token.router3()), V3ROUTER);
        //assertEq(address(token.positionManager()), POSITIONMANAGER);
        //assertEq(token.weth(), WETH);
        //assertEq(token.factory3(), FACTORY3);
    }

    function testAssemblyFunctions() public {
        // Test _erc20Approve
        vm.startPrank(alice);
        token.buyBonding{value: 1 ether}(1000 ether, 1 ether, false, generateProof(0, alice), "");
        
        // Test approval through assembly
        uint256 approvalAmount = 100 ether;
        vm.expectCall(
            address(token),
            abi.encodeWithSignature("approve(address,uint256)", ROUTER, approvalAmount)
        );
        token.approve(ROUTER, approvalAmount);
        
        // Test balanceOf through assembly
        uint256 balance = token.balanceOf(alice);
        assertGt(balance, 0, "Balance should be greater than 0");
        
        vm.stopPrank();
    }

    function testBondingCurve() public {
        vm.startPrank(alice);
        
        // Test buying - should get 1M free tokens plus purchased amount
        bytes32[] memory proof = generateProof(0, alice);
        
        // Calculate the cost first
        uint256 buyAmount = 1000000 ether;
        uint256 totalCost = token.calculateCost(buyAmount);
        
        // Buy with the calculated cost as maxCost
        token.buyBonding{value: totalCost}(
            buyAmount, 
            totalCost,  // Pass the calculated cost as maxCost
            false, 
            proof, 
            "Test message"
        );
        
        // Verify total balance (free + purchased)
        uint256 totalBalance = token.balanceOf(alice);
        assertGt(totalBalance, 1000000 ether, "Should have free tokens plus purchased amount");
        
        // Calculate the purchased amount (total - freebie)
        uint256 purchasedAmount = totalBalance - 1000000 ether;
        
        // Calculate expected refund with 4% tax, maintaining 18 decimals
        uint256 expectedRefund = token.calculateRefund(purchasedAmount);
        uint256 minRefund = (expectedRefund * 96 * 1e18) / (100 * 1e18);
        console2.log("Expected refund:", expectedRefund);
        console2.log("Min refund (with tax):", minRefund);
        
        // Test selling only the purchased amount, not the freebie
        token.sellBonding(purchasedAmount, minRefund, proof, "Test sell message");
        
        // Verify remaining balance is exactly the freebie amount
        assertEq(token.balanceOf(alice), 1000000 ether, "Should only have freebie tokens left");
        
        vm.stopPrank();
    }

    function generateProof(uint256 day, address user) internal view returns (bytes32[] memory) {
        require(whitelistsByDay[day][user], "User not white");
        
        // Count whitelisted addresses for this day
        uint256 leafCount = 0;
        for (uint256 i = 0; i < testUsers.length; i++) {
            if (whitelistsByDay[day][testUsers[i]]) {
                leafCount++;
            }
        }
        
        // Create and fill leaves array
        bytes32[] memory leaves = new bytes32[](leafCount);
        uint256 leafIndex = 0;
        for (uint256 i = 0; i < testUsers.length; i++) {
            if (whitelistsByDay[day][testUsers[i]]) {
                leaves[leafIndex] = keccak256(abi.encodePacked(testUsers[i]));
                leafIndex++;
            }
        }
        
        // Sort leaves
        sortBytes32Array(leaves);
        
        // Find position of user's leaf
        bytes32 userLeaf = keccak256(abi.encodePacked(user));
        uint256 userIndex;
        for (uint256 i = 0; i < leaves.length; i++) {
            if (leaves[i] == userLeaf) {
                userIndex = i;
                break;
            }
        }
        
        // Generate proof
        bytes32[] memory proof = new bytes32[](32); // Max depth
        uint256 proofLength = 0;
        uint256 index = userIndex;
        bytes32[] memory currentLevel = leaves;
        
        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);
            
            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    nextLevel[i/2] = keccak256(abi.encodePacked(
                        currentLevel[i],
                        currentLevel[i+1]
                    ));
                    
                    if (i == index || i + 1 == index) {
                        proof[proofLength++] = (i == index) 
                            ? currentLevel[i+1] 
                            : currentLevel[i];
                    }
                } else {
                    nextLevel[i/2] = currentLevel[i];
                }
            }
            
            index /= 2;
            currentLevel = nextLevel;
        }
        
        // Trim proof array to actual length
        bytes32[] memory finalProof = new bytes32[](proofLength);
        for (uint256 i = 0; i < proofLength; i++) {
            finalProof[i] = proof[i];
        }
        
        return finalProof;
    }

    // Add helper functions for merkle tree generation
    function generateMerkleRoots() internal view returns (bytes32[] memory) {
        bytes32[] memory roots = new bytes32[](12);
        
        for (uint256 day = 0; day < 12; day++) {
            // Count whitelisted addresses for this day
            uint256 leafCount = 0;
            for (uint256 i = 0; i < testUsers.length; i++) {
                if (whitelistsByDay[day][testUsers[i]]) {
                    leafCount++;
                }
            }
            
            // Create leaves array for this day
            bytes32[] memory leaves = new bytes32[](leafCount);
            uint256 leafIndex = 0;
            
            // Generate leaves for whitelisted addresses
            for (uint256 i = 0; i < testUsers.length; i++) {
                if (whitelistsByDay[day][testUsers[i]]) {
                    leaves[leafIndex] = keccak256(abi.encodePacked(testUsers[i]));
                    leafIndex++;
                }
            }
            
            // Sort leaves for consistent tree generation
            sortBytes32Array(leaves);
            
            // Generate and store root for this day
            roots[day] = generateMerkleRoot(leaves);
        }
        
        return roots;
    }

    function generateMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "No leaves");
        
        if (leaves.length == 1) {
            return leaves[0];
        }

        bytes32[] memory nextLevel = new bytes32[]((leaves.length + 1) / 2);
        
        for (uint i = 0; i < leaves.length; i += 2) {
            if (i + 1 < leaves.length) {
                nextLevel[i/2] = keccak256(abi.encodePacked(leaves[i], leaves[i+1]));
            } else {
                nextLevel[i/2] = leaves[i];
            }
        }
        
        return generateMerkleRoot(nextLevel);
    }

    function sortBytes32Array(bytes32[] memory arr) internal pure {
        for (uint i = 0; i < arr.length - 1; i++) {
            for (uint j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
                }
            }
        }
    }

    // Helper function to simulate bonding curve sales and deploy liquidity
    function setupLiquidityPool() internal returns (uint256 lpTokens) {
        // Use a more reasonable amount for Sepolia
        uint256 dailyPurchaseAmount = 100000000 ether; 
        
        // Buy tokens through bonding curve over several days
        for(uint256 day = 0; day < 5; day++) { // Reduced days for faster testing
            vm.warp(token.LAUNCH_TIME() + (day * 1 days));
            
            address buyer = testUsers[day];
            bytes32[] memory proof = generateProof(day, buyer);
            
            uint256 cost = token.calculateCost(dailyPurchaseAmount);
            vm.deal(buyer, cost);
            
            vm.startPrank(buyer);
            token.buyBonding{value: cost}(
                dailyPurchaseAmount,
                cost,
                false,
                proof,
                ''
            );
            vm.stopPrank();
        }
        
        // Deploy liquidity
        vm.warp(token.LAUNCH_TIME() + 13 days);
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        
        // Log initial state
        uint256 contractETH = address(token).balance;
        uint256 contractTokens = token.balanceOf(address(token));
        
        console.log("\nPre-Liquidity State:");
        console.log("Contract ETH Balance:", contractETH);
        console.log("Contract Token Balance:", contractTokens);
        
        // Deploy liquidity
        (uint256 tokensDeployed, uint256 ethDeployed, uint256 lp) = token.deployLiquidity();
        lpTokens = lp;
        
        console.log("\nLiquidity Deployed:");
        console.log("Tokens:", tokensDeployed);
        console.log("ETH:", ethDeployed);
        console.log("LP Tokens:", lpTokens);
        
        // Verify pool setup
        address pair = token.liquidityPair();
        console.log("Pool Token Balance:", token.balanceOf(pair));
        
        vm.stopPrank();
        return lpTokens;
    }

    function testLiquidityPool() public {
        uint256 initialLpTokens = setupLiquidityPool();
    }

    function testMarketSep() public {
        uint256 initialLpTokens = setupLiquidityPool();
        
        // Essential pool setup
        address cultPool = token.cultPool();
        IUniswapV3Pool cultV3Pool = IUniswapV3Pool(cultPool);
        
        // Create traders
        address[] memory traders = new address[](20);
        for(uint256 i = 0; i < 20; i++) {
            traders[i] = makeAddr(string.concat("trader", vm.toString(i)));
            vm.deal(traders[i], 100 ether);
        }
        
        // Tracking metrics (reduced to essential ones)
        uint256 totalVolume;
        uint256 totalTaxes;
        
        // Simulate trades
        for(uint256 i = 0; i < 100; i++) {
            vm.roll(block.number + i);
            vm.warp(block.timestamp + 15*i);
            console.log("\nContract state:", block.number);
            console.log("contract eth balance",address(token).balance);
            console.log("contract cult balance",IERC20(token.CULT()).balanceOf(address(token)));
            console.log("Contract token balance", token.balanceOf(address(token)));
            (,,,,,,,uint128 liquidity,,,,) = IPositionManager(address(POSITIONMANAGER)).positions(token.cultV3Position());
            console.log("Contract CULT-ETH V3 Position Liquidity:", liquidity);
            
            if(i % 2 == 0) { // Buy
                address trader = traders[i % traders.length];
                vm.startPrank(trader);
                
                address[] memory path = new address[](2);
                path[0] = WETH;
                path[1] = address(token);
                
                uint256 ethBefore = address(token).balance;
                
                try IUniswapV2Router002(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
                    0,
                    path,
                    trader,
                    block.timestamp
                ) {
                    totalVolume += 1 ether;
                    if (address(token).balance > ethBefore) {
                        totalTaxes += address(token).balance - ethBefore;
                    }
                } catch Error(string memory reason) {
                    console.log("\nBuy failed:", reason);
                }
                
                vm.stopPrank();
            } else { // Sell
                address seller = testUsers[i % testUsers.length];
                vm.startPrank(seller);
                
                uint256 tokenBalance = token.balanceOf(seller);
                if(tokenBalance > 0) {
                    uint256 sellAmount = tokenBalance / 4;
                    uint256 ethBefore = address(token).balance;
                    
                    address[] memory path = new address[](2);
                    path[0] = address(token);
                    path[1] = WETH;
                    
                    token.approve(ROUTER, sellAmount);
                    try IUniswapV2Router002(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
                        sellAmount,
                        0,
                        path,
                        seller,
                        block.timestamp
                    ) {
                        totalVolume += sellAmount;
                        if (address(token).balance > ethBefore) {
                            totalTaxes += address(token).balance - ethBefore;
                        }
                    } catch Error(string memory reason) {
                        console.log("\nSell failed:", reason);
                    }
                }
                vm.stopPrank();
            }
        }

        // Final metrics
        console.log("\n=== Trading Summary ===");
        console.log("Total Volume (ETH):", totalVolume / 1 ether);
        console.log("Total Taxes (ETH):", totalTaxes);
        
        // Basic assertions
        assertTrue(totalVolume > 0, "Should have non-zero volume");
        assertTrue(totalTaxes > 0, "Should have collected taxes");

        // Final state
        console.log("\n=== Final Balances ===");
        console.log("EXEC Balance:", token.balanceOf(address(token)));
        console.log("ETH Balance:", address(token).balance);
        console.log("CULT Balance:", IERC20(token.CULT()).balanceOf(address(token)));

            // Get V3 position details
        uint256 positionId = token.cultV3Position();
        if (positionId > 0) {
            (,,,,,,,uint128 liquidity,,,,) = IPositionManager(address(POSITIONMANAGER)).positions(positionId);
            console.log("CULT-ETH V3 Position Liquidity:", liquidity);
        } else {
            console.log("No V3 Position found");
        }
    }

    function testCollectV3FeesSep() public {
        // First run market simulation to generate fees
        testMarketSep(); // This generates real trading volume and fees

        // Get the position ID and manager
        uint256 positionId = token.cultV3Position();
        IPositionManager posManager = IPositionManager(address(POSITIONMANAGER));
        
        // Get initial position state
        (,,,,,,,,,, uint128 initialTokensOwed0, uint128 initialTokensOwed1) = 
            posManager.positions(positionId);
        
        console.log("\nBefore Collection:");
        console.log("Tokens Owed 0:", initialTokensOwed0);
        console.log("Tokens Owed 1:", initialTokensOwed1);

        // Prank as the NFT owner
        vm.startPrank(0x6A0a993cc824457734EC7Cac50744a34EcAf34D4);

        // Collect the fees
        (uint256 collected0, uint256 collected1) = token.collectV3Fees(
            type(uint128).max, // Collect all available token0 fees
            type(uint128).max  // Collect all available token1 fees
        );
        vm.stopPrank();

        // Get final position state
        (,,,,,,,,,, uint128 finalTokensOwed0, uint128 finalTokensOwed1) = 
            posManager.positions(positionId);
        
        console.log("\nAfter Collection:");
        console.log("Collected token0:", collected0);
        console.log("Collected token1:", collected1);
        console.log("Remaining Owed 0:", finalTokensOwed0);
        console.log("Remaining Owed 1:", finalTokensOwed1);

        // Assertions
        assertTrue(collected0 > 0 || collected1 > 0, "Should collect some fees");
        assertEq(finalTokensOwed0, 0, "Should collect all token0 fees");
        assertEq(finalTokensOwed1, 0, "Should collect all token1 fees");
    }

    function testGasBenchmarkSep() public {
        uint256 initialLpTokens = setupLiquidityPool();
        
        // Create traders
        address[] memory traders = new address[](20);
        for(uint256 i = 0; i < traders.length; i++) {
            traders[i] = makeAddr(string.concat("trader", vm.toString(i)));
            vm.deal(traders[i], 100 ether);
        }

        // Track unique gas values and their counts
        uint256[] memory uniqueGasValues = new uint256[](10);  // Store up to 10 unique values
        uint256[] memory gasValueCounts = new uint256[](10);
        uint256 uniqueValuesFound = 0;

        console.log("\n===simulating trading===");
        
        // Simulate trades with block spacing
        for(uint256 i = 0; i < 100; i++) {
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 15);
            
            bool isBuy = i % 2 == 0;
            uint256 traderIndex = i % traders.length;
            address trader = traders[traderIndex];
            
            vm.startPrank(trader);
            uint256 gasStart = gasleft();
            
            if(isBuy) {
                address[] memory path = new address[](2);
                path[0] = WETH;
                path[1] = address(token);
                
                try IUniswapV2Router002(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
                    0,
                    path,
                    trader,
                    block.timestamp
                ) {
                    uint256 gasUsed = gasStart - gasleft();
                    
                    // Check if this is a new gas value
                    bool isNewValue = true;
                    for(uint256 j = 0; j < uniqueValuesFound; j++) {
                        if(gasUsed == uniqueGasValues[j]) {
                            gasValueCounts[j]++;
                            isNewValue = false;
                            break;
                        }
                    }
                    
                    if(isNewValue && uniqueValuesFound < 10) {
                        uniqueGasValues[uniqueValuesFound] = gasUsed;
                        gasValueCounts[uniqueValuesFound] = 1;
                        uniqueValuesFound++;
                        console.log("New gas value found:", gasUsed);
                    }
                    
                } catch Error(string memory reason) {
                    console.log("Buy failed:", reason);
                }
            } else {
                uint256 sellAmount = token.balanceOf(trader) / 2;
                if(sellAmount > 0) {
                    address[] memory path = new address[](2);
                    path[0] = address(token);
                    path[1] = WETH;
                    
                    token.approve(ROUTER, sellAmount);
                    try IUniswapV2Router002(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
                        sellAmount,
                        0,
                        path,
                        trader,
                        block.timestamp
                    ) {
                        uint256 gasUsed = gasStart - gasleft();
                        
                        // Check if this is a new gas value
                        bool isNewValue = true;
                        for(uint256 j = 0; j < uniqueValuesFound; j++) {
                            if(gasUsed == uniqueGasValues[j]) {
                                gasValueCounts[j]++;
                                isNewValue = false;
                                break;
                            }
                        }
                        
                        if(isNewValue && uniqueValuesFound < 10) {
                            uniqueGasValues[uniqueValuesFound] = gasUsed;
                            gasValueCounts[uniqueValuesFound] = 1;
                            uniqueValuesFound++;
                            console.log("New gas value found:", gasUsed);
                        }
                        
                    } catch Error(string memory reason) {
                        console.log("Sell failed:", reason);
                    }
                }
            }
            
            vm.stopPrank();
        }

        // Print all unique gas values and their frequencies
        console.log("\n=== Unique Gas Values ===");
        for(uint256 i = 0; i < uniqueValuesFound; i++) {
            console.log("Gas:", uniqueGasValues[i], "Count:", gasValueCounts[i]);
        }

        /*
        before gas optimization
        === Unique Gas Values ===
        Gas: 160562 Count: 1
        Gas: 115946 Count: 1
        Gas: 115947 Count: 2
        Gas: 115917 Count: 1
        Gas: 115948 Count: 2
        Gas: 115918 Count: 1
        Gas: 115949 Count: 2
        Gas: 94018 Count: 2
        Gas: 94050 Count: 2
        Gas: 94019 Count: 13


        after assemblifying approve and balanceOf
        OOF our cheapest tx are more spensive
        3/7/24
        maybe its because of otehr logic too T.T
        === Unique Gas Values ===
        Gas: 160824 Count: 1
        Gas: 117024 Count: 1
        Gas: 117025 Count: 3
        Gas: 116996 Count: 1
        Gas: 116997 Count: 1
        Gas: 117026 Count: 1
        Gas: 117027 Count: 2
        Gas: 95097 Count: 2
        Gas: 95127 Count: 1
        Gas: 95128 Count: 2


        //After assembly sellTax 
        === Unique Gas Values ===
        Gas: 160824 Count: 1
        Gas: 117024 Count: 1
        Gas: 117025 Count: 3
        Gas: 116996 Count: 1
        Gas: 116997 Count: 1
        Gas: 117026 Count: 1
        Gas: 117027 Count: 2
        Gas: 95097 Count: 2
        Gas: 95127 Count: 1
        Gas: 95128 Count: 2

        Why is it the SAME! T.T


        direct gas emits
        ├─ emit TaxOperation(opType: "add", gasUsed: 130778 [1.307e5])
        ├─ emit TaxOperation(opType: "buy", gasUsed: 112930 [1.129e5])
        ├─ emit TaxOperation(opType: "sell", gasUsed: 133437 [1.334e5])
        sell using interface so it IS cheaper with my assembly bs. lfg!!!
        ├─ emit TaxOperation(opType: "sell", gasUsed: 134112 [1.341e5])

        post uniswappool instead of swaprouter
        Gas: 161385 Count: 1
        Gas: 117586 Count: 2
        Gas: 117560 Count: 2
        Gas: 117587 Count: 2
        Gas: 117588 Count: 1
        Gas: 117561 Count: 1
        Gas: 117589 Count: 1
        Gas: 95689 Count: 2
        Gas: 95661 Count: 6
        Gas: 95690 Count: 2

        */
    }

    // Add more tests as needed...
} 