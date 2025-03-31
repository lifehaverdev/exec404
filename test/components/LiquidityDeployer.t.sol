// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {LiquidityDeployer} from "../../src/components/LiquidityDeployer.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract tokenA is ERC20 {
    string public name_;
    string public symbol_;
    uint8 public decimals_;    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name_ = _name;
        symbol_ = _symbol;
        decimals_ = _decimals;
    }

    function name() public view override returns (string memory) {
        return name_;
    }

    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract LiquidityDeployerTest is Test {
    LiquidityDeployer public deployer;
    tokenA public TokenA;
    IUniswapV2Router02 public router;
    
    function setUp() public {
        // Using Uniswap V2 Router address
        router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        
        // Deploy the liquidity deployer
        deployer = new LiquidityDeployer(address(router));
        
        // Deploy mock tokens
        TokenA = new tokenA("Token A", "TKNA", 18);
        
        // Mint tokens to the deployer
        TokenA.mint(address(deployer), 1000e18);
        vm.deal(address(deployer), 1000e18);
    }

    function testDeployLiquidity() public {
        // Deploy liquidity
        address pair = deployer.deployLiquidity{value: 100e18}(
            address(TokenA),
            100e18,
            100e18
        );
        
        // Verify pair exists
        assertTrue(pair != address(0), "Pair not created");
        
        // Verify LP tokens are owned by the deployer
        IUniswapV2Pair lpToken = IUniswapV2Pair(pair);
        assertTrue(
            lpToken.balanceOf(address(deployer)) > 0,
            "No LP tokens minted to deployer"
        );
    }
}