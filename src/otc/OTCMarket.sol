// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOTCMarket} from "../interfaces/IOTCMarket.sol";
import {IVault} from "../interfaces/IVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {OTCFactory} from "./OTCFactory.sol";
import {BidVault} from "./BidVault.sol";

/// @notice See docs/07-otc-early-exit-alt1-1a-breakdown.md. Each fill deploys a per-bid BidVault (ERC-4626-style LP) that auto-redeems the bought shares through the Vault.
contract OTCMarket is IOTCMarket, ReentrancyGuard {
    error InvalidLadder();
    error StillOpen();
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_SCAN = 100; // gas bound, mirrors Vault's per-epoch cap
    uint16 internal constant BPS = 10_000;

    IVault public immutable vault; // also the rACCESS ERC20
    IERC20 public immutable shareToken;
    IERC20 public immutable usdc;
    OTCFactory public immutable factory;

    /// @dev bidId -> the bid's single BidVault, 1:1. Set once at placeBid and never overwritten; the buyer's escrow lives inside that vault for the bid's whole life.
    mapping(uint256 => address) public bidVaultOf;

    uint16[] internal _ladder;
    mapping(uint16 => bool) public onLadder;

    Bid[] public bids; // bidId = index
    mapping(uint16 => uint256[]) internal _book; // discountBps -> FIFO bidIds

    constructor(address vault_, MockUSDC usdc_, uint16[] memory ladder_, OTCFactory factory_) {
        if (ladder_.length == 0) revert InvalidLadder();
        vault = IVault(vault_);
        shareToken = IERC20(vault_);
        usdc = IERC20(address(usdc_));
        factory = factory_;
        for (uint256 i = 0; i < ladder_.length; i++) {
            if (ladder_[i] >= BPS) revert InvalidLadder();
            if (i > 0 && ladder_[i] <= ladder_[i - 1]) revert InvalidLadder();
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

    /// @notice Sum of escrowed USDC still owed to resting bids. The USDC physically lives in each
    ///         bid's BidVault; this figure equals the sum of every resting vault's `escrow()`.
    function totalEscrowed() external view returns (uint256 sum) {
        uint256 n = bids.length;
        for (uint256 i = 0; i < n; i++) {
            if (bids[i].status == BidStatus.Resting) sum += bids[i].usdcRemaining;
        }
    }

    /// @notice Place a resting bid at a discount tier. Deploys the bid's BidVault and escrows USDC into it.
    /// @param discountBps The discount tier in basis points; must be on the fixed ladder.
    /// @param usdcIn Amount of USDC to escrow (6-dec).
    /// @return bidId The index of the newly created bid.
    function placeBid(uint16 discountBps, uint256 usdcIn) external nonReentrant marketOpen returns (uint256 bidId) {
        if (usdcIn == 0) revert ZeroAmount();
        if (!onLadder[discountBps]) revert OffLadder(discountBps);

        address bv = factory.createBidVault(address(vault), MockUSDC(address(usdc)), msg.sender);
        usdc.safeTransferFrom(msg.sender, bv, usdcIn);

        bidId = bids.length;
        bids.push(
            Bid({
                buyer: msg.sender,
                discountBps: discountBps,
                usdcRemaining: usdcIn,
                status: BidStatus.Resting,
                bidVault: bv
            })
        );
        bidVaultOf[bidId] = bv;
        _book[discountBps].push(bidId);

        emit BidPlaced(bidId, msg.sender, discountBps, usdcIn);
    }

    /// @notice Cancel a resting bid and reclaim escrowed USDC.
    /// @param bidId The ID of the bid to cancel.
    function cancelBid(uint256 bidId) external nonReentrant {
        Bid storage b = bids[bidId];
        if (b.buyer != msg.sender) revert NotBidOwner();
        if (b.status != BidStatus.Resting) revert BidNotResting();

        uint256 refundAmt = b.usdcRemaining;
        b.usdcRemaining = 0;
        b.status = BidStatus.Cancelled;
        BidVault(b.bidVault).refund(msg.sender, refundAmt);

        emit BidCancelled(bidId, refundAmt);
    }

    /// @notice Shares (18-dec) that `usdcIn` (6-dec) buys at `discountBps` off the current NAV.
    function _sharesForUsdc(uint256 usdcIn, uint16 discountBps, uint256 navNow) internal pure returns (uint256) {
        uint256 atNav = Math.mulDiv(usdcIn, 1e18, navNow);
        return Math.mulDiv(atNav, BPS, BPS - discountBps);
    }

    /// @dev Each fill creates one Vault redeem request; a single sell can consume up to MAX_SCAN of the Vault's shared per-epoch request slots (EpochQueueFull). Acceptable for the POC.
    /// @notice Sell shares into resting bids, sweeping cheapest discount first.
    /// @param shares Amount of shares (18-dec) to sell.
    /// @param maxDiscountBps Maximum discount tier the seller accepts (bids above this are skipped).
    /// @return sharesSold Shares successfully matched and transferred to buyers.
    function sell(uint256 shares, uint16 maxDiscountBps) external nonReentrant marketOpen returns (uint256 sharesSold) {
        if (shares == 0) revert ZeroAmount();
        shareToken.safeTransferFrom(msg.sender, address(this), shares);

        uint256 navNow = vault.nav();
        uint256 remaining = shares;
        uint256 usdcToSeller;
        uint256 scanned;
        bool capped;

        for (uint256 t = 0; t < _ladder.length && remaining > 0; t++) {
            uint16 d = _ladder[t];
            if (d > maxDiscountBps) break;
            uint256[] storage q = _book[d];
            for (uint256 i = 0; i < q.length && remaining > 0; i++) {
                Bid storage b = bids[q[i]];
                if (b.status != BidStatus.Resting || b.usdcRemaining == 0) continue;
                if (scanned++ >= MAX_SCAN) {
                    capped = true;
                    break;
                }

                uint256 bidShares = _sharesForUsdc(b.usdcRemaining, d, navNow);
                uint256 fill = bidShares < remaining ? bidShares : remaining;
                uint256 usdcPaid = Math.mulDiv(b.usdcRemaining, fill, bidShares);

                b.usdcRemaining -= usdcPaid;
                if (fill == bidShares) b.status = BidStatus.Matched;
                remaining -= fill;
                usdcToSeller += usdcPaid;

                BidVault bv = BidVault(b.bidVault);
                bv.payOut(msg.sender, usdcPaid); // seller paid from the bid's own escrow
                shareToken.safeTransfer(address(bv), fill); // bought shares into the bid's vault
                bv.onFill(fill); // mint LP + queue redeem for this fill
                emit BidFilled(q[i], b.buyer, fill, usdcPaid);
            }
            if (capped) break;
        }

        if (usdcToSeller == 0) revert NoFill();

        sharesSold = shares - remaining;
        if (remaining > 0) shareToken.safeTransfer(msg.sender, remaining);

        emit Sold(msg.sender, sharesSold, usdcToSeller, remaining);
    }

    /// @notice After the vault leaves EpochBased, refund every resting bid. Permissionless, idempotent.
    function closeForWindDown() external nonReentrant {
        if (vault.state() == IVault.State.EpochBased) revert StillOpen();
        uint256 count;
        uint256 n = bids.length;
        for (uint256 i = 0; i < n && i < MAX_SCAN; i++) {
            Bid storage b = bids[i];
            if (b.status == BidStatus.Resting && b.usdcRemaining > 0) {
                uint256 refundAmt = b.usdcRemaining;
                b.usdcRemaining = 0;
                b.status = BidStatus.Cancelled;
                BidVault(b.bidVault).refund(b.buyer, refundAmt);
                count++;
            }
        }
        emit MarketClosedForWindDown(count);
    }
}
