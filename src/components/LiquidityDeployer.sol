// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (
        uint amountToken,
        uint amountETH,
        uint liquidity
    );
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
}

contract LiquidityDeployer {
    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;
    address public immutable weth;
    constructor(address _router) {
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(router.factory());
        weth = router.WETH();
    }

    function deployLiquidity(
        address tokenA,
        uint256 amountA,
        uint256 amountB
    ) public payable returns (address pair) {
        // Approve tokens
        ERC20(tokenA).approve(address(router), amountA);

        // Add liquidity
        router.addLiquidityETH{value: msg.value}(
            tokenA,
            amountA,
            amountA,
            amountB,
            address(this),
            block.timestamp
        );

        // Get pair address
        pair = factory.getPair(tokenA, weth);
        return pair;
    }
}