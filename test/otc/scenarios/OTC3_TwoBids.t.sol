// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../../src/interfaces/IOTCMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice OTC-3: two bids at different discounts -> two distinct BidVaults, non-fungible LP, cheapest-first.
contract OTC3_TwoBids is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_TwoBidsTwoVaultsCheapestFirst() public {
        uint256 idB = _placeBid(bob, 500, 4750e6); // 5,000 shares @5% -> fills first
        uint256 idC = _placeBid(charlie, 1000, 9000e6); // 10,000 shares @10% -> fills next

        _sell(alice, 8000e18, 1000); // 5,000 to bob @5%, 3,000 to charlie @10%

        address bvB = otc.bidVaultOf(idB);
        address bvC = otc.bidVaultOf(idC);
        assertTrue(bvB != address(0));
        assertTrue(bvC != address(0));
        assertTrue(bvB != bvC); // distinct vaults, non-fungible LP

        assertEq(IERC20(address(bvB)).balanceOf(bob), 5000e18);
        assertEq(IERC20(address(bvC)).balanceOf(charlie), 3000e18);

        // bob's bid fully consumed -> Matched; charlie's partially filled -> still Resting
        (,,, IOTCMarket.BidStatus stB) = otc.bids(idB);
        (,, uint256 remC, IOTCMarket.BidStatus stC) = otc.bids(idC);
        assertEq(uint8(stB), uint8(IOTCMarket.BidStatus.Matched));
        assertEq(uint8(stC), uint8(IOTCMarket.BidStatus.Resting));
        assertGt(remC, 0);
    }

    function test_CheapestFilledFirstWhenSellingExactCheapAmount() public {
        uint256 idC = _placeBid(charlie, 1000, 9000e6); // 10% bid present (id=0)
        uint256 idB = _placeBid(bob, 500, 4750e6); // 5% bid -> 5,000 shares (id=1)

        _sell(alice, 5000e18, 1000); // exactly the 5% bid's capacity

        assertTrue(otc.bidVaultOf(idB) != address(0)); // 5% filled
        // charlie's 10% bid untouched: no vault, still resting with full escrow
        (,, uint256 remC, IOTCMarket.BidStatus stC) = otc.bids(idC);
        assertEq(uint8(stC), uint8(IOTCMarket.BidStatus.Resting));
        assertEq(remC, 9000e6);
    }
}
