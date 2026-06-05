// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

/// @notice S1 — Happy path full lifecycle (spec §9). Launchpad succeeds, one matched epoch, then
///         wind-down settles everyone. At NAV 1.0 every actor ends whole.
contract S1_HappyPath is Fixture {
    function setUp() public {
        _deploy(50_000e6);
    }

    function test_S1_FullLifecycle() public {
        // --- Launchpad: 30k + 30k + 40k = 100k >= 50k min ---
        _startLaunchpad();
        _launchpadDeposit(alice, 30_000e6);
        _launchpadDeposit(bob, 30_000e6);
        _launchpadDeposit(charlie, 40_000e6);
        assertEq(vault.totalLaunchpadLocked(), 100_000e6);

        _finalizeLaunchpad();
        assertEq(uint8(vault.state()), uint8(IVault.State.EpochBased));
        assertEq(custody.wRWABalance(), 80_000e6);
        assertEq(custody.liquidBalance(), 20_000e6);
        assertEq(vault.totalSupply(), 100_000e18);

        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
        _claimLaunchpad(charlie);
        assertEq(vault.balanceOf(alice), 30_000e18);
        assertEq(vault.balanceOf(bob), 30_000e18);
        assertEq(vault.balanceOf(charlie), 40_000e18);

        // --- Epoch 0: Alice subscribes 10k, Bob redeems 5k shares, NAV unchanged ---
        uint256 aliceDep = _requestDeposit(alice, 10_000e6);
        uint256 bobRed = _requestRedeem(bob, 5000e18);

        pruv.setPrice(1e18);
        vault.processEpoch();

        // Matched 5k: Bob 5k USDC, Alice 5k matched + 5k net = 10k shares. Net sub 5k buys 4k/1k.
        assertEq(custody.wRWABalance(), 84_000e6);
        assertEq(custody.liquidBalance(), 21_000e6);
        assertEq(vault.totalSupply(), 105_000e18);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        _claim(alice, aliceDep);
        _claim(bob, bobRed);
        assertEq(vault.balanceOf(alice), 40_000e18, "Alice +10k shares");
        assertEq(usdc.balanceOf(bob) - bobUsdcBefore, 5000e6, "Bob +5k USDC");
        assertEq(vault.balanceOf(bob), 25_000e18, "Bob -5k shares");

        // --- Wind-down: liquidate everything, all holders settle pro-rata ---
        vault.triggerWindDown();
        assertEq(uint8(vault.state()), uint8(IVault.State.WindDown));

        _claimWindDown(alice);
        _claimWindDown(bob);
        _claimWindDown(charlie);

        assertEq(vault.totalSupply(), 0, "all shares burnt");
        assertEq(uint8(vault.state()), uint8(IVault.State.Closed));

        // At NAV 1.0 everyone is whole (started with 1,000,000 USDC each).
        assertEq(usdc.balanceOf(alice), 1_000_000e6);
        assertEq(usdc.balanceOf(bob), 1_000_000e6);
        assertEq(usdc.balanceOf(charlie), 1_000_000e6);
    }
}
