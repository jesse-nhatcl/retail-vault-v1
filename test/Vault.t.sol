// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {Custody} from "../src/Custody.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {INavSource} from "../src/interfaces/INavSource.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockLiquidBuffer} from "../src/mocks/MockLiquidBuffer.sol";
import {MockPruv} from "../src/mocks/MockPruv.sol";
import {MockAMM} from "../src/mocks/MockAMM.sol";

/// @notice Unit tests for Vault: state machine guards, launchpad mechanics, queue + cancel,
///         access control. Epoch math is covered end-to-end by test/scenarios/S*.
contract VaultTest is Test {
    MockUSDC usdc;
    MockLiquidBuffer liquid;
    MockPruv pruv;
    MockAMM amm;
    Custody custody;
    Vault vault;

    address admin = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint64 start;
    uint64 end;
    uint256 constant MIN = 50_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        liquid = new MockLiquidBuffer();
        pruv = new MockPruv(usdc);
        amm = new MockAMM(usdc, liquid);
        custody = new Custody(usdc, pruv, liquid, amm);
        vault = new Vault("Retail Access Vault", "rACCESS", usdc, custody);
        custody.setVault(address(vault));
        pruv.transferOwnership(address(this));

        start = uint64(block.timestamp + 1 days);
        end = uint64(block.timestamp + 8 days);
        vault.initLaunchpad(start, end, MIN);
        vault.configAsset(address(pruv), address(liquid), address(amm), 8000);

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
    }

    function _enterLaunchpad() internal {
        vm.warp(start);
        vault.startLaunchpad();
    }

    function _deposit(address who, uint256 amt) internal {
        vm.startPrank(who);
        usdc.approve(address(vault), amt);
        vault.depositToLaunchpad(amt);
        vm.stopPrank();
    }

    // ---- State machine ----

    function test_InitialState() public view {
        assertEq(uint8(vault.state()), uint8(IVault.State.Initialized));
    }

    function test_ConfigOnlyInInitialized() public {
        _enterLaunchpad();
        vm.expectRevert(Vault.InvalidState.selector);
        vault.configAsset(address(pruv), address(liquid), address(amm), 8000);
    }

    function test_StartLaunchpadRequiresStartTime() public {
        vm.expectRevert(Vault.LaunchpadNotStarted.selector);
        vault.startLaunchpad();
    }

    function test_DepositRequiresLaunchpadState() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 10_000e6);
        vm.expectRevert(Vault.InvalidState.selector);
        vault.depositToLaunchpad(10_000e6);
        vm.stopPrank();
    }

    // ---- Launchpad success ----

    function test_LaunchpadSuccessBuysAssetsAndMintsSupply() public {
        _enterLaunchpad();
        _deposit(alice, 30_000e6);
        _deposit(bob, 70_000e6);
        assertEq(vault.totalLaunchpadLocked(), 100_000e6);

        vm.warp(end);
        vault.transitionAfterDeadline();

        assertEq(uint8(vault.state()), uint8(IVault.State.EpochBased));
        assertEq(custody.wRWABalance(), 80_000e6, "80% illiquid");
        assertEq(custody.liquidBalance(), 20_000e6, "20% liquid");
        assertEq(custody.usdcBalance(), 0);
        assertEq(vault.totalSupply(), 100_000e18, "1 share per USDC, 18-dec");
        assertEq(vault.totalAssets(), 100_000e6);
    }

    function test_ClaimLaunchpadSharesProRata() public {
        _enterLaunchpad();
        _deposit(alice, 30_000e6);
        _deposit(bob, 70_000e6);
        vm.warp(end);
        vault.transitionAfterDeadline();

        vm.prank(alice);
        vault.claimLaunchpadShares();
        vm.prank(bob);
        vault.claimLaunchpadShares();

        assertEq(vault.balanceOf(alice), 30_000e18);
        assertEq(vault.balanceOf(bob), 70_000e18);
    }

    function test_CannotClaimLaunchpadTwice() public {
        _enterLaunchpad();
        _deposit(alice, 60_000e6);
        vm.warp(end);
        vault.transitionAfterDeadline();
        vm.startPrank(alice);
        vault.claimLaunchpadShares();
        vm.expectRevert(Vault.NothingToClaim.selector);
        vault.claimLaunchpadShares();
        vm.stopPrank();
    }

    // ---- Launchpad fail ----

    function test_LaunchpadFailAndRefund() public {
        _enterLaunchpad();
        _deposit(alice, 30_000e6);
        vm.warp(end);
        vault.transitionAfterDeadline();
        assertEq(uint8(vault.state()), uint8(IVault.State.LaunchpadFail));

        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.refundLaunchpad();
        assertEq(usdc.balanceOf(alice), before + 30_000e6);
        assertEq(vault.totalLaunchpadLocked(), 0);
    }

    function test_TransitionRequiresDeadline() public {
        _enterLaunchpad();
        _deposit(alice, 60_000e6);
        vm.expectRevert(Vault.LaunchpadNotEnded.selector);
        vault.transitionAfterDeadline();
    }

    // ---- Epoch queue + cancel ----

    function _toEpoch() internal {
        _enterLaunchpad();
        _deposit(alice, 60_000e6);
        _deposit(bob, 40_000e6);
        vm.warp(end);
        vault.transitionAfterDeadline();
        vm.prank(alice);
        vault.claimLaunchpadShares();
        vm.prank(bob);
        vault.claimLaunchpadShares();
    }

    function test_RequestDepositLocksUSDC() public {
        _toEpoch();
        vm.startPrank(alice);
        usdc.approve(address(vault), 10_000e6);
        uint256 id = vault.requestDeposit(10_000e6);
        vm.stopPrank();
        assertEq(id, 0);
        assertEq(vault.pendingSubAmount(alice), 10_000e6);
        assertEq(usdc.balanceOf(address(vault)), 10_000e6);
    }

    function test_RequestRedeemLocksShares() public {
        _toEpoch();
        vm.prank(bob);
        uint256 id = vault.requestRedeem(5000e18);
        assertEq(vault.pendingRedeemShares(bob), 5000e18);
        assertEq(vault.balanceOf(address(vault)), 5000e18);
        assertEq(id, 0);
    }

    function test_CancelDepositRefundsUSDC() public {
        _toEpoch();
        vm.startPrank(alice);
        usdc.approve(address(vault), 10_000e6);
        uint256 id = vault.requestDeposit(10_000e6);
        uint256 before = usdc.balanceOf(alice);
        vault.cancelRequest(id);
        vm.stopPrank();
        assertEq(usdc.balanceOf(alice), before + 10_000e6);
        assertEq(vault.pendingSubAmount(alice), 0);
    }

    function test_CancelRedeemReturnsShares() public {
        _toEpoch();
        vm.startPrank(bob);
        uint256 id = vault.requestRedeem(5000e18);
        vault.cancelRequest(id);
        vm.stopPrank();
        assertEq(vault.balanceOf(bob), 40_000e18);
        assertEq(vault.pendingRedeemShares(bob), 0);
    }

    function test_CannotCancelOthersRequest() public {
        _toEpoch();
        vm.startPrank(alice);
        usdc.approve(address(vault), 10_000e6);
        uint256 id = vault.requestDeposit(10_000e6);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(Vault.NotRequestOwner.selector);
        vault.cancelRequest(id);
    }

    // ---- NAV source seam ----

    function test_NavReadThroughInterfaceSeam() public view {
        // Vault reads NAV through the narrow INavSource interface, not a concrete fund type,
        // so the price source can later be swapped (real Pruv feed / oracle) without touching Vault.
        INavSource source = vault.navSource();
        assertEq(address(source), address(pruv));
        assertEq(source.pricePerWRWA(), pruv.pricePerWRWA());
    }

    // ---- Access control ----

    function test_ProcessEpochOnlyOwner() public {
        _toEpoch();
        vm.prank(alice);
        vm.expectRevert();
        vault.processEpoch();
    }

    function test_TriggerWindDownOnlyOwner() public {
        _toEpoch();
        vm.prank(alice);
        vm.expectRevert();
        vault.triggerWindDown();
    }
}
