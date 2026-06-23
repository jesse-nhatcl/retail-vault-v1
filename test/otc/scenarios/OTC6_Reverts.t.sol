// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../../src/interfaces/IOTCMarket.sol";

contract OTC6_Reverts is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_Revert_OffLadder() public {
        vm.startPrank(bob);
        usdc.approve(address(otc), 1000e6);
        vm.expectRevert(abi.encodeWithSelector(IOTCMarket.OffLadder.selector, uint16(300)));
        otc.placeBid(300, 1000e6);
        vm.stopPrank();
    }

    function test_Revert_SellNoFillUnderFloor() public {
        _placeBid(bob, 1000, 9000e6);
        vm.startPrank(alice);
        vault.approve(address(otc), 1000e18);
        vm.expectRevert(IOTCMarket.NoFill.selector);
        otc.sell(1000e18, 500);
        vm.stopPrank();
    }

    function test_Revert_PlaceBidAfterWindDown() public {
        vault.triggerWindDown();
        vm.startPrank(bob);
        usdc.approve(address(otc), 1000e6);
        vm.expectRevert(IOTCMarket.MarketClosed.selector);
        otc.placeBid(500, 1000e6);
        vm.stopPrank();
    }
}
