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
        //V1 Roots
        // roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        // roots[1] = 0xe9a7d49502aed47050e71c54456a47848d826184b52b703d5f58d51fd369fcf9;
        // roots[2] = 0xd87d9eeb13a7c51bd2ea10c6b3ec1fa5b941515d8f2343979caf747a8ccbbcbe;
        // roots[3] = 0x9c5fd486f6dd94f7d4cefacca2f8a610fca25d6ae3d6927f8bb77616cf1440cf;
        // roots[4] = 0xacb17e4db8fff2b8e7b682710b383f1f91b40c38ce086c362d80c907649d8247;
        // roots[5] = 0xf34783c0de12064f769d2be787a732db82086a672ec72b1d4fdb23cb11a1e134;
        // roots[6] = 0xcef676cc60c92453554df4c8dc41dbf9fdecae37d7dbcacdb921c4ece8e6d4a5;
        // roots[7] = 0xfcc23603efe9745c52e206c5bd308e333d1c4a6ef87b2c83a459572fc43512f3;
        // roots[8] = 0xb57e39d073e19d1ac0d57c992173748d925e0953b3e9d1ede5b1f0653b2a6a35;
        // roots[9] = 0xcb57758264ef8eeb7a060f9b7c8ffdcefcf5f791a686ed8fe17671c84cfdc3f8;
        // roots[10] = 0x6e664b458778d4896e32882a564617964120e8c4f30e0d9d2f1b07a1894d5d0b;
        // roots[11] = 0xc8a4a04d5cb05d354b3279b8092ad0320912674e7c4fe0f92af5accbf606d384;
        //v2 roots no delegation
        // roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        // roots[1] = 0xba4c7683fe9a03ebb8b98aa2f5672f2bbb13f08938df935f5ead42d0641cedec;
        // roots[2] = 0x56273724a5fe98e289169d65d26ab0b41d5086070ab3680f223395fa2e88e0ac;
        // roots[3] = 0xc8407bfa46ff866d4de05f1a8cfb52adadfb145f0b32b6cb46bc3855f388e209;
        // roots[4] = 0x3318b27514a6cfc186d0b5c187eb328b12603d37ded3c69d214b555294714598;
        // roots[5] = 0xe07ab75c7f20829e490bef5971962417d8e118fb690d27afe641422c25976d95;
        // roots[6] = 0xef4cc785c4cb2c95da781f39848239fdf47f762d3a450a0611386b0a49f3c59c;
        // roots[7] = 0x4e34169c0ae4e58c595fc244e9b4dcbb130cd85358c57bfefa875237f0833db2;
        // roots[8] = 0x26df5fc69123c0c8c899d776332602d792c717606be4fb5798a3d337eda1cc39;
        // roots[9] = 0xe8746cad9f4dba5feac1c8ce05f6a9f4eaf0014d252e2eaf872aa1338fe0e17d;
        // roots[10] = 0x088bfbc026984de05dc754bc59278e143c10f6d0316c08dd1494fc7112e961e1;
        // roots[11] = 0x4989e05b0243e27ad49e29ba0858edfdd8eaa5bff24d08468ff99af05d3ba05d;
        //v2 roots with delegation
        roots[0] = 0x383d484216d93fbbe5a6b58dc16fcda0abb4b5dc25ebbe822686016bda173de8;
        roots[1] = 0x3e755dd64a20ad8829a7f6e1a1df65199a80edc6a500ad0539a4363d623d8429;
        roots[2] = 0xe80a9245200ccbb7e5b8db4a18e354b19574011806e9aac4b3f048c7aa5e281b;
        roots[3] = 0x1dd1fb00acb2042a46ad691a058ec2cdf6e11cb401bb907f10c49071daec8e3d;
        roots[4] = 0x3721ea94d93df2cc9785ffbb0bde71c3495747976119135bcb808b9fd2b148a9;
        roots[5] = 0xc219477ca23adcb4650364be87505596afec465e1320d1fbc534ce6837764349;
        roots[6] = 0xff275b7b05a174b48b33d14bfeb6ac1a63bf44474054887d2fb40ad3110f4e56;
        roots[7] = 0xf7e95a2d1b84642fbc76572eb7e7be51acc71ffb467c04a82d9363b1d3a5f4ae;
        roots[8] = 0xcd962b225230f743505494ce5befdc43bb95039d9cf9cd85e31ab7998c7752bd;
        roots[9] = 0xea0bd929aa9d311b2eb540ad17f8de71cfd8e517a3b561828c8003834ea712d6;
        roots[10] = 0x67125b79075bb36b2be9c1731becda51087a8010418b21af3183e1cbd50880e0;
        roots[11] = 0xa248a94675ab4dbeed416e131c3cb0f1d7be803c5e914dfbe20fe2216fde7034;
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

        //MockCULT mockCult = new MockCULT();
        //console.log("MockCULT deployed at:", address(mockCult));
        MockCULT mockCult = MockCULT(0x813b4b53Adea0Dc81b4421b1468585560eCa153C);

        // Setup approvals
        //mockCult.approve(address(posManager), 100000 * 10**18);
        //IWETH9(WETH).approve(address(posManager), 0.03 ether);
        
        // Deposit ETH to WETH
        //IWETH9(WETH).deposit{value: 0.03 ether}();
        //console.log("Deposited ETH to WETH");

        // Setup pool and add liquidity
        //address pool = setupPool(mockCult);
        //uint256 tokenId = addLiquidity(mockCult, pool);

        // Deploy SEPEXEC404
        SEPEXEC404 token = new SEPEXEC404(
            roots,
            address(mockCult),
            address(0x99C5765d7F3B181e8177448A77db6fD637B61F7C) //cola bottles
        );
        console.log("SEPEXEC404 deployed at:", address(token));

        // Configure token
        token.configure(
            "https://monygroupmint.nyc3.digitaloceanspaces.com/exectest/public/metadata/",
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