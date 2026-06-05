// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";

/// @notice S7 — NAV change affects redemption value (spec §9).
///         setPrice(1.1) -> only the 80k illiquid sleeve appreciates: totalAssets = 88k + 20k = 108k,
///         NAV = 1.08. Redeeming 10 shares pays 10.8 USDC.
contract S7_NavChange is Fixture {
    function setUp() public {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
    }

    function test_S7_NavDrivesPayout() public {
        pruv.setPrice(1.1e18); // wRWA +10%

        assertEq(vault.totalAssets(), 108_000e6, "80k*1.1 + 20k");
        assertEq(vault.nav(), 1_080_000, "NAV 1.08 (scaled at 1e6 parity)");

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 id = _requestRedeem(alice, 10e18);
        vault.processEpoch();
        _claim(alice, id);

        assertEq(usdc.balanceOf(alice) - aliceUsdcBefore, 10_800_000, "10 shares * 1.08 = 10.8 USDC");
    }
}
