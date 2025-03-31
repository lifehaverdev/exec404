// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "solady/tokens/ERC20.sol";

contract MockCULT is ERC20 {
    constructor() ERC20() {
        _mint(msg.sender, 1000000000 * 10**18);
    }

    function name() public pure override returns (string memory) {
        return "Mock CULT";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCKCULT";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
