// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockLiquidBuffer} from "../src/mocks/MockLiquidBuffer.sol";
import {MockPruv} from "../src/mocks/MockPruv.sol";
import {MockAMM} from "../src/mocks/MockAMM.sol";

/// @notice Pins the decimal convention: USDC/wRWA/liquid are 6-dec, price scaled 1e18 (parity).
contract MocksTest is Test {
    MockUSDC usdc;
    MockLiquidBuffer liquid;
    MockPruv pruv;
    MockAMM amm;

    address user = makeAddr("user");

    function setUp() public {
        usdc = new MockUSDC();
        liquid = new MockLiquidBuffer();
        pruv = new MockPruv(usdc);
        amm = new MockAMM(usdc, liquid);
    }

    function test_DecimalsAreSixExceptPrice() public view {
        assertEq(usdc.decimals(), 6);
        assertEq(liquid.decimals(), 6);
        assertEq(pruv.decimals(), 6);
        assertEq(pruv.pricePerWRWA(), 1e18); // parity
    }

    function test_PruvSubscribeAtParity() public {
        usdc.mint(user, 1000e6);
        vm.startPrank(user);
        usdc.approve(address(pruv), 1000e6);
        uint256 wOut = pruv.subscribe(1000e6);
        vm.stopPrank();

        assertEq(wOut, 1000e6, "1000 USDC -> 1000 wRWA at parity");
        assertEq(pruv.balanceOf(user), 1000e6);
    }

    function test_PruvRedeemAfterPriceUp() public {
        usdc.mint(user, 1000e6);
        vm.startPrank(user);
        usdc.approve(address(pruv), 1000e6);
        pruv.subscribe(1000e6); // 1000 wRWA
        vm.stopPrank();

        pruv.setPrice(1.1e18); // +10%

        vm.prank(user);
        uint256 usdcOut = pruv.redeem(1000e6);
        assertEq(usdcOut, 1100e6, "1000 wRWA -> 1100 USDC at 1.1x");
        assertEq(pruv.balanceOf(user), 0);
    }

    function test_AmmSwapsOneToOne() public {
        liquid.mint(user, 500e6);
        vm.prank(user);
        uint256 usdcOut = amm.swapLiquidForUSDC(500e6);
        assertEq(usdcOut, 500e6);
        assertEq(usdc.balanceOf(user), 500e6);
        assertEq(liquid.balanceOf(user), 0);

        vm.prank(user);
        uint256 liqOut = amm.swapUSDCForLiquid(500e6);
        assertEq(liqOut, 500e6);
        assertEq(liquid.balanceOf(user), 500e6);
        assertEq(usdc.balanceOf(user), 0);
    }
}
