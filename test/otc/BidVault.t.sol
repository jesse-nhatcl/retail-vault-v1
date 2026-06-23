// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {BidVault} from "../../src/otc/BidVault.sol";

contract BidVaultTest is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_HoldsSharesMintsLpAndQueuesRedeem() public {
        // simulate the market: this test contract is the BidVault's `market`
        BidVault bv = new BidVault(address(vault), usdc, bob, 1000e18);
        vm.prank(alice);
        vault.transfer(address(bv), 1000e18); // BidVault must hold shares before initRedeem
        bv.initRedeem(); // msg.sender = this test = market

        assertEq(bv.balanceOf(bob), 1000e18); // LP minted 1:1
        assertEq(bv.shares(), 1000e18);

        pruv.setPrice(1e18);
        vault.processEpoch();
        bv.claimRedemption();
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        bv.redeem(1000e18);
        assertEq(usdc.balanceOf(bob), bobBefore + 1000e6);
    }
}
