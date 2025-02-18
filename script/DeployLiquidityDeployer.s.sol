// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {LiquidityDeployer} from "../src/LiquidityDeployer.sol";

contract DeployLiquidityDeployer is Script {
    function run() external returns (LiquidityDeployer) {
        vm.startBroadcast();
        
        // Using Uniswap V2 Router address (mainnet)
        address routerAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        
        LiquidityDeployer deployer = new LiquidityDeployer(routerAddress);
        
        vm.stopBroadcast();
        return deployer;
    }
}