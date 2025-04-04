// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EXEC404} from "../src/EXEC404.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
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

contract EXEC404Test is Test {
    // Constants for common addresses
    address constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router
    address constant V3ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;	//0x68B34Df539345556C21BF984377daab139449559; //Uniswap v3 router
    address constant POSITIONMANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    
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
    address[] internal testUsers = [alice, bob, carol, dave, emma, frank, grace, henry, ivy, jack, kelly, larry];
    
    // Contract instances
    EXEC404 public token;
    DN404Mirror public mirror;
    
    // Merkle tree roots for 12 days
    bytes32[] public merkleRoots;
    
    // Test amounts
    uint256 constant PRICE_PER_TOKEN = 0.0025 ether;
    uint256 constant ONE_UNIT = 1000000 ether; // 1M tokens = 1 NFT
    
    // Events to track
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event NFTTransfer(address indexed from, address indexed to, uint256 indexed id);
    
    // Mapping to store all merkle trees data
    mapping(uint256 => mapping(address => bool)) public whitelistsByDay;
    
    function setUp() public virtual {
        // Initialize test users with different "holdings" to simulate CULT holders
        address[] memory users = new address[](12);
        
        // Set up whitelists for each day (0-12) procedurally
        for (uint256 day = 0; day <= 12; day++) {
            // Each day includes users from index 0 up to the current day (inclusive)
            for (uint256 userIndex = 0; userIndex <= day && userIndex < testUsers.length; userIndex++) {
                whitelistsByDay[day][testUsers[userIndex]] = true;
            }
        }

        // Generate merkle roots
        merkleRoots = generateMerkleRoots();
        
        // Deploy contracts with generated merkle roots
        vm.startPrank(alice);
        token = new EXEC404(merkleRoots);
        
        vm.stopPrank();
        
        // Setup initial balances for all test users
        for(uint256 i = 0; i < testUsers.length; i++) {
            vm.deal(testUsers[i], 10000 ether);
        }

        // Generate and set roots for all tiers
        for(uint256 day = 0; day < 12; day++) {
            bytes32[] memory leaves = new bytes32[](day + 1); // Each day has more users
            uint256 leafIndex = 0;
            
            // Generate leaves for this day
            for(uint256 i = 0; i < testUsers.length; i++) {
                if(whitelistsByDay[day][testUsers[i]]) {
                    leaves[leafIndex] = keccak256(abi.encodePacked(testUsers[i]));
                    leafIndex++;
                }
            }
            
            // Sort leaves for consistent tree generation
            sortBytes32Array(leaves);
            
            // Generate and set root for this day
            bytes32 root = generateMerkleRoot(leaves);
        }
    }

    function generateMerkleRoots() internal view returns (bytes32[] memory) {
        bytes32[] memory roots = new bytes32[](12); // 12 roots (days 0-11)
        
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

    function sortBytes32Array(bytes32[] memory arr) internal pure returns (bytes32[] memory) {
        // Bubble sort implementation (simple but not optimal for large arrays)
        for (uint256 i = 0; i < arr.length - 1; i++) {
            for (uint256 j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    // Swap elements
                    (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
                }
            }
        }
        return arr;
    }

    function generateMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "Empty leaves");
        
        if (leaves.length == 1) {
            return leaves[0];
        }
        
        // Create new layer with paired hashes
        uint256 layerLength = (leaves.length + 1) / 2;
        bytes32[] memory layer = new bytes32[](layerLength);
        
        for (uint256 i = 0; i < leaves.length; i += 2) {
            if (i + 1 < leaves.length) {
                // Order the pair based on their values to match MerkleProofLib
                bytes32 left = leaves[i];
                bytes32 right = leaves[i + 1];
                if (left > right) {
                    (left, right) = (right, left);
                }
                layer[i/2] = keccak256(abi.encodePacked(left, right));
            } else {
                layer[i/2] = keccak256(abi.encodePacked(leaves[i], leaves[i]));
            }
        }
        
        // Recursively generate root from this layer
        return generateMerkleRoot(layer);
    }

    

    function generateProof(uint256 day, address user) public view returns (bytes32[] memory) {
        require(day < 12, "Invalid day");
        require(whitelistsByDay[day][user], "User not whitelisted for this day");

        // Count whitelisted addresses and create leaves array
        uint256 leafCount = 0;
        for (uint256 i = 0; i < testUsers.length; i++) {
            if (whitelistsByDay[day][testUsers[i]]) {
                leafCount++;
            }
        }

        // Special case: if there's only one leaf, return empty proof
        if (leafCount == 1) {
            return new bytes32[](0);
        }

        // Create and populate leaves array
        bytes32[] memory leaves = new bytes32[](leafCount);
        uint256 leafIndex = 0;
        for (uint256 i = 0; i < testUsers.length; i++) {
            if (whitelistsByDay[day][testUsers[i]]) {
                leaves[leafIndex] = keccak256(abi.encodePacked(testUsers[i]));
                leafIndex++;
            }
        }

        // If only one leaf, return empty proof
        if (leaves.length == 1) {
            return new bytes32[](0);
        }

        // Sort leaves for consistent tree generation
        sortBytes32Array(leaves);

        // Find position of user's leaf
        bytes32 userLeaf = keccak256(abi.encodePacked(user));
        uint256 userLeafIndex;
        for (userLeafIndex = 0; userLeafIndex < leaves.length; userLeafIndex++) {
            if (leaves[userLeafIndex] == userLeaf) break;
        }

        // Calculate proof length (log2 ceiling of leaves length)
        uint256 proofLength = 0;
        uint256 layerSize = leaves.length;
        while (layerSize > 1) {
            proofLength++;
            layerSize = (layerSize + 1) / 2;
        }

        // Generate proof
        bytes32[] memory proof = new bytes32[](proofLength);
        bytes32[] memory currentLayer = leaves;
        uint256 currentIndex = userLeafIndex;
        
        for (uint256 i = 0; i < proofLength; i++) {
            bytes32[] memory newLayer = new bytes32[]((currentLayer.length + 1) / 2);
            
            for (uint256 j = 0; j < currentLayer.length; j += 2) {
                uint256 k = j / 2;
                if (j + 1 < currentLayer.length) {
                    // Order the pair based on their values to match MerkleProofLib
                    bytes32 left = currentLayer[j];
                    bytes32 right = currentLayer[j + 1];
                    if (left > right) {
                        (left, right) = (right, left);
                    }
                    newLayer[k] = keccak256(abi.encodePacked(left, right));
                } else {
                    newLayer[k] = keccak256(abi.encodePacked(currentLayer[j], currentLayer[j]));
                }
            }

            // Add sibling to proof
            if (currentIndex % 2 == 0) {
                proof[i] = currentIndex + 1 < currentLayer.length ? 
                    currentLayer[currentIndex + 1] : 
                    currentLayer[currentIndex];
            } else {
                proof[i] = currentLayer[currentIndex - 1];
            }

            currentLayer = newLayer;
            currentIndex = currentIndex / 2;
        }

        return proof;
    }

    function testMerkleRoots() public {
        bytes32[] memory roots = generateMerkleRoots();
        for(uint256 i = 0; i < roots.length; i++) {
            console.log("Root for day %d:", i);
            console.logBytes32(roots[i]);
        }
    }

    function testMerkleProofGenerationValid() public {
        // Test valid proof generation
        bytes32[] memory proof = generateProof(0, alice);
        console.log("Proof for alice on day 0:");
        for(uint256 i = 0; i < proof.length; i++) {
            console.logBytes32(proof[i]);
        }
        // Verify the proof against the stored root
        bool isValid = verifyMerkleProof(proof, merkleRoots[0], alice);
        assertTrue(isValid, "Proof verification failed");
    }

    function testMerkleProofGenerationInvalid() public {
        // Test invalid case
        address randomAddr = makeAddr("random");
        
        // Try-catch approach
        try this.generateProof(0, randomAddr) returns (bytes32[] memory) {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "User not whitelisted for this day", "Wrong revert reason");
        }
    }

    // Verify merkle proof
    function verifyMerkleProof(bytes32[] memory proof, bytes32 root, address user) internal pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        bytes32 computedHash = leaf;
        
        for(uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if(computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
    
    // Helper to move time forward
    function moveForwardDays(uint256 days_) internal {
        vm.warp(block.timestamp + days_ * 1 days);
    }
    
    // Helper to check token and NFT balances
    function checkBalances(address user, uint256 expectedTokens, uint256 expectedNFTs) internal {
        assertEq(token.balanceOf(user), expectedTokens, "Token balance mismatch");
        assertEq(mirror.balanceOf(user), expectedNFTs, "NFT balance mismatch");
    }
    
    // Helper to track gas usage
    function trackGas() internal returns (uint256) {
        uint256 gasStart = gasleft();
        return gasStart;
    }
    
    function calculateGasUsed(uint256 gasStart) internal view returns (uint256) {
        return gasStart - gasleft();
    }

    function testBondingPurchaseRestrictions() public {
        uint256 amount = 1000 ether;  // Amount of tokens to buy
        uint256 maxCost = 1 ether;    // Max ETH willing to spend
        
        // Test for each da
        
        for(uint256 day = 0; day < 12; day++) {
            console.log("\nTesting day:", day);
            
            // Set blockchain to correct day
            vm.warp(token.LAUNCH_TIME() + (day * 1 days));
            
            // Test each user
            for(uint256 i = 0; i < testUsers.length; i++) {
                address user = testUsers[i];
                bool isWhitelisted = whitelistsByDay[day][user];
                
                console.log("Testing user:", user);
                console.log("Is whitelisted:", isWhitelisted);
                
                vm.startPrank(user);
                vm.deal(user, maxCost);  // Give user some ETH
                
                // In testBondingPurchaseRestrictions
                if(isWhitelisted) {
                    // Should succeed for whitelisted users
                    bytes32[] memory proof = generateProof(day, user);
                    console.log("Generated proof length:", proof.length);
                    for(uint256 j = 0; j < proof.length; j++) {
                        console.logBytes32(proof[j]);
                    }
                    console.logBytes32(merkleRoots[day]); // Log the expected root
                    token.buyBonding{value: maxCost}(amount, maxCost, false, proof, '');
                    assertTrue(token.balanceOf(user) > 0, "Whitelisted user should be able to buy");
                } else {
                    // Should fail for non-whitelisted users
                    bytes32[] memory emptyProof;
                    vm.expectRevert("Non-white");  // Updated error message
                    token.buyBonding{value: maxCost}(amount, maxCost, false, emptyProof, '');
                }
                
                vm.stopPrank();
            }
        }
    }

    function testCalculateCostLimits() public view {
        // Let's test different amounts and log the costs
        uint256[] memory testAmounts = new uint256[](7);
        testAmounts[0] = 1000 ether;                    // 1,000 tokens
        testAmounts[1] = 1_000_000 ether;              // 1M tokens
        testAmounts[2] = 100_000_000 ether;            // 100M tokens
        testAmounts[3] = 1_000_000_000 ether;          // 1B tokens
        testAmounts[4] = 2_000_000_000 ether;          // 2B tokens
        testAmounts[5] = 3_996_000_000 ether;          // ~90% of 4.44B
        testAmounts[6] = 4_440_000_000 ether;          // 4.44B tokens

        console.log("Testing calculateCost limits:");
        console.log("==============================");
        
        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            try token.calculateCost(amount) returns (uint256 cost) {
                console.log("Amount (tokens):", amount / 1e18);
                console.log("Cost (ETH):", cost / 1e18);
                console.log("------------------------------");
            } catch {
                console.log("Failed at amount:", amount / 1e18);
                console.log("------------------------------");
                break;
            }
        }
    }

    function testBondingBuyLimit() public {
        bytes32[] memory proof = generateProof(0, alice);

        // Test: Can't exceed max supply
        vm.warp(token.LAUNCH_TIME());
        vm.startPrank(alice);
        vm.deal(alice, 1000000 ether); // Give Alice plenty of ETH

        console.log("Starting bonding curve tests:");
        console.log("=============================");

        // Try increasingly large purchases
        uint256[] memory purchaseAmounts = new uint256[](1);
        purchaseAmounts[0] = 3_996_000_001 ether; //exceeds bonding
        //purchaseAmounts[0] = 1_000_000 ether;        // 1M
        // purchaseAmounts[1] = 10_000_000 ether;       // 10M
        // purchaseAmounts[2] = 100_000_000 ether;      // 100M
        // purchaseAmounts[3] = 500_000_000 ether;      // 500M
        // purchaseAmounts[4] = 1_000_000_000 ether;    // 1B
        // purchaseAmounts[5] = 2_000_000_000 ether;    // 2B
        // purchaseAmounts[6] = 1_611_000_000 ether; // last bit

        for (uint256 i = 0; i < purchaseAmounts.length; i++) {
            uint256 amount = purchaseAmounts[i];
            try token.calculateCost(amount) returns (uint256 cost) {
                console.log("\nTrying to buy tokens:", amount / 1e18);
                console.log("Cost calculated:", cost / 1e18);
                console.log("Current total supply:", token.totalSupply() / 1e18);
                console.log("Total bonding supply:", token.totalBondingSupply());
                
                try token.buyBonding{value: cost}(amount, cost, false, proof, '') {
                    console.log("Purchase succeeded");
                } catch Error(string memory reason) {
                    console.log("Purchase failed with reason:", reason);
                    break;
                }
            } catch Error(string memory reason) {
                console.log("\nCalculateCost failed at amount:", amount / 1e18);
                console.log("Reason:", reason);
                break;
            }
        }

        vm.stopPrank();
    }

    function testBondingEdgeCases() public {
        uint256 amount = 1000 ether;
        uint256 maxCost = 1 ether;
        bytes32[] memory proof = generateProof(0, alice);

        // Test: Can't exceed max supply
        vm.warp(token.LAUNCH_TIME());
        vm.startPrank(alice);
        token.buyBonding{value: 1 ether}(amount, 1 ether, false, proof, '');
        
        // Calculate max bonding amount (90% of 4.4B)
        uint256 maxBondingSupply = token.MAX_SUPPLY() - 444000000 ether;
        uint256 tooMuch = maxBondingSupply + 1; // Just over the max allowed
        vm.deal(alice, 100 ether); // Ensure we have enough ETH
        
        vm.expectRevert("Exceeds bonding");
        token.buyBonding{value: 100 ether}(tooMuch, 100 ether, false, proof, '');
        
        vm.stopPrank();

        // Test: Can't send insufficient ETH
        vm.startPrank(alice);
        vm.deal(alice, maxCost);
        uint256 cost = token.calculateCost(amount);
        vm.expectRevert("Low ETH value");
        token.buyBonding{value: cost - 1}(amount, maxCost, false, proof, '');
        vm.stopPrank();

        // Test: Can't exceed slippage
        vm.startPrank(alice);
        uint256 actualCost = token.calculateCost(amount);  // Use the contract's calculation
        vm.deal(alice, actualCost);
        uint256 lowMaxCost = actualCost - 1;
        vm.expectRevert("MaxCost exceeded");
        token.buyBonding{value: actualCost}(amount, lowMaxCost, false, proof, '');
        vm.stopPrank();

        // Test: NFT minting flag works
        vm.startPrank(alice);
        vm.deal(alice, actualCost * 3);
        actualCost = token.calculateCost(amount);  // Use the contract's calculation
        // First buy with NFT minting off
        
        token.buyBonding{value: actualCost}(amount, actualCost, false, proof, '');
        
        uint256 nftBalanceBefore = token.balanceOf(alice);
        
        // Then buy with NFT minting on
        
        actualCost = token.calculateCost(amount);
        token.buyBonding{value: actualCost}(amount, actualCost, true, proof, '');
        uint256 nftBalanceAfter = token.balanceOf(alice);
        
        assertTrue(nftBalanceAfter > nftBalanceBefore, "NFT minting flag should work");
        vm.stopPrank();
    }

    // Helper function to simulate bonding curve sales and deploy liquidity
    function setupLiquidityPool() internal virtual returns (uint256 lpTokens) {
        uint256 dailyPurchaseAmount = token.MAX_SUPPLY() / 11;
        
        // Buy tokens through bonding curve over 12 days
        for(uint256 day = 0; day < 9; day++) {
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
        
        // Get initial state
        uint256 contractETH = address(token).balance;
        uint256 contractTokens = token.balanceOf(address(token));
        
        console.log("\nPre-Liquidity State:");
        console.log("Contract ETH Balance:", contractETH);
        console.log("Contract Token Balance:", contractTokens);
        
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

    function testGradualBondingAndLiquidity() public {
        //uint256 bondingSupply = token.MAX_SUPPLY() - token.totalSupply();
        //console.log("Bonding supply:", bondingSupply);
        uint256 dailyPurchaseAmount = token.MAX_SUPPLY() / 10;
        
        for(uint256 day = 0; day < 9; day++) {
            // Set time to current day
            vm.warp(token.LAUNCH_TIME() + (day * 1 days));
            console.log("\nDay:", day);
            
            // Get the whitelisted user for this day
            address buyer = testUsers[day];
            bytes32[] memory proof = generateProof(day, buyer);
            
            // Calculate cost and provide ETH
            uint256 cost = token.calculateCost(dailyPurchaseAmount);
            vm.deal(buyer, cost);
            
            // Make purchase
            vm.startPrank(buyer);
            token.buyBonding{value: cost}(
                dailyPurchaseAmount,
                cost,  // Max cost same as calculated cost
                false,  // Mint NFTs
                proof,
                ''
            );
            vm.stopPrank();
            
            console.log("User purchased:", dailyPurchaseAmount);
            console.log("ETH paid:", cost);
        }
        
        // Move time forward past the 12-day period
        vm.warp(token.LAUNCH_TIME() + 13 days);
        
        // Random user attempts to deploy liquidity
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        
        // Get initial contract ETH balance
        uint256 initialETH = address(token).balance;
        console.log("\nContract ETH balance:", initialETH);
        
        // Deploy liquidity
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = token.deployLiquidity();
        
        // Verify liquidity deployment
        assertTrue(token.liquidityPair() != address(0), "Liquidity pair not created");
        //assertEq(amountToken, token.totalSupply(), "Incorrect token amount in LP");
        // Use assertApproxEqAbs instead of direct equality
        assertApproxEqAbs(
            amountETH,
            initialETH,
            0.01 ether, // Allow for small difference
            "Not all ETH deployed to LP"
        );
        assertTrue(liquidity > 0, "No LP tokens minted");
        
        console.log("Liquidity Deployed:");
        console.log("- Tokens:", amountToken);
        console.log("- ETH:", amountETH);
        console.log("- LP tokens:", liquidity);
        
        vm.stopPrank();
    }

    function testPoolBuying() public {
        setupLiquidityPool();
        address trader = makeAddr("trader");
        vm.deal(trader, 100 ether);
        
        vm.startPrank(trader);
        
        uint256 amountIn = 1 ether;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(token);
        
        uint256[] memory amounts = IUniswapV2Router002(ROUTER).getAmountsOut(amountIn, path);
        
        console.log("\nSwap Details:");
        console.log("ETH in:", amountIn);
        console.log("Expected tokens out:", amounts[1]);
        
        IUniswapV2Router002(ROUTER).swapExactETHForTokens{value: amountIn}(
            0,
            path,
            trader,
            block.timestamp
        );
        
        assertTrue(token.balanceOf(trader) > 0, "No tokens received");
        vm.stopPrank();
    }

    function testPoolSelling() public {
        setupLiquidityPool();
        address trader = makeAddr("trader");
        
        // First buy some tokens
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(token);
        
        // Buy tokens first
        IUniswapV2Router002(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            path,
            trader,
            block.timestamp
        );
        
        // Wait for next block to ensure reserves are updated
        vm.roll(block.number + 1);
        
        uint256 sellAmount = token.balanceOf(trader);
        token.approve(ROUTER, sellAmount);
        
        // Now sell
        path[0] = address(token);
        path[1] = WETH;
        
        IUniswapV2Router002(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            trader,
            block.timestamp
        );
        
        assertEq(token.balanceOf(trader), 0, "Not all tokens sold");
        assertTrue(trader.balance > 0, "No ETH received");
        
        vm.stopPrank();
    }

    // function testCreateCultPosition() public {
    //     address user = makeAddr("cultLPProvider");
    //     vm.deal(user, 1 ether);
    //     vm.startPrank(user);
        
    //     // Prepare ETH amounts
        
    //     // Buy CULT tokens
    //     IWETH(token.weth()).deposit{value: 0.005 ether}();
    //     IERC20(token.weth()).approve(address(token.router3()), 0.005 ether);
        
    //     bytes memory path = abi.encodePacked(
    //         token.weth(),
    //         uint24(10000),
    //         token.CULT()
    //     );
        
    //     ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
    //         path: path,
    //         recipient: user,
    //         deadline: block.timestamp,
    //         amountIn: 0.005 ether,
    //         amountOutMinimum: 0
    //     });
        
    //     uint256 cultBought = ISwapRouter(token.router3()).exactInput(params);
        
    //     // Prepare for position
    //     IWETH(token.weth()).deposit{value: 0.005 ether}();
        
    //     // Calculate position range
    //     //address cultPool = token.factory3().getPool(token.CULT(), token.weth(), 10000);
    //     (,bytes memory d) = token.factory3().staticcall(abi.encodeWithSelector(0x1698ee82, token.CULT(), token.weth(), 10000));
    //     address cultPool = abi.decode(d, (address));
    //     //(, int24 currentTick,,,,, ) = IUniswapV3Pool(cultPool).slot0();
    //     (,bytes memory d2) = cultPool.staticcall(abi.encodeWithSelector(0x3850c7bd));
    //     (uint160 sqrtPriceX96, int24 currentTick,,,,,) = abi.decode(d2, (uint160,int24,uint16,uint16,uint16,uint8,bool));

        
    //     //int24 tickSpacing = IUniswapV3Pool(cultPool).tickSpacing();
    //     (,bytes memory d3) = cultPool.staticcall(abi.encodeWithSelector(0xd0c93a7c));
    //     int24 tickSpacing = abi.decode(d3, (int24));
    //     //int24 tickRange = tickSpacing * 16;
    //     //int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
    //     //int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;
        
    //     // Approve tokens
    //     IERC20(token.CULT()).approve(address(token.positionManager()), cultBought);
    //     IERC20(token.weth()).approve(address(token.positionManager()), 0.005 ether);
        
    //     // Create position
    //     INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
    //         token0: token.CULT(),
    //         token1: token.weth(),
    //         fee: 10000,
    //         tickLower: ((currentTick - (tickSpacing * 16)) / tickSpacing) * tickSpacing,
    //         tickUpper: ((currentTick + (tickSpacing * 16)) / tickSpacing) * tickSpacing,
    //         amount0Desired: cultBought,
    //         amount1Desired: 0.005 ether,
    //         amount0Min: 0,
    //         amount1Min: 0,
    //         recipient: user,
    //         deadline: block.timestamp
    //     });
        
    //     try INonfungiblePositionManager(token.positionManager()).mint(mintParams) returns (
    //         uint256 tokenId,
    //         uint128 liquidity,
    //         uint256 amount0,
    //         uint256 amount1
    //     ) {
    //         assertTrue(tokenId > 0, "Position should be created");
    //         assertTrue(liquidity > 0, "Position should have liquidity");
    //     } catch Error(string memory reason) {
    //         fail();
    //     }
        
    //     vm.stopPrank();
    // }

    function testAddressLT() public pure {
        address _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address _cult = 0x0000000000c5dc95539589fbD24BE07c6C14eCa4;
        console.log(_cult < _weth);
    }

    function testMarket() public {
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
            //vm.roll(block.number + i % 2);
            //vm.warp(block.timestamp + 15 * (i % 2));
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
        // Add debug logs
        
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
                                    console.log("Sell failed:", reason);
                        console.log("Post-fail balance:", token.balanceOf(seller));
                        console.log("Post-fail allowance:", token.allowance(seller, ROUTER));
                    }
                }
                vm.stopPrank();
            }
        }

        // Final metrics
        console.log("\n=== Trading Summary ===");
        console.log("Total Volume (ETH):", totalVolume / 1 ether);
        console.log("Total Taxes (ETH):", totalTaxes / 1 ether);
        
        // Basic assertions
        assertTrue(totalVolume > 0, "Should have non-zero volume");
        assertTrue(totalTaxes > 0, "Should have collected taxes");

        // Final state
        console.log("\n=== Final Balances ===");
        console.log("EXEC Balance:", token.balanceOf(address(token)) / 1 ether);
        console.log("ETH Balance:", address(token).balance );
        console.log("CULT Balance:", IERC20(token.CULT()).balanceOf(address(token)) / 1 ether);

        // Get V3 position details
        uint256 positionId = token.cultV3Position();
        if (positionId > 0) {
            (,,,,,,,uint128 liquidity,,,,) = IPositionManager(address(POSITIONMANAGER)).positions(positionId);
            console.log("CULT-ETH V3 Position Liquidity:", liquidity);
        } else {
            console.log("No V3 Position found");
        }
    }

    function predictOperation() internal view returns (uint256) {
        // Instead of checking current balances, we should:
        // 1. For buys: Check if this buy will generate enough EXEC to trigger a sell
        // 2. For sells: Check if this sell will generate enough ETH to buy CULT
        // 3. After CULT buy: Check if we'll have enough CULT to add LP

        // Get pre-operation state
        uint256 pendingExec = token.balanceOf(address(token));
        uint256 pendingEth = address(token).balance;
        uint256 pendingCult = IERC20(token.CULT()).balanceOf(address(token));

        console.log("Pending state:");
        console.log("Pending EXEC:", pendingExec);
        console.log("Pending ETH:", pendingEth);
        console.log("Pending CULT:", pendingCult);

        // The next operation will be determined by this transaction
        // We need to predict what the balances will be AFTER this transaction
        
        return type(uint256).max; // temporary
    }

    function testGasBenchmark() public {
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


        final version?? no interfaces
        === Unique Gas Values ===
        Gas: 160746 Count: 1
        Gas: 116946 Count: 1
        Gas: 116947 Count: 3
        Gas: 116918 Count: 1
        Gas: 116919 Count: 1
        Gas: 116948 Count: 1
        Gas: 116949 Count: 2
        Gas: 95019 Count: 2
        Gas: 95049 Count: 1
        Gas: 95050 Count: 2

        */
    }

    function testCollectV3Fees() public {
        // First run market simulation to generate fees
        //uint256 initialLpTokens = setupLiquidityPool();
        testMarket(); // This generates real trading volume and fees

        // Get the position ID and manager
        uint256 positionId = token.cultV3Position();
        IPositionManager posManager = IPositionManager(POSITIONMANAGER);
        
        // Get initial position state
        (,,,,,,,,,, uint128 initialTokensOwed0, uint128 initialTokensOwed1) = 
            posManager.positions(positionId);
        
        console.log("\nBefore Collection:");
        console.log("Tokens Owed 0:", initialTokensOwed0);
        console.log("Tokens Owed 1:", initialTokensOwed1);
        // Prank as the NFT owner
        vm.startPrank(0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6);

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

    function testBondingMessaging() public {
        uint256 amount = 100 ether;
        uint256 maxCost = 1 ether;
        vm.warp(token.LAUNCH_TIME());
        address user = testUsers[0];
        bytes32[] memory proof = generateProof(0, user);
        
        vm.startPrank(user);
        vm.deal(user, maxCost * 3);

        // Initialize account first with a small purchase
        token.buyBonding{value: maxCost}(amount, maxCost, false, proof, "");
        console.log("Initial account setup complete");

        // Now test the actual message functionality
        _testBondingBuy(amount, maxCost, proof, "");
        _testBondingBuy(amount, maxCost, proof, "");
        _testBondingBuy(amount, maxCost, proof, "Hello World!");

        // Test sells
        uint256 sellAmount = 50 ether;
        _testBondingSell(sellAmount, 0, proof, "");
        _testBondingSell(sellAmount, 0, proof, "Goodbye!");

        vm.stopPrank();
    }

    function _testBondingBuy(
        uint256 amount,
        uint256 maxCost,
        bytes32[] memory proof,
        string memory testMessage
    ) private {
        uint256 messageIndex = token.totalMessages();
        uint256 gasBefore = gasleft();
        
        token.buyBonding{value: maxCost}(amount, maxCost, false, proof, testMessage);
        
        console.log(
            "Gas used for buy with%smessage: %d",
            bytes(testMessage).length == 0 ? " empty " : " ",
            gasBefore - gasleft()
        );

        if (bytes(testMessage).length > 0) {
            (address sender,,,,string memory message) = token.getMessageDetails(messageIndex);
            assertEq(sender, testUsers[0], "Wrong sender stored");
            assertEq(message, testMessage, "Wrong message stored");
        }
    }

    function _testBondingSell(
        uint256 amount,
        uint256 minRefund,
        bytes32[] memory proof,
        string memory testMessage
    ) private {
        uint256 messageIndex = token.totalMessages();
        uint256 gasBefore = gasleft();
        
        token.sellBonding(amount, minRefund, proof, testMessage);
        
        console.log(
            "Gas used for sell with%smessage: %d",
            bytes(testMessage).length == 0 ? " empty " : " ",
            gasBefore - gasleft()
        );

        if (bytes(testMessage).length > 0) {
            (address sender,,,,string memory message) = token.getMessageDetails(messageIndex);
            assertEq(sender, testUsers[0], "Wrong sender stored");
            assertEq(message, testMessage, "Wrong message stored");
        }
    }

    function testGetMessagesBatch() public {
    uint256 baseAmount = 1_000_000 ether;
    uint256 maxCost = 1 ether;
    vm.warp(token.LAUNCH_TIME());
    address user = testUsers[0];
    bytes32[] memory proof = generateProof(0, user);
    
    vm.startPrank(user);
    vm.deal(user, maxCost * 10); // give a bit more ETH

    // Initialize account
    token.buyBonding{value: maxCost}(baseAmount, maxCost, false, proof, "");

    // Create a series of messages
    string[4] memory testMessages = [
        "First message",
        "Second message",
        "Third message",
        "Fourth message"
    ];

    for (uint i = 0; i < testMessages.length; i++) {
        uint256 amount = baseAmount / (i + 1); // prevent overflow and reduce over time
        if (i % 2 == 0) {
            uint256 cost = token.calculateCost(amount);
            token.buyBonding{value: cost}(amount, cost, false, proof, testMessages[i]);
        } else {
            token.sellBonding(amount / 2, 0, proof, testMessages[i]);
        }
    }

    // Test valid range (0-1)
    console.log("\nTesting range 0-1:");
    (
        address[] memory senders,
        uint32[] memory timestamps,
        uint96[] memory amounts,
        bool[] memory isBuys,
        string[] memory messages
    ) = token.getMessagesBatch(0, 1);

    for (uint i = 0; i <= 1; i++) {
        console.log("Message %s:", i);
        console.log("Sender:", senders[i]);
        console.log("Timestamp:", timestamps[i]);
        console.log("Amount (scaled):", amounts[i]);
        console.log("Is Buy:", isBuys[i]);
        console.log("Message:", messages[i]);

        if (isBuys[i]) {
            uint96 expected = uint96((baseAmount / (i + 1)) / 1e18);
            assertGt(expected, 0, "Expected amount is zero!");
            assertEq(amounts[i], expected, "Buy amount not preserved as scaled ETH");
        }
    }

    // Test another valid range (1-3)
    console.log("\nTesting range 1-3:");
    (senders, timestamps, amounts, isBuys, messages) = token.getMessagesBatch(1, 3);

    for (uint i = 0; i < 3; i++) {
        console.log("Message %s:", i + 1);
        console.log("Sender:", senders[i]);
        console.log("Timestamp:", timestamps[i]);
        console.log("Amount (scaled):", amounts[i]);
        console.log("Is Buy:", isBuys[i]);
        console.log("Message:", messages[i]);
    }

    // Test invalid ranges
    console.log("\nTesting invalid ranges:");
    vm.expectRevert("Invalid range");
    token.getMessagesBatch(2, 1);
    console.log("Correctly reverted when end < start");

    vm.expectRevert("End out of bounds");
    token.getMessagesBatch(0, 10);
    console.log("Correctly reverted when end > totalMessages");

    vm.stopPrank();
}


    function testBondingPriceChanges() public {
        address user = testUsers[0];
        bytes32[] memory proof = generateProof(0, user);
        
        vm.startPrank(user);
        vm.deal(user, 100 ether); // Give plenty of ETH
        vm.warp(token.LAUNCH_TIME());

        uint256 purchaseAmount = 250_000_000 ether; // 250M EXEC per purchase
        uint256 checkAmount = 1_000_000 ether; // Check price for 10M EXEC
        
        console.log("\n=== Bonding Price Changes ===");
        console.log("Initial price for 1M EXEC: %s wei", token.calculateCost(checkAmount));
        
        // Buy in 10M EXEC increments and check price after each purchase
        for (uint256 i = 1; i <= 16; i++) {
            uint256 cost = token.calculateCost(purchaseAmount);
            
            // Make the purchase
            _testBondingBuy(purchaseAmount, cost, proof, "");
            
            // Check new price for next 10M EXEC
            uint256 newPrice = token.calculateCost(checkAmount);
            console.log(
                "After %sM EXEC purchased - Price for next 1M: %s wei",
                i * 250,
                newPrice
            );
        }
        
        vm.stopPrank();
    }

    function testBondingSlippage() public {
        uint256 amount = 10_000_000 ether; // Trying to buy 10M tokens
        uint256 maxCost = 0.0025 ether;      // But only paying 0.25 ETH (price for ~1M tokens)
        
        vm.warp(token.LAUNCH_TIME());
        address user = testUsers[0];
        bytes32[] memory proof = generateProof(0, user);
        
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        // Calculate the actual cost for 10M tokens
        uint256 actualCost = token.calculateCost(amount);
        console.log("Actual cost for 10M tokens:", actualCost);
        console.log("Attempting to pay only:", maxCost);

        // This should revert because we're trying to buy more tokens than we're paying for
        vm.expectRevert("MaxCost exceeded");
        token.buyBonding{value: maxCost}(amount, maxCost, false, proof, "");

        // Now let's verify the correct amount we can buy with 0.25 ETH
        uint256 correctAmount = 1_000_000 ether; // Expected ~1M tokens for 0.25 ETH
        uint256 correctCost = token.calculateCost(correctAmount);
        
        // This should succeed
        token.buyBonding{value: correctCost}(correctAmount, correctCost, false, proof, "");
        
        // Verify the balance is correct
        assertEq(token.balanceOf(user)- 1_000_000 ether, correctAmount, "Received wrong amount of tokens");
        
        vm.stopPrank();
    }

    //price deprecat4ed
    // function testTokenEthConversions() public {
    //     uint256 maxBondingSupply = token.MAX_SUPPLY() - token.LIQUIDITY_RESERVE();
    //     uint256 basePrice = 2500000000000000; // 0.0025 ETH in wei
    //     uint256 baseAmount = 1_000_000 ether;  // 1M EXEC
        
    //     console.log("\n=== Testing Full Bonding Curve ===");
    //     console.log("Max Bonding Supply:", maxBondingSupply / 1e18, "EXEC");
        
    //     // Test at 10% intervals up to 90%
    //     for (uint256 i = 1; i <= 9; i++) {
    //         uint256 targetAmount = (maxBondingSupply * i) / 10;
            
    //         // Calculate cost for full amount up to this point
    //         uint256 totalCost = token.calculateCost(targetAmount);
            
    //         // Calculate cost for just the last 1M EXEC at this point
    //         uint256 costForNext1M;
    //         if (i < 9) {
    //             uint256 costBefore = token.calculateCost(targetAmount);
    //             uint256 costAfter = token.calculateCost(targetAmount + 1_000_000 ether);
    //             costForNext1M = costAfter - costBefore;
    //         }
            
    //         console.log("\n=== %s0%% of Supply ===", i);
    //         console.log("Target EXEC:", targetAmount);
    //         console.log("Total Cost in ETH:", totalCost);
    //         console.log("Average Price per 1M EXEC:", (totalCost * 1e18) / targetAmount / 1e18, "ETH");
    //         if (i < 9) {
    //             console.log("Marginal Price per 1M EXEC:", costForNext1M, "ETH");
    //         }
            
    //         // Also show the instantaneous price at this point
    //         uint256 instantPrice = token.getPrice(targetAmount);
    //         console.log("Instant Price:", instantPrice, "ETH");
    //     }

    //     // Now let's do a smaller purchase to verify
    //     vm.startPrank(alice);
    //     vm.deal(alice, type(uint256).max); // Give maximum possible ETH
    //     bytes32[] memory proof = generateProof(0, alice);
        
    //     // Try buying just 10% instead of 50%
    //     uint256 largeAmount = maxBondingSupply / 10; // 10% of supply instead of 50%
    //     uint256 largeCost = token.calculateCost(largeAmount);
        
    //     console.log("\n=== Large Purchase Test ===");
    //     console.log("Attempting to buy:", largeAmount, "EXEC");
    //     console.log("Calculated cost:", largeCost, "ETH");
        
    //     token.buyBonding{value: largeCost}(largeAmount, largeCost, false, proof, "");
        
    //     uint256 aliceBalance = token.balanceOf(alice);
    //     console.log("\nPurchase Results:");
    //     console.log("Alice's balance:", aliceBalance, "EXEC");
    //     console.log("Total bonding supply:", token.totalBondingSupply(), "EXEC");
        
    //     vm.stopPrank();
    // }

    // price deprecated
    // function testPriceCalculations() public {
    //     // Calculate 10% intervals of the max bonding supply
    //     uint256 maxBondingSupply = token.MAX_SUPPLY() - token.LIQUIDITY_RESERVE();
        
    //     console.log("\n=== Price Calculation Test ===");
    //     console.log("Max Bonding Supply:", maxBondingSupply / 1e18, "EXEC");
        
    //     // Test at each 10% interval
    //     for (uint256 i = 1; i <= 10; i++) {
    //         uint256 supplyPoint = (maxBondingSupply * i) / 10;
            
    //         // Get price at this supply point
    //         uint256 instantPrice = token.getPrice(supplyPoint);
            
    //         // Calculate integral up to this point
    //         uint256 totalCost = token.calculateCost(supplyPoint);
            
    //         // Calculate average price
    //         uint256 avgPrice = totalCost / (supplyPoint / 1e18);
            
    //         console.log("\n=== At %s0%% of Supply (%s EXEC) ===", i, supplyPoint / 1e18);
    //         console.log("Instant Price:", instantPrice, "ETH");
    //         console.log("Total Cost:", totalCost, "ETH");
    //         console.log("Average Price:", avgPrice, "ETH");
            
    //         // If not at the end, calculate marginal cost for next small increment
    //         if (i < 10) {
    //             uint256 nextPoint = supplyPoint + 1000000 ether; // Next 1M tokens
    //             uint256 nextCost = token.calculateCost(nextPoint);
    //             uint256 marginalCost = nextCost - totalCost;
                
    //             console.log("Marginal Cost (next 1M):", marginalCost, "ETH");
    //         }
    //     }
        
    //     // Additional test: verify small purchases near the start
    //     console.log("\n=== Small Purchase Tests (First 5M EXEC) ===");
    //     uint256[] memory smallAmounts = new uint256[](5);
    //     for (uint256 i = 0; i < 5; i++) {
    //         smallAmounts[i] = (i + 1) * 1000000 ether; // 1M EXEC increments
            
    //         uint256 price = token.getPrice(smallAmounts[i]);
    //         uint256 cost = token.calculateCost(smallAmounts[i]);
            
    //         console.log("\nAmount: %sM EXEC", i + 1);
    //         console.log("Instant Price:", price, "ETH");
    //         console.log("Total Cost:", cost, "ETH");
    //         console.log("Average Price:", (cost / (smallAmounts[i] / 1e18)), "ETH");
    //     }
    // }

    // function testIntegralCalculationSteps() public {
    //     // Let's test with 1M EXEC tokens (1e24) first
    //     uint256 testAmount = 1000000 ether; // 1M EXEC
        
    //     console.log("\n=== Testing Integral Calculation with 1M EXEC ===");
    //     console.log("Input amount:", testAmount / 1e18, "EXEC");
        
    //     // Step 1: Scale down
    //     uint256 scaledSupplyWad = testAmount / 1e7;
    //     console.log("\nStep 1: Scale down by 1e7");
    //     console.log("scaledSupplyWad:", scaledSupplyWad);
        
    //     // Step 2: Base price part
    //     uint256 basePart = token.INITIAL_PRICE() * scaledSupplyWad / 1e18;
    //     console.log("\nStep 2: Base price part (INITIAL_PRICE * scaledSupplyWad)");
    //     console.log("INITIAL_PRICE:", token.INITIAL_PRICE());
    //     console.log("basePart:", basePart);
        
    //     // Step 3: Quartic term (x^4)
    //     uint256 quarticStep1 = FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad); // x^2
    //     uint256 quarticStep2 = FixedPointMathLib.mulWad(quarticStep1, scaledSupplyWad);    // x^3
    //     uint256 quarticStep3 = FixedPointMathLib.mulWad(quarticStep2, scaledSupplyWad);    // x^4
    //     uint256 quarticTerm = FixedPointMathLib.mulWad(1 gwei, quarticStep3);              // coefficient * x^4
        
    //     console.log("\nStep 3: Quartic term calculations");
    //     console.log("x^2:", quarticStep1);
    //     console.log("x^3:", quarticStep2);
    //     console.log("x^4:", quarticStep3);
    //     console.log("Final quartic term:", quarticTerm);
        
    //     // Step 4: Cubic term (x^3)
    //     uint256 cubicStep1 = FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad);  // x^2
    //     uint256 cubicStep2 = FixedPointMathLib.mulWad(cubicStep1, scaledSupplyWad);       // x^3
    //     uint256 cubicCoef = 1333333333;                    // 4/3 * 1gwei
    //     uint256 cubicTerm = FixedPointMathLib.mulWad(cubicCoef, cubicStep2);              // coefficient * x^3
        
    //     console.log("\nStep 4: Cubic term calculations");
    //     console.log("x^2:", cubicStep1);
    //     console.log("x^3:", cubicStep2);
    //     console.log("Cubic coefficient:", cubicCoef);
    //     console.log("Final cubic term:", cubicTerm);
        
    //     // Step 5: Quadratic term (x^2)
    //     uint256 quadStep1 = FixedPointMathLib.mulWad(scaledSupplyWad, scaledSupplyWad);   // x^2
    //     uint256 quadTerm = FixedPointMathLib.mulWad(2 gwei, quadStep1);                   // coefficient * x^2
        
    //     console.log("\nStep 5: Quadratic term calculations");
    //     console.log("x^2:", quadStep1);
    //     console.log("Final quadratic term:", quadTerm);
        
    //     // Step 6: Final sum
    //     uint256 total = basePart + quarticTerm + cubicTerm + quadTerm;
    //     console.log("\nStep 6: Final sum of all terms");
    //     console.log("Total:", total);
    //     console.log("Total in ETH:", total );
        
    //     // Compare with contract calculation
    //     uint256 contractResult = token.calculateCost(testAmount);
    //     console.log("\nContract calculation result:", contractResult);
    //     console.log("Contract result in ETH:", contractResult );
    // }
}