// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/Test.sol";
import {SEPEXEC404} from "../src/SEPEXEC404.sol";
import {MockCULT} from "../src/mocks/MockCULT.sol";

// Simplified interface for what we need
interface IPositionManager {
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function mint(
        MintParams calldata params
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

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
}

interface IV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract DeploySepoliaScript is Script, Test {
    function run() public returns (SEPEXEC404, MockCULT) {
        // Create merkle roots
        bytes32[] memory roots = new bytes32[](12);
        
        // First root allows our test wallet
        address testWallet = vm.envAddress("TEST_WALLET");
        roots[0] = keccak256(abi.encodePacked(bytes20(testWallet)));
        
        // Rest are placeholder roots
        for (uint i = 1; i < 12; i++) {
            roots[i] = keccak256(abi.encodePacked("day", i));
        }

        vm.startBroadcast();

        // Deploy mock CULT
        MockCULT mockCult = new MockCULT();
        console.log("MockCULT deployed at:", address(mockCult));

        // Create initial V3 liquidity pool for mock CULT/WETH
        address WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address FACTORY3 = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
        IPositionManager posManager = IPositionManager(0x1238536071E1c677A632429e3655c799b22cDA52);

        // Check if pool exists before creation
        address existingPool = IV3Factory(FACTORY3).getPool(address(mockCult), WETH, 10000);
        console.log("Existing pool check:", existingPool);

        // Approve tokens for initial liquidity
        mockCult.approve(address(posManager), 1000000 * 10**18);
        console.log("Approved PositionManager for CULT");

        // Create V3 pool with initial liquidity
        address pool = posManager.createAndInitializePoolIfNecessary(
            address(mockCult),
            WETH,
            10000, // 1% fee tier (same as in contract)
            uint160(1 << 96) // Initial sqrtPriceX96
        );
        console.log("Created V3 pool at:", pool);

        // Verify pool creation
        address verifyPool = IV3Factory(FACTORY3).getPool(address(mockCult), WETH, 10000);
        console.log("Verified pool address:", verifyPool);

        // Add initial liquidity
        IPositionManager.MintParams memory params = IPositionManager.MintParams({
            token0: address(mockCult),
            token1: WETH,
            fee: 10000,
            tickLower: -887220,
            tickUpper: 887220,
            amount0Desired: 1000000 * 10**18,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 1000
        });

        // Add liquidity
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
            posManager.mint{value: 1 ether}(params);
        
        console.log("Added liquidity:");
        console.log("- Token ID:", tokenId);
        console.log("- Liquidity:", liquidity);
        console.log("- CULT used:", amount0);
        console.log("- ETH used:", amount1);

        // Deploy SEPEXEC404 with mock CULT
        SEPEXEC404 token = new SEPEXEC404(
            roots,
            address(mockCult),
            address(0x99C5765d7F3B181e8177448A77db6fD637B61F7C) // Operator NFT address
        );
        console.log("SEPEXEC404 deployed at:", address(token));

        token.configure(
            "https://api.example.com/token/",
            "https://api.example.com/unrevealed.json",
            true
        );

        vm.stopBroadcast();

        return (token, mockCult);
    }
}