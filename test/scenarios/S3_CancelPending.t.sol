// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";

/// @notice S3 — ERC-7887 cancel of a pending subscription before processEpoch (spec §9).
///         After cancel the epoch processes as a no-op.
contract S3_CancelPending is Fixture {
    function setUp() public {
        _deploy(50_000e6);
    }

    function _reachEpoch() internal {
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
    }

    function test_S3_CancelThenNoOpEpoch() public {
        _reachEpoch();
        uint256 supplyBefore = vault.totalSupply();

        uint256 id = _requestDeposit(alice, 10_000e6);
        assertEq(vault.pendingSubAmount(alice), 10_000e6);
        assertEq(usdc.balanceOf(address(vault)), 10_000e6);

        vm.prank(alice);
        vault.cancelRequest(id);

        assertEq(vault.pendingSubAmount(alice), 0);
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 60_000e6, "10k deposit refunded");
        assertEq(usdc.balanceOf(address(vault)), 0);

        // Epoch processes as a no-op.
        pruv.setPrice(1e18);
        vault.processEpoch();

        assertEq(vault.totalSupply(), supplyBefore, "no supply change");
        assertEq(vault.currentEpoch(), 1);
        assertEq(custody.wRWABalance(), 80_000e6);
        assertEq(custody.liquidBalance(), 20_000e6);
    }
}
