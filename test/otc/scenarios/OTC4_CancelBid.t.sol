// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {BidVault} from "../../../src/otc/BidVault.sol";

/// @notice OTC-4: a buyer cancels a resting bid and reclaims the escrowed USDC.
contract OTC4_CancelBid is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_CancelRestingBidRefunds() public {
        uint256 id = _placeBid(bob, 500, 1000e6);
        uint256 beforeBal = usdc.balanceOf(bob);

        // per-bid: escrow lives in the bid's own vault, not the market.
        address bv = otc.bidVaultOf(id);
        assertEq(BidVault(bv).escrow(), 1000e6);
        assertEq(usdc.balanceOf(address(otc)), 0);

        vm.prank(bob);
        otc.cancelBid(id);

        // refund comes from the bid's vault; escrow drained to 0, buyer made whole.
        assertEq(usdc.balanceOf(bob), beforeBal + 1000e6);
        assertEq(BidVault(bv).escrow(), 0);
        assertEq(usdc.balanceOf(address(otc)), 0);
    }
}
