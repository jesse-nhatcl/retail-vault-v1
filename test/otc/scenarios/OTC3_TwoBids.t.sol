// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../../src/interfaces/IOTCMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BidVault} from "../../../src/otc/BidVault.sol";

/// @notice OTC-3: two bids at different discounts -> two distinct BidVaults, non-fungible LP, cheapest-first.
contract OTC3_TwoBids is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_TwoBidsTwoVaultsCheapestFirst() public {
        uint256 idB = _placeBid(bob, 500, 4750e6); // 5,000 shares @5% -> fills first
        uint256 idC = _placeBid(charlie, 1000, 9000e6); // 10,000 shares @10% -> fills next

        // per-bid: TWO distinct vaults exist at placeBid, before any sell.
        address bvB = otc.bidVaultOf(idB);
        address bvC = otc.bidVaultOf(idC);
        assertTrue(bvB != address(0));
        assertTrue(bvC != address(0));
        assertTrue(bvB != bvC); // distinct vaults, non-fungible LP
        assertEq(BidVault(bvB).escrow(), 4750e6); // full escrow before fill
        assertEq(BidVault(bvC).escrow(), 9000e6);

        _sell(alice, 8000e18, 1000); // 5,000 to bob @5%, 3,000 to charlie @10%

        // bidVaultOf is stable: same addresses after the fill.
        assertEq(otc.bidVaultOf(idB), bvB);
        assertEq(otc.bidVaultOf(idC), bvC);

        assertEq(IERC20(address(bvB)).balanceOf(bob), 5000e18);
        assertEq(IERC20(address(bvC)).balanceOf(charlie), 3000e18);

        // bob's vault fully consumed -> 0 escrow; charlie's partially filled -> 3,000 shares' worth spent.
        assertEq(BidVault(bvB).escrow(), 0);
        assertEq(BidVault(bvC).escrow(), 6300e6); // 9000 - 3000 shares * 0.90 = 9000 - 2700

        // bob's bid fully consumed -> Matched; charlie's partially filled -> still Resting
        (,,, IOTCMarket.BidStatus stB,) = otc.bids(idB);
        (,, uint256 remC, IOTCMarket.BidStatus stC,) = otc.bids(idC);
        assertEq(uint8(stB), uint8(IOTCMarket.BidStatus.Matched));
        assertEq(uint8(stC), uint8(IOTCMarket.BidStatus.Resting));
        assertGt(remC, 0);
    }

    function test_CheapestFilledFirstWhenSellingExactCheapAmount() public {
        uint256 idC = _placeBid(charlie, 1000, 9000e6); // 10% bid present (id=0)
        uint256 idB = _placeBid(bob, 500, 4750e6); // 5% bid -> 5,000 shares (id=1)

        // per-bid: both bids got a vault at placeBid, before the sell.
        address bvB = otc.bidVaultOf(idB);
        address bvC = otc.bidVaultOf(idC);
        assertTrue(bvB != address(0));
        assertTrue(bvC != address(0));

        _sell(alice, 5000e18, 1000); // exactly the 5% bid's capacity

        // bob's 5% bid filled: LP minted, escrow drained.
        assertEq(BidVault(bvB).balanceOf(bob), 5000e18);
        assertEq(BidVault(bvB).escrow(), 0);

        // charlie's 10% bid untouched: vault still has no LP and full escrow, bid still resting.
        assertEq(BidVault(bvC).balanceOf(charlie), 0);
        assertEq(BidVault(bvC).escrow(), 9000e6);
        (,, uint256 remC, IOTCMarket.BidStatus stC,) = otc.bids(idC);
        assertEq(uint8(stC), uint8(IOTCMarket.BidStatus.Resting));
        assertEq(remC, 9000e6);
    }
}
