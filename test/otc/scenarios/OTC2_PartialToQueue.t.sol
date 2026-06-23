// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

/// @notice OTC-2: only part of the lot finds buyers; the rest redeems normally at NAV.
contract OTC2_PartialToQueue is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_UnsoldGoesToQueue() public {
        _placeBid(bob, 500, 4750e6); // demand for 5,000 shares only
        uint256 sold = _sell(alice, 8000e18, 1000);
        assertEq(sold, 5000e18);

        uint256 rid = _requestRedeem(alice, 3000e18);
        pruv.setPrice(1e18);
        vault.processEpoch();
        uint256 beforeBal = usdc.balanceOf(alice);
        _claim(alice, rid);
        assertEq(usdc.balanceOf(alice), beforeBal + 3000e6);
    }
}
