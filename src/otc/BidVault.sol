// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBidVault} from "../interfaces/IBidVault.sol";
import {IVault} from "../interfaces/IVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice One per OTC bid. Holds the buyer's escrowed USDC, accumulates bought shares across fills,
///         mints a single LP token to the buyer, and redeems the shares through the core Vault.
contract BidVault is IBidVault, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable market;
    IVault public immutable vault;
    IERC20 public immutable usdc;
    address public immutable buyer;

    uint256 internal constant MAX_CLAIM = 100; // per-call claim cap (mirrors the 100-iteration convention)

    uint256[] public redeemRequestIds; // one per fill
    uint256 public nextClaimIndex; // forward cursor into redeemRequestIds
    uint256 public proceeds; // settled USDC received from the Vault; only this is redeemable

    constructor(address vault_, MockUSDC usdc_, address buyer_, address market_) ERC20("OTC BidVault LP", "otcLP") {
        vault = IVault(vault_);
        usdc = IERC20(address(usdc_));
        buyer = buyer_;
        market = market_;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert NotMarket();
        _;
    }

    /// @notice Returns the USDC still escrowed (unfilled) backing the open part of the bid.
    /// @return The escrowed USDC = total balance minus already-settled proceeds.
    function escrow() external view returns (uint256) {
        return usdc.balanceOf(address(this)) - proceeds;
    }

    /// @notice Market-only: pay the seller out of escrow on a fill.
    /// @param to     Recipient (the seller).
    /// @param amount USDC to transfer.
    function payOut(address to, uint256 amount) external onlyMarket nonReentrant {
        usdc.safeTransfer(to, amount);
        emit PaidOut(to, amount);
    }

    /// @notice Market-only: refund escrowed USDC on cancel or wind-down.
    /// @param to     Recipient (the buyer).
    /// @param amount USDC to transfer.
    function refund(address to, uint256 amount) external onlyMarket nonReentrant {
        usdc.safeTransfer(to, amount);
        emit Refunded(to, amount);
    }

    /// @notice Market-only: mint LP for this fill and queue a redeem of the bought shares.
    /// @param shares Vault shares (18-dec) acquired in this fill.
    function onFill(uint256 shares) external onlyMarket nonReentrant {
        _mint(buyer, shares);
        uint256 id = vault.requestRedeem(shares);
        redeemRequestIds.push(id);
        emit Filled(shares, id);
    }

    /// @notice Claim NAV USDC for settled fills, bounded to MAX_CLAIM per call. Stops at the first
    ///         not-yet-settled request (later fills are in non-decreasing epochs, so also unsettled).
    ///         Permissionless; call repeatedly until `nextClaimIndex == redeemRequestIds.length`.
    function claimRedemption() external nonReentrant {
        uint256 before = usdc.balanceOf(address(this));
        uint256 n = redeemRequestIds.length;
        uint256 end = nextClaimIndex + MAX_CLAIM;
        if (end > n) end = n;
        uint256 i = nextClaimIndex;
        for (; i < end; i++) {
            try vault.claim(redeemRequestIds[i]) {}
            catch {
                break;
            }
        }
        nextClaimIndex = i;
        uint256 received = usdc.balanceOf(address(this)) - before;
        proceeds += received;
        emit RedemptionClaimed(received);
    }

    /// @notice Recover value via the Vault's wind-down pool into the redeemable proceeds pool.
    function claimWindDown() external nonReentrant {
        uint256 before = usdc.balanceOf(address(this));
        vault.claimWindDown();
        uint256 received = usdc.balanceOf(address(this)) - before;
        proceeds += received;
        emit RedemptionClaimed(received);
    }

    /// @notice Burn `lp` LP tokens for a pro-rata share of the redeemable proceeds.
    /// @param  lp      LP tokens to burn.
    /// @return usdcOut USDC paid to the caller.
    function redeem(uint256 lp) external nonReentrant returns (uint256 usdcOut) {
        if (lp == 0 || balanceOf(msg.sender) < lp) revert NothingToClaim();
        usdcOut = Math.mulDiv(proceeds, lp, totalSupply());
        if (usdcOut == 0) revert NothingToClaim();
        _burn(msg.sender, lp);
        proceeds -= usdcOut;
        usdc.safeTransfer(msg.sender, usdcOut);
        emit LpRedeemed(msg.sender, lp, usdcOut);
    }
}
