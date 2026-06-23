// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../src/interfaces/IOTCMarket.sol";
import {OTCMarket} from "../../src/otc/OTCMarket.sol";
import {OTCFactory} from "../../src/otc/OTCFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    function test_CancelBidRefunds() public {
        uint256 id = _placeBid(bob, 500, 1000e6);
        uint256 balBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        otc.cancelBid(id);

        assertEq(usdc.balanceOf(bob), balBefore + 1000e6);
        (,, uint256 rem, IOTCMarket.BidStatus status) = otc.bids(id);
        assertEq(rem, 0);
        assertEq(uint8(status), uint8(IOTCMarket.BidStatus.Cancelled));
    }

    function test_Revert_CancelBidNotOwner() public {
        uint256 id = _placeBid(bob, 500, 1000e6);
        vm.prank(charlie);
        vm.expectRevert(IOTCMarket.NotBidOwner.selector);
        otc.cancelBid(id);
    }

    function test_Sell_FullFill_5pct() public {
        uint256 id = _placeBid(bob, 500, 9500e6); // buys exactly 10,000 shares at 5% off

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 sold = _sell(alice, 10_000e18, 1000);

        assertEq(sold, 10_000e18);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + 9500e6);
        address bv = otc.bidVaultOf(id);
        assertTrue(bv != address(0));
        assertEq(vault.balanceOf(bob), 0);
        assertEq(IERC20(address(bv)).balanceOf(bob), 10_000e18); // LP minted 1:1
        assertEq(usdc.balanceOf(address(otc)), 0);
        (,, uint256 rem, IOTCMarket.BidStatus status) = otc.bids(id);
        assertEq(rem, 0);
        assertEq(uint8(status), uint8(IOTCMarket.BidStatus.Matched));
    }

    function test_Sell_CheapestFirst() public {
        uint256 idC = _placeBid(charlie, 1000, 9000e6); // 10% bid -> should fill LAST
        uint256 idB = _placeBid(bob, 500, 4750e6); // 5% bid -> 5,000 shares, fills FIRST

        _sell(alice, 5000e18, 1000);

        assertEq(IERC20(address(otc.bidVaultOf(idB))).balanceOf(bob), 5000e18); // bob's bid filled first
        assertEq(otc.bidVaultOf(idC), address(0)); // charlie's bid untouched
    }

    function test_Sell_PartialReturnsUnsold() public {
        _placeBid(bob, 500, 4750e6); // buys 5,000 shares
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        uint256 sold = _sell(alice, 8000e18, 1000);

        assertEq(sold, 5000e18);
        assertEq(vault.balanceOf(alice), aliceSharesBefore - 5000e18); // 3,000 returned
    }

    function test_Revert_Sell_NoBidUnderFloor() public {
        _placeBid(bob, 1000, 9000e6); // only a 10% bid exists
        vm.startPrank(alice);
        vault.approve(address(otc), 1000e18);
        vm.expectRevert(IOTCMarket.NoFill.selector);
        otc.sell(1000e18, 500); // floor 5% -> 10% bid too expensive
        vm.stopPrank();
    }

    function test_Revert_ConstructorUnsortedLadder() public {
        uint16[] memory bad = new uint16[](2);
        bad[0] = 500;
        bad[1] = 100; // not ascending
        OTCFactory factory = new OTCFactory();
        vm.expectRevert(); // InvalidLadder
        new OTCMarket(address(vault), usdc, bad, factory);
    }

    function test_Sell_DeploysBidVaultAndMintsLp() public {
        uint256 id = _placeBid(bob, 500, 9500e6);
        _sell(alice, 10_000e18, 1000);
        address bv = otc.bidVaultOf(id);
        assertTrue(bv != address(0));
        assertEq(vault.balanceOf(bob), 0);
        assertEq(IERC20(address(bv)).balanceOf(bob), 10_000e18);
    }

    function test_CloseForWindDown_RefundsOpenBids() public {
        _placeBid(bob, 500, 1000e6);
        _placeBid(charlie, 1000, 2000e6);
        uint256 bobBefore = usdc.balanceOf(bob);
        uint256 charlieBefore = usdc.balanceOf(charlie);

        vault.triggerWindDown();
        otc.closeForWindDown();

        assertEq(usdc.balanceOf(bob), bobBefore + 1000e6);
        assertEq(usdc.balanceOf(charlie), charlieBefore + 2000e6);
        assertEq(usdc.balanceOf(address(otc)), 0);
    }

    function test_Revert_CloseForWindDown_WhileOpen() public {
        _placeBid(bob, 500, 1000e6);
        vm.expectRevert(); // StillOpen — vault is still EpochBased
        otc.closeForWindDown();
    }
}
