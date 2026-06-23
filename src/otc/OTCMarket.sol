// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOTCMarket} from "../interfaces/IOTCMarket.sol";
import {IVault} from "../interfaces/IVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice See docs/07-otc-early-exit-alt1-1a-breakdown.md. Phase 0: swaps shares straight to buyers.
contract OTCMarket is IOTCMarket, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_SCAN = 100; // gas bound, mirrors Vault's per-epoch cap
    uint16 internal constant BPS = 10_000;

    IVault public immutable vault; // also the rACCESS ERC20
    IERC20 public immutable shareToken;
    IERC20 public immutable usdc;

    uint16[] internal _ladder;
    mapping(uint16 => bool) public onLadder;

    Bid[] public bids; // bidId = index
    mapping(uint16 => uint256[]) internal _book; // discountBps -> FIFO bidIds

    constructor(address vault_, MockUSDC usdc_, uint16[] memory ladder_) {
        vault = IVault(vault_);
        shareToken = IERC20(vault_);
        usdc = IERC20(address(usdc_));
        for (uint256 i = 0; i < ladder_.length; i++) {
            _ladder.push(ladder_[i]);
            onLadder[ladder_[i]] = true;
        }
    }

    modifier marketOpen() {
        if (vault.state() != IVault.State.EpochBased) revert MarketClosed();
        _;
    }

    /// @notice Returns all discount ladder tiers in basis points.
    function ladder() external view returns (uint16[] memory) {
        return _ladder;
    }

    /// @notice Returns the FIFO list of bid IDs resting at a given discount tier.
    /// @param discountBps The discount tier in basis points.
    function restingBids(uint16 discountBps) external view returns (uint256[] memory) {
        return _book[discountBps];
    }

    /// @notice Place a resting bid at a discount tier. Not yet implemented.
    function placeBid(uint16, uint256) external returns (uint256) {
        revert ZeroAmount(); // implemented in a later task
    }

    /// @notice Cancel a resting bid and reclaim escrowed USDC. Not yet implemented.
    function cancelBid(uint256) external {
        revert BidNotResting(); // implemented in a later task
    }

    /// @notice Sell shares into resting bids, cheapest discount first. Not yet implemented.
    function sell(uint256, uint16) external returns (uint256) {
        revert NoFill(); // implemented in a later task
    }

    /// @notice Close the market and refund all resting bids when vault enters WindDown. Not yet implemented.
    function closeForWindDown() external {
        revert MarketClosed(); // implemented in a later task
    }
}
