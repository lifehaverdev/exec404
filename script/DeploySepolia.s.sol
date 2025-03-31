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
        // Create merkle roots array with the 12 hour roots
        bytes32[] memory roots = new bytes32[](12);
        
        // Hardcoded merkle roots for each hour
        roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;  // Hour 1
        roots[1] = 0xe9a7d49502aed47050e71c54456a47848d826184b52b703d5f58d51fd369fcf9;  // Hour 2
        roots[2] = 0xd87d9eeb13a7c51bd2ea10c6b3ec1fa5b941515d8f2343979caf747a8ccbbcbe;  // Hour 3
        roots[3] = 0x9c5fd486f6dd94f7d4cefacca2f8a610fca25d6ae3d6927f8bb77616cf1440cf;  // Hour 4
        roots[4] = 0xacb17e4db8fff2b8e7b682710b383f1f91b40c38ce086c362d80c907649d8247;  // Hour 5
        roots[5] = 0xf34783c0de12064f769d2be787a732db82086a672ec72b1d4fdb23cb11a1e134;  // Hour 6
        roots[6] = 0xcef676cc60c92453554df4c8dc41dbf9fdecae37d7dbcacdb921c4ece8e6d4a5;  // Hour 7
        roots[7] = 0xfcc23603efe9745c52e206c5bd308e333d1c4a6ef87b2c83a459572fc43512f3;  // Hour 8
        roots[8] = 0xb57e39d073e19d1ac0d57c992173748d925e0953b3e9d1ede5b1f0653b2a6a35;  // Hour 9
        roots[9] = 0xcb57758264ef8eeb7a060f9b7c8ffdcefcf5f791a686ed8fe17671c84cfdc3f8;  // Hour 10
        roots[10] = 0x6e664b458778d4896e32882a564617964120e8c4f30e0d9d2f1b07a1894d5d0b; // Hour 11
        roots[11] = 0xc8a4a04d5cb05d354b3279b8092ad0320912674e7c4fe0f92af5accbf606d384; // Hour 12

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
            amount0Desired: 100000 * 10**18,
            amount1Desired: 0.03 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 1000
        });

        // Add liquidity
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
            posManager.mint{value: 0.03 ether}(params);
        
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

        // Verify the contract
        if (block.chainid == 11155111) { // Sepolia chain ID
            bytes memory constructorArgs = abi.encode(
                roots,
                address(mockCult),
                address(0x99C5765d7F3B181e8177448A77db6fD637B61F7C)
            );

            vm.broadcast();
            string[] memory commands = new string[](4);
            commands[0] = "forge";
            commands[1] = "verify-contract";
            commands[2] = vm.toString(address(token));  // Convert address to string
            commands[3] = "SEPEXEC404";
            vm.ffi(commands);
        }

        token.configure(
            "https://monygroupmint.nyc3.digitaloceanspaces.com/cultexec/public/metadata/",
            "https://ms2.fun/EXEC404/unrevealed.json",
            true
        );

        vm.stopBroadcast();

        return (token, mockCult);
    }
}