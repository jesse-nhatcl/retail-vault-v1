// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../src/interfaces/IOTCMarket.sol";

contract OTCMarketTest is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_LadderConfigured() public {
        uint16[] memory l = otc.ladder();
        assertEq(l.length, 4);
        assertEq(l[0], 100);
        assertEq(l[3], 1000);
    }

    function test_PlaceBidEscrowsAndBooks() public {
        uint256 balBefore = usdc.balanceOf(bob);
        uint256 id = _placeBid(bob, 500, 1000e6);

        assertEq(id, 0);
        assertEq(usdc.balanceOf(bob), balBefore - 1000e6);
        assertEq(usdc.balanceOf(address(otc)), 1000e6);
        uint256[] memory book = otc.restingBids(500);
        assertEq(book.length, 1);
        assertEq(book[0], 0);
    }

    function test_Revert_PlaceBidZero() public {
        vm.prank(bob);
        vm.expectRevert(IOTCMarket.ZeroAmount.selector);
        otc.placeBid(500, 0);
    }

    function test_Revert_PlaceBidOffLadder() public {
        vm.startPrank(bob);
        usdc.approve(address(otc), 1000e6);
        vm.expectRevert(abi.encodeWithSelector(IOTCMarket.OffLadder.selector, uint16(300)));
        otc.placeBid(300, 1000e6);
        vm.stopPrank();
    }
}
