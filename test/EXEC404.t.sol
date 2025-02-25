// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/DN404EXEC.sol";
import { DN404Mirror } from "dn404/src/DN404Mirror.sol";

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
    
    function setUp() public {
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
                    vm.expectRevert("Not whitelisted");  // Updated error message
                    token.buyBonding{value: maxCost}(amount, maxCost, false, emptyProof, '');
                }
                
                vm.stopPrank();
            }
        }
    }

    function testBondingEdgeCases() public {
        uint256 amount = 1000 ether;
        uint256 maxCost = 1 ether;
        bytes32[] memory proof = generateProof(0, alice);

        // Test: Can't exceed max supply
        vm.warp(token.LAUNCH_TIME());
        vm.startPrank(alice);
        vm.deal(alice, maxCost);
        uint256 tooMuch = token.MAX_SUPPLY() + 1;
        vm.expectRevert("Exceeds bonding supply");
        token.buyBonding{value: maxCost}(tooMuch, maxCost, false, proof, '');
        vm.stopPrank();

        // Test: Can't send insufficient ETH
        vm.startPrank(alice);
        vm.deal(alice, maxCost);
        uint256 cost = token.calculateCost(amount);
        vm.expectRevert("Insufficient ETH sent");
        token.buyBonding{value: cost - 1}(amount, maxCost, false, proof, '');
        vm.stopPrank();

        // Test: Can't exceed slippage
        vm.startPrank(alice);
        uint256 actualCost = token.calculateCost(amount);  // Use the contract's calculation
        vm.deal(alice, actualCost);
        uint256 lowMaxCost = actualCost - 1;
        vm.expectRevert("Slippage exceeded");
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
        token.buyBonding{value: actualCost}(amount, actualCost, true, proof, '');
        uint256 nftBalanceAfter = token.balanceOf(alice);
        
        assertTrue(nftBalanceAfter > nftBalanceBefore, "NFT minting flag should work");
        vm.stopPrank();
    }

    // Helper function to simulate bonding curve sales and deploy liquidity
    function setupLiquidityPool() internal returns (uint256 lpTokens) {
        uint256 dailyPurchaseAmount = token.MAX_SUPPLY() / 10;
        
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
        
        uint256[] memory amounts = IUniswapV2Router02(ROUTER).getAmountsOut(amountIn, path);
        
        console.log("\nSwap Details:");
        console.log("ETH in:", amountIn);
        console.log("Expected tokens out:", amounts[1]);
        
        IUniswapV2Router02(ROUTER).swapExactETHForTokens{value: amountIn}(
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
        IUniswapV2Router02(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
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
        
        IUniswapV2Router02(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
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

    function testCreateCultPosition() public {
        address user = makeAddr("cultLPProvider");
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        
        // Prepare ETH amounts
        
        // Buy CULT tokens
        IWETH(token.weth()).deposit{value: 0.005 ether}();
        IERC20(token.weth()).approve(address(token.router3()), 0.005 ether);
        
        bytes memory path = abi.encodePacked(
            token.weth(),
            uint24(10000),
            token.CULT()
        );
        
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: user,
            deadline: block.timestamp,
            amountIn: 0.005 ether,
            amountOutMinimum: 0
        });
        
        uint256 cultBought = ISwapRouter(token.router3()).exactInput(params);
        
        // Prepare for position
        IWETH(token.weth()).deposit{value: 0.005 ether}();
        
        // Calculate position range
        //address cultPool = token.factory3().getPool(token.CULT(), token.weth(), 10000);
        (,bytes memory d) = token.factory3().staticcall(abi.encodeWithSelector(0x1698ee82, token.CULT(), token.weth(), 10000));
        address cultPool = abi.decode(d, (address));
        //(, int24 currentTick,,,,, ) = IUniswapV3Pool(cultPool).slot0();
        (,bytes memory d2) = cultPool.staticcall(abi.encodeWithSelector(0x3850c7bd));
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = abi.decode(d2, (uint160,int24,uint16,uint16,uint16,uint8,bool));

        
        //int24 tickSpacing = IUniswapV3Pool(cultPool).tickSpacing();
        (,bytes memory d3) = cultPool.staticcall(abi.encodeWithSelector(0xd0c93a7c));
        int24 tickSpacing = abi.decode(d3, (int24));
        //int24 tickRange = tickSpacing * 16;
        //int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        //int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;
        
        // Approve tokens
        IERC20(token.CULT()).approve(address(token.positionManager()), cultBought);
        IERC20(token.weth()).approve(address(token.positionManager()), 0.005 ether);
        
        // Create position
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token.CULT(),
            token1: token.weth(),
            fee: 10000,
            tickLower: ((currentTick - (tickSpacing * 16)) / tickSpacing) * tickSpacing,
            tickUpper: ((currentTick + (tickSpacing * 16)) / tickSpacing) * tickSpacing,
            amount0Desired: cultBought,
            amount1Desired: 0.005 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp
        });
        
        try INonfungiblePositionManager(token.positionManager()).mint(mintParams) returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) {
            assertTrue(tokenId > 0, "Position should be created");
            assertTrue(liquidity > 0, "Position should have liquidity");
        } catch Error(string memory reason) {
            fail();
        }
        
        vm.stopPrank();
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
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 15);
            
            if(i % 2 == 0) { // Buy
                address trader = traders[i % traders.length];
                vm.startPrank(trader);
                
                address[] memory path = new address[](2);
                path[0] = WETH;
                path[1] = address(token);
                
                uint256 ethBefore = address(token).balance;
                
                try IUniswapV2Router02(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
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
                    try IUniswapV2Router02(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
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
        console.log("Total Taxes (ETH):", totalTaxes / 1 ether);
        
        // Basic assertions
        assertTrue(totalVolume > 0, "Should have non-zero volume");
        assertTrue(totalTaxes > 0, "Should have collected taxes");

        // Final state
        console.log("\n=== Final Balances ===");
        console.log("EXEC Balance:", token.balanceOf(address(token)) / 1 ether);
        console.log("ETH Balance:", address(token).balance / 1 ether);
        console.log("CULT Balance:", IERC20(token.CULT()).balanceOf(address(token)) / 1 ether);
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
                
                try IUniswapV2Router02(ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
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
                    try IUniswapV2Router02(ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
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
        */
    }

    function testCollectV3Fees() public {
        // First run market simulation to generate fees
        //uint256 initialLpTokens = setupLiquidityPool();
        testMarket(); // This generates real trading volume and fees

        // Get the position ID and manager
        uint256 positionId = token.cultV3Position();
        INonfungiblePositionManager posManager = INonfungiblePositionManager(token.positionManager());
        
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
}
