// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

/// @notice OTC-4: a buyer cancels a resting bid and reclaims the escrowed USDC.
contract OTC4_CancelBid is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_CancelRestingBidRefunds() public {
        uint256 id = _placeBid(bob, 500, 1000e6);
        uint256 beforeBal = usdc.balanceOf(bob);
        vm.prank(bob);
        otc.cancelBid(id);
        assertEq(usdc.balanceOf(bob), beforeBal + 1000e6);
        assertEq(usdc.balanceOf(address(otc)), 0);
    }
}
