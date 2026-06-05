// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

/// @notice S8 — Wind-down with in-flight queues (spec §9 / SUMMARY §7).
/// @dev    Spec §9 says "redeem queue 5 shares"; the SUMMARY's detailed walkthrough uses 5,000.
///         We use 5,000 (the meaningful value). Pending subs are refunded; pending redeem shares are
///         returned to their owner and then settled pro-rata via the wind-down pool — equivalent in
///         value to settling the queue inline at NAV 1.0.
contract S8_WindDownMidEpoch is Fixture {
    function setUp() public {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
        pruv.setPrice(1e18);
    }

    function test_S8_WindDownSettlesInFlight() public {
        // In-flight: Alice has a 5k subscription, Bob a 5k-share redemption — both unprocessed.
        _requestDeposit(alice, 5000e6);
        _requestRedeem(bob, 5000e18);

        vault.triggerWindDown();
        assertEq(uint8(vault.state()), uint8(IVault.State.WindDown));

        // (a) sub refunded, (b)+(c) shares returned, (d) liquid + illiquid liquidated into the pool.
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 60_000e6, "5k subscription refunded");
        assertEq(vault.balanceOf(bob), 40_000e18, "redeem shares returned");
        assertEq(vault.windDownUSDC(), 100_000e6, "full NAV liquidated to pool");
        assertEq(custody.wRWABalance(), 0);
        assertEq(custody.liquidBalance(), 0);

        _claimWindDown(alice);
        _claimWindDown(bob);

        assertEq(vault.totalSupply(), 0);
        assertEq(uint8(vault.state()), uint8(IVault.State.Closed));
        // NAV 1.0 -> everyone whole.
        assertEq(usdc.balanceOf(alice), 1_000_000e6);
        assertEq(usdc.balanceOf(bob), 1_000_000e6);
    }
}
