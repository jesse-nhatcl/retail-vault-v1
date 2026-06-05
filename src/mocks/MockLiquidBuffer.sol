// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockLiquidBuffer
/// @notice Yield-bearing liquid sleeve token (no actual yield accrues in the POC), 6 decimals to
///         match USDC so the mock AMM can swap 1:1. Mint/burn are permissionless test helpers.
contract MockLiquidBuffer is ERC20 {
    constructor() ERC20("Mock Liquid Buffer", "mLIQ") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
