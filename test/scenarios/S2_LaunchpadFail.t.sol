// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

/// @notice S2 — Launchpad fails (below min) and the sole depositor is refunded in full (spec §9).
contract S2_LaunchpadFail is Fixture {
    function setUp() public {
        _deploy(50_000e6);
    }

    function test_S2_FailAndRefund() public {
        _startLaunchpad();
        _launchpadDeposit(alice, 30_000e6); // 30k < 50k min
        _finalizeLaunchpad();

        assertEq(uint8(vault.state()), uint8(IVault.State.LaunchpadFail));

        vm.prank(alice);
        vault.refundLaunchpad();

        assertEq(usdc.balanceOf(alice), 1_000_000e6, "USDC fully restored");
        assertEq(vault.totalLaunchpadLocked(), 0);
        assertEq(custody.wRWABalance(), 0);
        assertEq(custody.liquidBalance(), 0);
        assertEq(custody.usdcBalance(), 0);
    }
}
