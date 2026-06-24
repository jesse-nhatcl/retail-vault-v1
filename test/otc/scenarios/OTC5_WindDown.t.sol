// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {BidVault} from "../../../src/otc/BidVault.sol";

/// @notice OTC-5: wind-down refunds all resting bids; market closes.
contract OTC5_WindDown is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_WindDownRefundsOpenBids() public {
        uint256 idB = _placeBid(bob, 500, 1000e6);
        uint256 idC = _placeBid(charlie, 1000, 2000e6);
        uint256 b0 = usdc.balanceOf(bob);
        uint256 c0 = usdc.balanceOf(charlie);

        // per-bid: each resting bid escrows in its own vault.
        address bvB = otc.bidVaultOf(idB);
        address bvC = otc.bidVaultOf(idC);
        assertEq(BidVault(bvB).escrow(), 1000e6);
        assertEq(BidVault(bvC).escrow(), 2000e6);

        vault.triggerWindDown();
        otc.closeForWindDown();

        assertEq(usdc.balanceOf(bob), b0 + 1000e6);
        assertEq(usdc.balanceOf(charlie), c0 + 2000e6);
        assertEq(BidVault(bvB).escrow(), 0); // each vault's escrow refunded
        assertEq(BidVault(bvC).escrow(), 0);
        assertEq(usdc.balanceOf(address(otc)), 0);
    }

    function test_FilledBidVaultClaimableAfterWindDown() public {
        uint256 id = _placeBid(bob, 500, 9500e6);
        _sell(alice, 10_000e18, 1000); // BidVault created, redeem queued but NOT yet processed
        address bv = otc.bidVaultOf(id);

        vault.triggerWindDown(); // cancels the queued redeem, returns shares to the BidVault

        BidVault(bv).claimWindDown(); // BidVault converts returned shares to USDC via wind-down pool
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        BidVault(bv).redeem(10_000e18);
        assertEq(usdc.balanceOf(bob), bobBefore + 10_000e6); // buyer recovers value (NOT stranded)
    }
}
