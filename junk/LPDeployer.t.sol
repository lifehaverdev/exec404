// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {AutoLiquidityDeployer} from "../src/LPDeployer.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency, lessThan} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";

contract AutoLiquidityDeployerTest is Test {
    AutoLiquidityDeployer public token;
    IPoolManager public poolManager;
    PositionManager public positionManager;
    
    // Mainnet addresses
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address payable constant POSITION_MANAGER = payable(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);

    bool private IS_FORK;

    function setUp() public {
        try vm.envString("MAIN_RPC") returns (string memory) {
            // Fork mainnet
            vm.createSelectFork(vm.envString("MAIN_RPC"));
            IS_FORK = true;
            
            // Use existing deployed contracts
            poolManager = IPoolManager(POOL_MANAGER);
            positionManager = PositionManager(POSITION_MANAGER);

            // Deploy our token with the real pool manager
            token = new AutoLiquidityDeployer(
                "Test Token",
                "TEST"
            );
            
            // Deal some ETH to the test contract for pool creation
            vm.deal(address(token), 100 ether);
        } catch {
            IS_FORK = false;
        }
    }

    function testPoolInitialization() public {
        if (!IS_FORK) return;
        assertFalse(token.isInitialized());
        
        // No need for user setup since contract is deploying LP
        // Just ensure contract has ETH
        assertGe(address(token).balance, 1 ether, "Contract needs ETH");
        
        try token.initializePool() returns (PoolKey memory poolKey) {
            emit log_string("Success - Pool Key Details:");
            emit log_named_address("currency0", Currency.unwrap(poolKey.currency0));
            emit log_named_address("currency1", Currency.unwrap(poolKey.currency1));
            emit log_named_uint("fee", poolKey.fee);
            emit log_named_int("tickSpacing", poolKey.tickSpacing);
            emit log_named_address("hooks", address(poolKey.hooks));
            
            // Additional assertions to verify contract owns the position
            assertTrue(token.isInitialized());
        } catch Error(string memory reason) {
            emit log_string("Revert reason:");
            emit log_string(reason);
            fail();
        } catch Panic(uint256 code) {
            emit log_string("Panic code:");
            emit log_uint(code);
            fail();
        } catch (bytes memory lowLevelData) {
            emit log_string("Low level data:");
            emit log_bytes(lowLevelData);
            fail();
        }
    }

    function testPoolState() public {
        if (!IS_FORK) return;
        
        address user = makeAddr("user");
        vm.deal(user, 100 ether);
        
        vm.prank(user);
        token.initializePool();
        
        // Test initialized state
        (
            Currency currency0,
            Currency currency1,
            uint24 fee,
            int24 tickSpacing,
            IHooks hooks
        ) = token.poolKey();

        // Verify the pool parameters
        assertTrue(
            lessThan(currency0, currency1),
            "Currencies should be properly ordered"
        );
        assertEq(fee, 3000);
        assertEq(tickSpacing, 60);
        assertEq(address(hooks), address(0)); // Using empty hook
    }

    function testCannotInitializeTwice() public {
        if (!IS_FORK) return;
        
        address user = makeAddr("user");
        vm.deal(user, 100 ether);
        
        vm.prank(user);
        token.initializePool();
        
        vm.prank(user);
        vm.expectRevert("Pool already initialized");
        token.initializePool();
    }

    // Helper function to get a fresh token deployment
    function deployNewToken(string memory name, string memory symbol) internal returns (AutoLiquidityDeployer) {
        return new AutoLiquidityDeployer(
            name,
            symbol
        );
    }
}
