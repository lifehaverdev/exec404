// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {AutoLiquidityDeployer} from "../src/LPDeployer.sol";

contract DeployAutoLiquidityDeployer is Script {
    function run() public returns (AutoLiquidityDeployer) {
        vm.startBroadcast();
        
        // We'll need to pass in the token address
        AutoLiquidityDeployer deployer = new AutoLiquidityDeployer(
            "Test",
            "TEST"
        );
        
        vm.stopBroadcast();
        return deployer;
    }
}