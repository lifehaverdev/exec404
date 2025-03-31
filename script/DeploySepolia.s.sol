// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockCULT} from "src/mocks/MockCULT.sol";
import {SEPEXEC404} from "src/SEPEXEC404.sol";

interface IWETH9 {
        function deposit() external payable;
        function approve(address spender, uint256 amount) external returns (bool);
    }

    interface IUniswapV3Pool {
        function tickSpacing() external view returns (int24);
        function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
    }

    interface IPositionManager {
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
        function mint(MintParams calldata params) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
        function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) external payable returns (address pool);
    }

    interface IUniswapV3Factory {
        function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
    }

contract DeploySepoliaScript is Script {
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address constant posManager = 0x1238536071E1c677A632429e3655c799b22cDA52;

    

    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) internal pure returns (uint160) {
        return uint160(sqrt((reserve1 << 192) / reserve0));
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) >> 1;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) >> 1;
        }
    }

    function setupRoots() internal pure returns (bytes32[] memory) {
        bytes32[] memory roots = new bytes32[](12);
        roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        roots[1] = 0xe9a7d49502aed47050e71c54456a47848d826184b52b703d5f58d51fd369fcf9;
        roots[2] = 0xd87d9eeb13a7c51bd2ea10c6b3ec1fa5b941515d8f2343979caf747a8ccbbcbe;
        roots[3] = 0x9c5fd486f6dd94f7d4cefacca2f8a610fca25d6ae3d6927f8bb77616cf1440cf;
        roots[4] = 0xacb17e4db8fff2b8e7b682710b383f1f91b40c38ce086c362d80c907649d8247;
        roots[5] = 0xf34783c0de12064f769d2be787a732db82086a672ec72b1d4fdb23cb11a1e134;
        roots[6] = 0xcef676cc60c92453554df4c8dc41dbf9fdecae37d7dbcacdb921c4ece8e6d4a5;
        roots[7] = 0xfcc23603efe9745c52e206c5bd308e333d1c4a6ef87b2c83a459572fc43512f3;
        roots[8] = 0xb57e39d073e19d1ac0d57c992173748d925e0953b3e9d1ede5b1f0653b2a6a35;
        roots[9] = 0xcb57758264ef8eeb7a060f9b7c8ffdcefcf5f791a686ed8fe17671c84cfdc3f8;
        roots[10] = 0x6e664b458778d4896e32882a564617964120e8c4f30e0d9d2f1b07a1894d5d0b;
        roots[11] = 0xc8a4a04d5cb05d354b3279b8092ad0320912674e7c4fe0f92af5accbf606d384;
        return roots;
    }

    function setupPool(MockCULT mockCult) internal returns (address pool) {
        // Check if pool exists
        pool = IUniswapV3Factory(factory).getPool(
            address(mockCult),
            WETH,
            10000
        );
        console.log("Existing pool check:", pool);

        // Create pool if it doesn't exist
        if (pool == address(0)) {
            pool = IPositionManager(posManager).createAndInitializePoolIfNecessary(
                address(mockCult),
                WETH,
                10000,
                encodePriceSqrt(1, 1)
            );
            console.log("Created V3 pool at:", pool);
        }

        // Verify pool address
        pool = IUniswapV3Factory(factory).getPool(
            address(mockCult),
            WETH,
            10000
        );
        console.log("Verified pool address:", pool);
        
        return pool;
    }

    function addLiquidity(MockCULT mockCult, address pool) internal returns (uint256 tokenId) {
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();
        
        int24 tickRange = tickSpacing * 16;
        int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;

        IPositionManager.MintParams memory params = IPositionManager.MintParams({
            token0: address(mockCult),
            token1: WETH,
            fee: 10000,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 100000 * 10**18,
            amount1Desired: 0.03 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 1000
        });

        (tokenId,,, ) = IPositionManager(posManager).mint(params);
        console.log("Added liquidity, NFT token ID:", tokenId);
        
        return tokenId;
    }

    function run() public returns (SEPEXEC404, MockCULT) {
        bytes32[] memory roots = setupRoots();
        
        vm.startBroadcast();

        MockCULT mockCult = new MockCULT();
        console.log("MockCULT deployed at:", address(mockCult));

        // Setup approvals
        mockCult.approve(address(posManager), 100000 * 10**18);
        IWETH9(WETH).approve(address(posManager), 0.03 ether);
        
        // Deposit ETH to WETH
        IWETH9(WETH).deposit{value: 0.03 ether}();
        console.log("Deposited ETH to WETH");

        // Setup pool and add liquidity
        address pool = setupPool(mockCult);
        uint256 tokenId = addLiquidity(mockCult, pool);

        // Deploy SEPEXEC404
        SEPEXEC404 token = new SEPEXEC404(
            roots,
            address(mockCult),
            address(0x99C5765d7F3B181e8177448A77db6fD637B61F7C)
        );
        console.log("SEPEXEC404 deployed at:", address(token));

        // Configure token
        token.configure(
            "https://monygroupmint.nyc3.digitaloceanspaces.com/cultexec/public/metadata/",
            "https://ms2.fun/EXEC404/unrevealed.json",
            true
        );

        vm.stopBroadcast();

        // Verify contract after broadcasting is done
        if (block.chainid == 11155111) { // Sepolia chain ID
            string[] memory commands = new string[](4);
            commands[0] = "forge";
            commands[1] = "verify-contract";
            commands[2] = vm.toString(address(token));
            commands[3] = "SEPEXEC404";
            vm.ffi(commands);
        }

        return (token, mockCult);
    }
}