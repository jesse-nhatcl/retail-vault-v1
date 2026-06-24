// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOTCMarket
/// @notice Layer-0 early-exit OTC market over rACCESS shares. Buyer-first resting bids on a
///         fixed discount ladder; a seller's `sell` sweeps them cheapest-first and settles on-chain.
interface IOTCMarket {
    enum BidStatus {
        Resting,
        Matched,
        Cancelled
    }

    struct Bid {
        address buyer;
        uint16 discountBps; // must be on the fixed ladder
        uint256 usdcRemaining; // 6-dec, escrowed; decremented as the bid is filled
        BidStatus status;
        address bidVault; // the bid's single BidVault, deployed at placeBid; holds the escrow
    }

    error OffLadder(uint16 discountBps);
    error ZeroAmount();
    error NotBidOwner();
    error BidNotResting();
    error MarketClosed(); // vault not in EpochBased
    error NoFill(); // sell() matched nothing at/under the floor

    event BidPlaced(uint256 indexed bidId, address indexed buyer, uint16 discountBps, uint256 usdcIn);
    event BidCancelled(uint256 indexed bidId, uint256 usdcRefunded);
    event Sold(address indexed seller, uint256 sharesSold, uint256 usdcReceived, uint256 sharesReturned);
    event BidFilled(uint256 indexed bidId, address indexed buyer, uint256 shares, uint256 usdcPaid);
    event MarketClosedForWindDown(uint256 bidsRefunded);

    function placeBid(uint16 discountBps, uint256 usdcIn) external returns (uint256 bidId);
    function cancelBid(uint256 bidId) external;
    function sell(uint256 shares, uint16 maxDiscountBps) external returns (uint256 sharesSold);
    function closeForWindDown() external;

    function ladder() external view returns (uint16[] memory);
    function restingBids(uint16 discountBps) external view returns (uint256[] memory);
}
