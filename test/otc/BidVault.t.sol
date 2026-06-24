// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {BidVault} from "../../src/otc/BidVault.sol";
import {IBidVault} from "../../src/interfaces/IBidVault.sol";

contract BidVaultTest is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_EscrowThenFillThenRedeem() public {
        // this test contract is the BidVault's `market`
        BidVault bv = new BidVault(address(vault), usdc, bob, address(this));

        // simulate escrow
        usdc.mint(address(bv), 9500e6);
        assertEq(bv.escrow(), 9500e6);

        // pay the seller out of escrow
        uint256 aliceBefore = usdc.balanceOf(alice);
        bv.payOut(alice, 9500e6);
        assertEq(usdc.balanceOf(alice), aliceBefore + 9500e6);
        assertEq(bv.escrow(), 0);

        // give the vault shares then fill
        vm.prank(alice);
        vault.transfer(address(bv), 10_000e18);
        bv.onFill(10_000e18);
        assertEq(bv.balanceOf(bob), 10_000e18); // LP minted
        bv.redeemRequestIds(0); // index 0 exists (no revert)

        // settle
        pruv.setPrice(1e18);
        vault.processEpoch();
        bv.claimRedemption();
        assertEq(bv.proceeds(), 10_000e6);

        // redeem
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        uint256 out = bv.redeem(10_000e18);
        assertEq(out, 10_000e6);
        assertEq(usdc.balanceOf(bob), bobBefore + 10_000e6);
    }

    function test_Revert_PayOutNotMarket() public {
        BidVault bv = new BidVault(address(vault), usdc, bob, address(this));
        vm.prank(bob);
        vm.expectRevert(IBidVault.NotMarket.selector);
        bv.payOut(bob, 1);
    }

    function test_Revert_OnFillNotMarket() public {
        BidVault bv = new BidVault(address(vault), usdc, bob, address(this));
        vm.prank(bob);
        vm.expectRevert(IBidVault.NotMarket.selector);
        bv.onFill(1);
    }

    function test_Revert_RefundNotMarket() public {
        BidVault bv = new BidVault(address(vault), usdc, bob, address(this));
        vm.prank(bob);
        vm.expectRevert(IBidVault.NotMarket.selector);
        bv.refund(bob, 1);
    }
}
