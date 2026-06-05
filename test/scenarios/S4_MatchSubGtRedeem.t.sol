// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";

/// @notice S4 — Matching, subscription > redemption (PRD Case 1, spec §9).
///         Setup: 80k wRWA + 20k liquid, supply 100k, NAV 1.0.
contract S4_MatchSubGtRedeem is Fixture {
    function setUp() public {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
        // Sanity: exact S4 starting state.
        assertEq(custody.wRWABalance(), 80_000e6);
        assertEq(custody.liquidBalance(), 20_000e6);
        assertEq(vault.totalSupply(), 100_000e18);
    }

    function test_S4_Matching() public {
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        uint256 aliceDep = _requestDeposit(alice, 10_000e6);
        uint256 bobRed = _requestRedeem(bob, 4000e18);

        pruv.setPrice(1e18);
        vault.processEpoch();

        // matched = 4,000. Net sub 6,000 -> rebalance buy 4,800 illiquid + 1,200 liquid.
        assertEq(custody.wRWABalance(), 84_800e6, "buy 4,800 wRWA");
        assertEq(custody.liquidBalance(), 21_200e6, "buy 1,200 liquid");
        assertEq(vault.totalSupply(), 106_000e18);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        _claim(alice, aliceDep);
        _claim(bob, bobRed);

        assertEq(vault.balanceOf(alice) - aliceSharesBefore, 10_000e18, "Alice +10,000 shares");
        assertEq(usdc.balanceOf(bob) - bobUsdcBefore, 4000e6, "Bob +4,000 USDC");
        assertEq(vault.balanceOf(bob), 36_000e18, "Bob -4,000 shares");
        assertEq(vault.nav(), 1e6, "NAV stays 1.0");
    }
}
