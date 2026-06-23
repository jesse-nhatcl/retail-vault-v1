// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

/// @notice OTC-5: wind-down refunds all resting bids; market closes.
contract OTC5_WindDown is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_WindDownRefundsOpenBids() public {
        _placeBid(bob, 500, 1000e6);
        _placeBid(charlie, 1000, 2000e6);
        uint256 b0 = usdc.balanceOf(bob);
        uint256 c0 = usdc.balanceOf(charlie);

        vault.triggerWindDown();
        otc.closeForWindDown();

        assertEq(usdc.balanceOf(bob), b0 + 1000e6);
        assertEq(usdc.balanceOf(charlie), c0 + 2000e6);
        assertEq(usdc.balanceOf(address(otc)), 0);
    }
}
