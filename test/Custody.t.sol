// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Custody} from "../src/Custody.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockLiquidBuffer} from "../src/mocks/MockLiquidBuffer.sol";
import {MockPruv} from "../src/mocks/MockPruv.sol";
import {MockAMM} from "../src/mocks/MockAMM.sol";

/// @notice Unit tests for Custody. The test contract itself plays the role of the Vault.
contract CustodyTest is Test {
    MockUSDC usdc;
    MockLiquidBuffer liquid;
    MockPruv pruv;
    MockAMM amm;
    Custody custody;

    address attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        liquid = new MockLiquidBuffer();
        pruv = new MockPruv(usdc);
        amm = new MockAMM(usdc, liquid);
        custody = new Custody(usdc, pruv, liquid, amm);
        custody.setVault(address(this)); // test acts as the Vault
    }

    function test_SetVaultOnlyOnce() public {
        vm.expectRevert(Custody.VaultAlreadySet.selector);
        custody.setVault(attacker);
    }

    function test_OnlyVaultGate() public {
        vm.prank(attacker);
        vm.expectRevert(Custody.NotVault.selector);
        custody.withdrawUSDC(attacker, 1);
    }

    function test_DepositUSDC_PullsFromVault() public {
        usdc.mint(address(this), 10_000e6);
        usdc.approve(address(custody), 10_000e6);
        custody.depositUSDC(10_000e6);
        assertEq(custody.usdcBalance(), 10_000e6);
    }

    function test_SubscribeToPruv() public {
        usdc.mint(address(custody), 8000e6);
        uint256 wOut = custody.subscribeToPruv(8000e6);
        assertEq(wOut, 8000e6, "parity");
        assertEq(custody.wRWABalance(), 8000e6);
        assertEq(custody.usdcBalance(), 0);
    }

    function test_RedeemFromPruv() public {
        usdc.mint(address(custody), 8000e6);
        custody.subscribeToPruv(8000e6); // now holds 8000 wRWA
        uint256 out = custody.redeemFromPruv(3000e6);
        assertEq(out, 3000e6);
        assertEq(custody.wRWABalance(), 5000e6);
        assertEq(custody.usdcBalance(), 3000e6);
    }

    function test_SwapUSDCForLiquidAndBack() public {
        usdc.mint(address(custody), 2000e6);
        uint256 liqOut = custody.swapUSDCForLiquid(2000e6);
        assertEq(liqOut, 2000e6);
        assertEq(custody.liquidBalance(), 2000e6);
        assertEq(custody.usdcBalance(), 0);

        uint256 usdcOut = custody.swapLiquidForUSDC(1500e6);
        assertEq(usdcOut, 1500e6);
        assertEq(custody.liquidBalance(), 500e6);
        assertEq(custody.usdcBalance(), 1500e6);
    }

    function test_WithdrawUSDC() public {
        usdc.mint(address(custody), 5000e6);
        custody.withdrawUSDC(attacker, 2000e6);
        assertEq(usdc.balanceOf(attacker), 2000e6);
        assertEq(custody.usdcBalance(), 3000e6);
    }
}
