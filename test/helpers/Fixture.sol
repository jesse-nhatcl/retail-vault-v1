// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../src/Vault.sol";
import {Custody} from "../../src/Custody.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {MockLiquidBuffer} from "../../src/mocks/MockLiquidBuffer.sol";
import {MockPruv} from "../../src/mocks/MockPruv.sol";
import {MockAMM} from "../../src/mocks/MockAMM.sol";

/// @notice Shared scenario setup: 3 funded actors, deployed + wired contracts, configured launchpad.
///         The test contract is the admin/owner of both the Vault and MockPruv.
abstract contract Fixture is Test {
    MockUSDC internal usdc;
    MockLiquidBuffer internal liquid;
    MockPruv internal pruv;
    MockAMM internal amm;
    Custody internal custody;
    Vault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    uint64 internal launchStart;
    uint64 internal launchEnd;
    uint16 internal constant ILLIQUID_BPS = 8000; // 80% illiquid / 20% liquid

    function _deploy(uint256 minAmount) internal {
        usdc = new MockUSDC();
        liquid = new MockLiquidBuffer();
        pruv = new MockPruv(usdc);
        amm = new MockAMM(usdc, liquid);
        custody = new Custody(usdc, pruv, liquid, amm);
        vault = new Vault("Retail Access Vault", "rACCESS", usdc, custody);
        custody.setVault(address(vault));

        launchStart = uint64(block.timestamp + 1 days);
        launchEnd = uint64(block.timestamp + 8 days);
        vault.initLaunchpad(launchStart, launchEnd, minAmount);
        vault.configAsset(address(pruv), address(liquid), address(amm), ILLIQUID_BPS);

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(charlie, 1_000_000e6);
    }

    // ---- Launchpad helpers ----

    function _startLaunchpad() internal {
        vm.warp(launchStart);
        vault.startLaunchpad();
    }

    function _launchpadDeposit(address who, uint256 amount) internal {
        vm.startPrank(who);
        usdc.approve(address(vault), amount);
        vault.depositToLaunchpad(amount);
        vm.stopPrank();
    }

    function _finalizeLaunchpad() internal {
        vm.warp(launchEnd);
        vault.transitionAfterDeadline();
    }

    function _claimLaunchpad(address who) internal {
        vm.prank(who);
        vault.claimLaunchpadShares();
    }

    // ---- Epoch helpers ----

    function _requestDeposit(address who, uint256 amount) internal returns (uint256 id) {
        vm.startPrank(who);
        usdc.approve(address(vault), amount);
        id = vault.requestDeposit(amount);
        vm.stopPrank();
    }

    function _requestRedeem(address who, uint256 shares) internal returns (uint256 id) {
        vm.prank(who);
        id = vault.requestRedeem(shares);
    }

    function _claim(address who, uint256 id) internal {
        vm.prank(who);
        vault.claim(id);
    }

    function _claimWindDown(address who) internal {
        vm.prank(who);
        vault.claimWindDown();
    }
}
