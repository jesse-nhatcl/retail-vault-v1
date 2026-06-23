// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

/// @notice OTC-1: seller exits at 5% discount; buyer later redeems the shares at full NAV (profit = discount).
contract OTC1_FullFill is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_SellerExitsBuyerRedeemsAtNav() public {
        _placeBid(bob, 500, 9500e6); // 10,000 shares at 5% off
        uint256 aliceUsdc = usdc.balanceOf(alice);

        _sell(alice, 10_000e18, 1000);
        assertEq(usdc.balanceOf(alice), aliceUsdc + 9500e6); // fast exit, absorbed the 5%

        uint256 rid = _requestRedeem(bob, 10_000e18);
        pruv.setPrice(1e18); // NAV unchanged
        vault.processEpoch();
        uint256 bobUsdc = usdc.balanceOf(bob);
        _claim(bob, rid);
        assertEq(usdc.balanceOf(bob), bobUsdc + 10_000e6); // full NAV -> profit = 500 USDC
    }
}
