// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MockUSDC} from "./MockUSDC.sol";
import {MockLiquidBuffer} from "./MockLiquidBuffer.sol";

/// @title MockAMM
/// @notice Fixed 1:1 swap between the liquid buffer token and USDC. Both tokens are 6-decimal, so
///         swaps are value-preserving with no slippage. Burns the input side and mints the output
///         side (mock convenience — no reserves to manage). Stands in for the deferred Curve pool.
contract MockAMM {
    MockUSDC public immutable usdc;
    MockLiquidBuffer public immutable liquid;

    event SwapLiquidForUSDC(address indexed account, uint256 amount);
    event SwapUSDCForLiquid(address indexed account, uint256 amount);

    constructor(MockUSDC _usdc, MockLiquidBuffer _liquid) {
        usdc = _usdc;
        liquid = _liquid;
    }

    /// @notice Swap `amount` liquid buffer tokens (from caller) for an equal amount of USDC.
    function swapLiquidForUSDC(uint256 amount) external returns (uint256 usdcOut) {
        liquid.burn(msg.sender, amount);
        usdc.mint(msg.sender, amount);
        usdcOut = amount;
        emit SwapLiquidForUSDC(msg.sender, amount);
    }

    /// @notice Swap `amount` USDC (from caller) for an equal amount of liquid buffer tokens.
    function swapUSDCForLiquid(uint256 amount) external returns (uint256 liquidOut) {
        usdc.burn(msg.sender, amount);
        liquid.mint(msg.sender, amount);
        liquidOut = amount;
        emit SwapUSDCForLiquid(msg.sender, amount);
    }
}
