// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/components/Bonding.sol";

contract DeployBonding is Script {
    function run() external returns (Bonding bondingContract) {
        vm.startBroadcast();
        bondingContract = new Bonding();
        vm.stopBroadcast();
        return bondingContract;
    }
}