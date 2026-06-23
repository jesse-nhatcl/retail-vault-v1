// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";
import {OTCMarket} from "../../src/otc/OTCMarket.sol";

/// @notice Reaches EpochBased with `alice` holding shares, then deploys an OTCMarket
///         with a {1%,2.5%,5%,10%} discount ladder.
abstract contract OTCFixture is Fixture {
    OTCMarket internal otc;
    uint16[] internal LADDER; // 100, 250, 500, 1000 bps

    function _setUpOTC() internal {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 100_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);

        LADDER.push(100);
        LADDER.push(250);
        LADDER.push(500);
        LADDER.push(1000);
        otc = new OTCMarket(address(vault), usdc, LADDER);
    }

    /// @notice Helper: approve and place a bid from `who`.
    /// @param  who         Bidder address.
    /// @param  discountBps Discount tier in basis points.
    /// @param  usdcIn      USDC to escrow.
    function _placeBid(address who, uint16 discountBps, uint256 usdcIn) internal returns (uint256 id) {
        vm.startPrank(who);
        usdc.approve(address(otc), usdcIn);
        id = otc.placeBid(discountBps, usdcIn);
        vm.stopPrank();
    }

    /// @notice Helper: approve and sell shares from `who`.
    /// @param  who            Seller address.
    /// @param  shares         Shares to sell.
    /// @param  maxDiscountBps Maximum acceptable discount tier.
    function _sell(address who, uint256 shares, uint16 maxDiscountBps) internal returns (uint256 sold) {
        vm.startPrank(who);
        vault.approve(address(otc), shares);
        sold = otc.sell(shares, maxDiscountBps);
        vm.stopPrank();
    }
}
