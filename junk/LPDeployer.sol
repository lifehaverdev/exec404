// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency, lessThan } from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {EmptyHook} from "./EmptyHook.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import "forge-std/Test.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract AutoLiquidityDeployer is ERC20, Test {

    // Inside the contract, add this enum
    enum Actions {
        MINT_POSITION,
        TRANSFER_POSITION,
        SETTLE_PAIR
    }

    // Basic ERC20 setup
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    IPoolManager public immutable poolManager;
    EmptyHook public hook;
    PoolKey public poolKey;
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address payable constant POSITION_MANAGER = payable(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    IPositionManager public immutable positionManager = IPositionManager(POSITION_MANAGER);
    
    
    
    
    bool public isInitialized;

    // Standard pool parameters
    uint24 private constant LP_FEE = 3000; // 0.30%
    int24 private constant TICK_SPACING = 60;
    uint160 private constant SQRT_RATIO_1_1 = 79228162514264337593543950336;

    constructor(
        string memory tokenName, 
        string memory tokenSymbol
    ) {
        _name = tokenName;
        _symbol = tokenSymbol;
        _mint(msg.sender, 1_000_000 * 10**decimals());
        hook = EmptyHook(address(0));//CounterHook(0x14b97Cb21B52F90a0B7C42416ca2C0DdE2300ac0);
    }

    function initializePool() external returns (PoolKey memory) {
        require(!isInitialized, "Pool already initialized");

        // Mint tokens to the contract itself
        _mint(address(this), 100 ether);

        // Create Currency instances
        Currency tokenCurrency = Currency.wrap(address(this));
        Currency nativeCurrency = CurrencyLibrary.ADDRESS_ZERO;

        // Sort currencies using proper comparison
        (Currency currency0, Currency currency1) = lessThan(tokenCurrency, nativeCurrency)
            ? (tokenCurrency, nativeCurrency)
            : (nativeCurrency, tokenCurrency);

        // Create the pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
        
        // Calculate proper liquidity amount
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_RATIO_1_1,
            TickMath.getSqrtPriceAtTick(-TICK_SPACING),
            TickMath.getSqrtPriceAtTick(TICK_SPACING),
            1 ether,
            1 ether
        );

        // Setup multicall parameters
        bytes[] memory params = new bytes[](2);
        
        // 1. Initialize the pool
        bytes memory hookData = new bytes(0);
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector,
            poolKey,
            SQRT_RATIO_1_1,
            hookData
        );
        
        // 2. Encode mint position parameters
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey,
            -TICK_SPACING,
            TICK_SPACING,
            liquidity,
            1 ether + 1 wei, // amount0Max with slippage
            1 ether + 1 wei, // amount1Max with slippage
            address(this),  // Contract is the recipient
            hookData
        );

        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            block.timestamp + 60
        );

        // Proper token approvals using Permit2
        // if (!lessThan(tokenCurrency, nativeCurrency)) {
        //     // If we're token1, approve this token
        //     this.approve(address(PERMIT2), type(uint256).max);
        //     PERMIT2.approve(
        //         address(this),
        //         address(positionManager),
        //         type(uint160).max,
        //         type(uint48).max
        //     );
        // }

        // Standard ERC20 approval for position manager
        if (!lessThan(tokenCurrency, nativeCurrency)) {
            // If we're token1, approve this token
            this.approve(address(positionManager), type(uint256).max);
        }

        // Make sure contract has enough ETH
        require(address(this).balance >= 1 ether, "Insufficient ETH balance");

        // Execute multicall with ETH value
        uint256 valueToPass = lessThan(nativeCurrency, tokenCurrency) ? 1 ether + 1 wei : 0;
        positionManager.multicall{value: valueToPass}(params);

        isInitialized = true;
        return poolKey;
    }

    /// @dev helper function for encoding mint liquidity operation
    function _mintLiquidityParams(
        PoolKey memory _poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(_poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(_poolKey.currency0, _poolKey.currency1);
        return (actions, params);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    // Add this function to handle NFT receipt
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // Return the function selector to indicate we can receive the NFT
        return this.onERC721Received.selector;
    }

    // Add receive() function to allow contract to receive ETH
    receive() external payable {}
}