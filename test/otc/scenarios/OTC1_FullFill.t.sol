// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {BidVault} from "../../../src/otc/BidVault.sol";

/// @notice OTC-1: seller exits at 5% discount; buyer later redeems the shares at full NAV (profit = discount).
contract OTC1_FullFill is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_SellerExitsBuyerRedeemsAtNav() public {
        uint256 id = _placeBid(bob, 500, 9500e6); // 10,000 shares at 5% off
        uint256 aliceUsdc = usdc.balanceOf(alice);

        // per-bid: the vault exists at placeBid, before any sell, holding the full escrow.
        address bvAtPlace = otc.bidVaultOf(id);
        assertTrue(bvAtPlace != address(0));
        assertEq(BidVault(bvAtPlace).escrow(), 9500e6);

        _sell(alice, 10_000e18, 1000);
        assertEq(usdc.balanceOf(alice), aliceUsdc + 9500e6); // fast exit, absorbed the 5%

        address bv = otc.bidVaultOf(id);
        assertEq(bv, bvAtPlace); // bidVaultOf is stable: same vault before and after the fill
        pruv.setPrice(1e18); // NAV unchanged
        vault.processEpoch();
        BidVault(bv).claimRedemption();
        uint256 bobUsdc = usdc.balanceOf(bob);
        vm.prank(bob);
        BidVault(bv).redeem(10_000e18);
        assertEq(usdc.balanceOf(bob), bobUsdc + 10_000e6); // full NAV -> profit = 500 USDC
    }
}
