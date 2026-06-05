// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";
import {Vault} from "../../src/Vault.sol";

/// @notice S6 — Redemption needs the illiquid fallback (spec §9).
/// @dev    The spec's literal setup (90k wRWA + 2k liquid + 100k supply + NAV 1.0) is internally
///         inconsistent (92k assets / 100k supply != 1.0). We reach an equivalent, *consistent*
///         low-liquid state by draining the buffer with a prior-epoch redemption, which preserves
///         the asserted behavior: 2,000 from Layer 2 (liquid) + 6,000 from Layer 3 (illiquid Pruv).
contract S6_IlliquidFallback is Fixture {
    function setUp() public {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
        pruv.setPrice(1e18);

        // Epoch 0: Bob redeems 18k, draining the liquid buffer 20k -> 2k. NAV stays 1.0.
        uint256 bobRed = _requestRedeem(bob, 18_000e18);
        vault.processEpoch();
        _claim(bob, bobRed);
        assertEq(custody.liquidBalance(), 2000e6, "buffer drained to 2k");
        assertEq(custody.wRWABalance(), 80_000e6);
        assertEq(vault.totalSupply(), 82_000e18);
        assertEq(vault.nav(), 1e6, "NAV consistent at 1.0");
    }

    function test_S6_FallThroughToIlliquid() public {
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 aliceRed = _requestRedeem(alice, 8000e18);

        // Expect the 3-layer split: 2,000 from liquid, 6,000 from illiquid.
        vm.expectEmit(true, false, false, true, address(vault));
        emit Vault.NetRedeemSettled(1, 8000e6, 2000e6, 6000e6);
        vault.processEpoch();

        // Layer 2 drained, Layer 3 redeemed 6,000 wRWA.
        assertEq(custody.liquidBalance(), 0, "liquid fully used");
        assertEq(custody.wRWABalance(), 74_000e6, "6,000 wRWA redeemed from Pruv");

        _claim(alice, aliceRed);
        assertEq(usdc.balanceOf(alice) - aliceUsdcBefore, 8000e6, "Alice +8,000 USDC");
        assertEq(vault.totalSupply(), 74_000e18);
    }
}
