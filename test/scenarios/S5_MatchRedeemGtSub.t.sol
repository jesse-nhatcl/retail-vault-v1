// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";

/// @notice S5 — Matching, redemption > subscription (PRD Case 2, spec §9).
///         Net redemption is covered entirely by the liquid buffer (Layer 2); no illiquid touch.
contract S5_MatchRedeemGtSub is Fixture {
    function setUp() public {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
        assertEq(custody.wRWABalance(), 80_000e6);
        assertEq(custody.liquidBalance(), 20_000e6);
        assertEq(vault.totalSupply(), 100_000e18);
    }

    function test_S5_Matching() public {
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        uint256 aliceDep = _requestDeposit(alice, 4000e6);
        uint256 bobRed = _requestRedeem(bob, 10_000e18);

        pruv.setPrice(1e18);
        vault.processEpoch();

        // matched 4,000; net redeem 6,000 from liquid buffer (20k -> 14k). No illiquid touch.
        assertEq(custody.wRWABalance(), 80_000e6, "illiquid untouched");
        assertEq(custody.liquidBalance(), 14_000e6, "liquid 20k -> 14k");
        assertEq(vault.totalSupply(), 94_000e18);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        _claim(alice, aliceDep);
        _claim(bob, bobRed);

        assertEq(vault.balanceOf(alice) - aliceSharesBefore, 4000e18, "Alice +4,000 shares");
        assertEq(usdc.balanceOf(bob) - bobUsdcBefore, 10_000e6, "Bob +10,000 USDC (4k match + 6k liquid)");
        assertEq(vault.balanceOf(bob), 30_000e18, "Bob -10,000 shares");
    }
}
