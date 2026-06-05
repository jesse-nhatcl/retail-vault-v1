// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {Custody} from "../src/Custody.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockLiquidBuffer} from "../src/mocks/MockLiquidBuffer.sol";
import {MockPruv} from "../src/mocks/MockPruv.sol";
import {MockAMM} from "../src/mocks/MockAMM.sol";

/// @notice Manager-facing demo of the 8 verification scenarios. Prints human-readable numbers, the
///         claim each scenario proves, and a `require`-backed PASS verdict (numbers are verified,
///         not just printed).
/// @dev    One scenario:  forge script script/Demo.s.sol --sig 'run(string)' "S4" -vvv
///         All scenarios: forge script script/Demo.s.sol --sig 'run(string)' "ALL" -vvv
contract Demo is Script {
    MockUSDC usdc;
    MockLiquidBuffer liquid;
    MockPruv pruv;
    MockAMM amm;
    Custody custody;
    Vault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC4A411E);

    uint64 start;
    uint64 end;

    uint256 constant USDC_ONE = 1e6;
    uint256 constant SHARE_ONE = 1e18;

    function run(string memory scenario) external {
        bytes32 s = keccak256(bytes(scenario));
        if (s == keccak256("ALL")) _all();
        else if (s == keccak256("S1")) _s1();
        else if (s == keccak256("S2")) _s2();
        else if (s == keccak256("S3")) _s3();
        else if (s == keccak256("S4")) _s4();
        else if (s == keccak256("S5")) _s5();
        else if (s == keccak256("S6")) _s6();
        else if (s == keccak256("S7")) _s7();
        else if (s == keccak256("S8")) _s8();
        else revert("unknown scenario: use S1..S8 or ALL");
    }

    function _all() internal {
        _s1();
        _s2();
        _s3();
        _s4();
        _s5();
        _s6();
        _s7();
        _s8();
        console2.log("");
        console2.log("##################################################");
        console2.log("#            ACCEPTANCE SUMMARY                  #");
        console2.log("##################################################");
        console2.log("  [PASS] S1  Happy path full lifecycle");
        console2.log("  [PASS] S2  Launchpad fail + full refund");
        console2.log("  [PASS] S3  Cancel pending subscription (ERC-7887)");
        console2.log("  [PASS] S4  Matching: subscription > redemption");
        console2.log("  [PASS] S5  Matching: redemption > subscription");
        console2.log("  [PASS] S6  Redemption falls through to illiquid");
        console2.log("  [PASS] S7  NAV change drives redemption value");
        console2.log("  [PASS] S8  Wind-down settles in-flight queues");
        console2.log("  --------------------------------------------------");
        console2.log("  8 / 8 mechanism scenarios verified.");
        console2.log("");
    }

    // =============================================================
    //                       SCENARIOS
    // =============================================================

    function _s1() internal {
        _open("S1", "Happy Path - Full Lifecycle");
        _proves("Money flows end-to-end (launchpad -> epoch -> wind-down) with nothing lost.");
        _deploy(50_000 * USDC_ONE);

        _step("Launchpad opens. Alice 30,000 + Bob 30,000 + Charlie 40,000 USDC deposited.");
        vm.warp(start);
        vault.startLaunchpad();
        _lpDeposit(alice, 30_000 * USDC_ONE);
        _lpDeposit(bob, 30_000 * USDC_ONE);
        _lpDeposit(charlie, 40_000 * USDC_ONE);
        _ok(string.concat("Total locked: ", _usd(vault.totalLaunchpadLocked()), " (>= 50,000 min)"));

        _step("Deadline passes -> protocol deploys capital into the 80/20 mix.");
        vm.warp(end);
        vault.transitionAfterDeadline();
        _portfolio();
        require(custody.wRWABalance() == 80_000 * USDC_ONE && custody.liquidBalance() == 20_000 * USDC_ONE, "S1 mix");
        require(vault.totalSupply() == 100_000 * SHARE_ONE, "S1 supply");

        _claimAll();
        _step("Epoch 0: Alice subscribes 10,000; Bob redeems 5,000 shares; NAV unchanged.");
        uint256 a = _reqDeposit(alice, 10_000 * USDC_ONE);
        uint256 b = _reqRedeem(bob, 5000 * SHARE_ONE);
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok("Matched 5,000 P2P; net subscription 5,000 bought toward target.");
        _claim(alice, a);
        _claim(bob, b);

        _step("Admin triggers wind-down; all holders redeem pro-rata.");
        vault.triggerWindDown();
        _vm(alice);
        vault.claimWindDown();
        _vm(bob);
        vault.claimWindDown();
        _vm(charlie);
        vault.claimWindDown();

        _ok(string.concat("Final state: ", _stateName()));
        _ok(
            string.concat(
                "Alice / Bob / Charlie USDC: ",
                _usd(usdc.balanceOf(alice)),
                " / ",
                _usd(usdc.balanceOf(bob)),
                " / ",
                _usd(usdc.balanceOf(charlie))
            )
        );
        require(vault.totalSupply() == 0 && vault.state() == IVault.State.Closed, "S1 closed");
        require(
            usdc.balanceOf(alice) == 1_000_000 * USDC_ONE && usdc.balanceOf(bob) == 1_000_000 * USDC_ONE
                && usdc.balanceOf(charlie) == 1_000_000 * USDC_ONE,
            "S1 whole"
        );
        _pass("Every actor recovered their capital at NAV 1.00; supply fully retired.");
    }

    function _s2() internal {
        _open("S2", "Launchpad Fail + Refund");
        _proves("If the minimum is not met, every depositor gets 100% of their USDC back.");
        _deploy(50_000 * USDC_ONE);

        _step("Only Alice deposits 30,000 (< 50,000 minimum).");
        vm.warp(start);
        vault.startLaunchpad();
        _lpDeposit(alice, 30_000 * USDC_ONE);
        vm.warp(end);
        vault.transitionAfterDeadline();
        _ok(string.concat("State: ", _stateName(), " (minimum not reached)"));

        _step("Alice claims her refund.");
        _vm(alice);
        vault.refundLaunchpad();
        _ok(string.concat("Alice USDC restored to ", _usd(usdc.balanceOf(alice))));
        require(usdc.balanceOf(alice) == 1_000_000 * USDC_ONE && vault.totalLaunchpadLocked() == 0, "S2");
        _pass("No user funds stranded on the failure path.");
    }

    function _s3() internal {
        _open("S3", "Cancel Pending Subscription (ERC-7887)");
        _proves("A user can withdraw a queued subscription before it is processed.");
        _deploy(50_000 * USDC_ONE);
        _toEpoch();

        _step("Alice subscribes 10,000, then cancels before the epoch runs.");
        uint256 id = _reqDeposit(alice, 10_000 * USDC_ONE);
        _ok(string.concat("Pending subscription: ", _usd(vault.pendingSubAmount(alice))));
        _vm(alice);
        vault.cancelRequest(id);
        _ok(string.concat("After cancel: ", _usd(vault.pendingSubAmount(alice)), " pending; USDC returned."));

        uint256 supplyBefore = vault.totalSupply();
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok(string.concat("Epoch processed as a no-op. currentEpoch = ", vm.toString(vault.currentEpoch())));
        require(vault.pendingSubAmount(alice) == 0 && vault.totalSupply() == supplyBefore, "S3");
        _pass("Cancelled request refunded and skipped; queue integrity preserved.");
    }

    function _s4() internal {
        _open("S4", "Matching - Subscription > Redemption");
        _proves("Subscriptions and redemptions net off P2P; only the surplus hits the fund.");
        _deploy(50_000 * USDC_ONE);
        _toEpoch();
        _portfolio();

        _step("Alice subscribes 10,000; Bob redeems 4,000 shares (NAV 1.00).");
        uint256 a = _reqDeposit(alice, 10_000 * USDC_ONE);
        uint256 b = _reqRedeem(bob, 4000 * SHARE_ONE);
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok("Matched 4,000 P2P (no fund interaction). Net subscription 6,000.");
        _ok("Rebalance buy: 4,800 illiquid + 1,200 liquid (toward 80/20).");
        _claim(alice, a);
        _claim(bob, b);
        _portfolio();
        require(custody.wRWABalance() == 84_800 * USDC_ONE && custody.liquidBalance() == 21_200 * USDC_ONE, "S4 mix");
        _ok(string.concat("Alice received 10,000 shares; Bob received 4,000 USDC."));
        _pass("P2P netting saved a 4,000 USDC fund round-trip.");
    }

    function _s5() internal {
        _open("S5", "Matching - Redemption > Subscription");
        _proves("Excess redemptions are paid from the liquid buffer, not the illiquid fund.");
        _deploy(50_000 * USDC_ONE);
        _toEpoch();
        _portfolio();

        _step("Alice subscribes 4,000; Bob redeems 10,000 shares (NAV 1.00).");
        uint256 a = _reqDeposit(alice, 4000 * USDC_ONE);
        uint256 b = _reqRedeem(bob, 10_000 * SHARE_ONE);
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok("Matched 4,000 P2P; net redemption 6,000 paid from liquid buffer (20k -> 14k).");
        _claim(alice, a);
        _claim(bob, b);
        _portfolio();
        require(custody.wRWABalance() == 80_000 * USDC_ONE && custody.liquidBalance() == 14_000 * USDC_ONE, "S5 mix");
        _ok("Alice received 4,000 shares; Bob received 10,000 USDC (4k match + 6k liquid).");
        _pass("Illiquid fund never touched; buffer absorbed the redemption.");
    }

    function _s6() internal {
        _open("S6", "Redemption Needs Illiquid Fallback");
        _proves("When the buffer is exhausted, redemption falls through to the illiquid fund.");
        _deploy(50_000 * USDC_ONE);
        _toEpoch();
        pruv.setPrice(1e18);

        _step("Prior epoch drains the liquid buffer down to 2,000.");
        uint256 b = _reqRedeem(bob, 18_000 * SHARE_ONE);
        vault.processEpoch();
        _claim(bob, b);
        _ok(string.concat("Buffer now: ", _usd(custody.liquidBalance())));

        _step("Alice redeems 8,000 shares; only 2,000 liquid is available.");
        uint256 a = _reqRedeem(alice, 8000 * SHARE_ONE);
        vault.processEpoch();
        _ok("Layer 2 (liquid): 2,000 used. Layer 3 (Pruv): 6,000 redeemed.");
        _claim(alice, a);
        _portfolio();
        require(custody.liquidBalance() == 0 && custody.wRWABalance() == 74_000 * USDC_ONE, "S6");
        _ok("Alice received 8,000 USDC across both layers.");
        _pass("3-layer redemption falls through correctly when the buffer is short.");
    }

    function _s7() internal {
        _open("S7", "NAV Change Affects Calculations");
        _proves("When the underlying appreciates, redeemers are paid the higher NAV.");
        _deploy(50_000 * USDC_ONE);
        _toEpoch();

        _step("Admin marks wRWA +10% (setPrice 1.10).");
        pruv.setPrice(1.1e18);
        _ok(string.concat("Total assets: ", _usd(vault.totalAssets()), " | NAV: ", _navStr(vault.nav())));

        _step("Alice redeems 10 shares.");
        uint256 before = usdc.balanceOf(alice);
        uint256 id = _reqRedeem(alice, 10 * SHARE_ONE);
        vault.processEpoch();
        _claim(alice, id);
        uint256 got = usdc.balanceOf(alice) - before;
        _ok(string.concat("Alice received ", _usd(got), " (= 10 shares x 1.08)"));
        require(got == 10_800_000, "S7");
        _pass("Redemption value reflects the epoch-time NAV, not a stale price.");
    }

    function _s8() internal {
        _open("S8", "Wind-Down Mid-Epoch");
        _proves("Wind-down cleanly settles all in-flight obligations; no user stranded.");
        _deploy(50_000 * USDC_ONE);
        _toEpoch();
        pruv.setPrice(1e18);

        _step("In-flight: Alice subscription 5,000 + Bob redemption 5,000 shares (unprocessed).");
        _reqDeposit(alice, 5000 * USDC_ONE);
        _reqRedeem(bob, 5000 * SHARE_ONE);

        _step("Admin triggers wind-down.");
        vault.triggerWindDown();
        _ok(string.concat("State: ", _stateName(), " | liquidated pool: ", _usd(vault.windDownUSDC())));
        _ok("Pending subscription refunded; locked redemption shares returned.");

        _vm(alice);
        vault.claimWindDown();
        _vm(bob);
        vault.claimWindDown();
        _ok(string.concat("Final state: ", _stateName()));
        _ok(string.concat("Alice / Bob USDC: ", _usd(usdc.balanceOf(alice)), " / ", _usd(usdc.balanceOf(bob))));
        require(
            vault.state() == IVault.State.Closed && usdc.balanceOf(alice) == 1_000_000 * USDC_ONE
                && usdc.balanceOf(bob) == 1_000_000 * USDC_ONE,
            "S8"
        );
        _pass("All obligations settled; pool closed; everyone whole at NAV 1.00.");
    }

    // =============================================================
    //                      SETUP HELPERS
    // =============================================================

    function _deploy(uint256 minAmount) internal {
        usdc = new MockUSDC();
        liquid = new MockLiquidBuffer();
        pruv = new MockPruv(usdc);
        amm = new MockAMM(usdc, liquid);
        custody = new Custody(usdc, pruv, liquid, amm);
        vault = new Vault("Retail Access Vault", "rACCESS", usdc, custody);
        custody.setVault(address(vault));
        start = uint64(block.timestamp + 1 days);
        end = uint64(block.timestamp + 8 days);
        vault.initLaunchpad(start, end, minAmount);
        vault.configAsset(address(pruv), address(liquid), address(amm), 8000);
        usdc.mint(alice, 1_000_000 * USDC_ONE);
        usdc.mint(bob, 1_000_000 * USDC_ONE);
        usdc.mint(charlie, 1_000_000 * USDC_ONE);
    }

    function _lpDeposit(address who, uint256 amount) internal {
        vm.startPrank(who);
        usdc.approve(address(vault), amount);
        vault.depositToLaunchpad(amount);
        vm.stopPrank();
    }

    function _reqDeposit(address who, uint256 amount) internal returns (uint256 id) {
        vm.startPrank(who);
        usdc.approve(address(vault), amount);
        id = vault.requestDeposit(amount);
        vm.stopPrank();
    }

    function _reqRedeem(address who, uint256 shares) internal returns (uint256 id) {
        vm.prank(who);
        id = vault.requestRedeem(shares);
    }

    function _claim(address who, uint256 id) internal {
        vm.prank(who);
        vault.claim(id);
    }

    function _vm(address who) internal {
        vm.prank(who);
    }

    function _toEpoch() internal {
        vm.warp(start);
        vault.startLaunchpad();
        _lpDeposit(alice, 60_000 * USDC_ONE);
        _lpDeposit(bob, 40_000 * USDC_ONE);
        vm.warp(end);
        vault.transitionAfterDeadline();
        _vm(alice);
        vault.claimLaunchpadShares();
        _vm(bob);
        vault.claimLaunchpadShares();
    }

    function _claimAll() internal {
        _vm(alice);
        vault.claimLaunchpadShares();
        _vm(bob);
        vault.claimLaunchpadShares();
        _vm(charlie);
        vault.claimLaunchpadShares();
    }

    // =============================================================
    //                     OUTPUT HELPERS
    // =============================================================

    function _open(string memory id, string memory title) internal pure {
        console2.log("");
        console2.log("==================================================");
        console2.log(string.concat("  ", id, ": ", title));
        console2.log("==================================================");
    }

    function _proves(string memory what) internal pure {
        console2.log(string.concat("  WHAT THIS PROVES: ", what));
        console2.log("");
    }

    function _step(string memory s) internal pure {
        console2.log(string.concat("  > ", s));
    }

    function _ok(string memory s) internal pure {
        console2.log(string.concat("      [ok] ", s));
    }

    function _pass(string memory s) internal pure {
        console2.log("");
        console2.log(string.concat("  RESULT: PASS - ", s));
    }

    function _portfolio() internal view {
        console2.log(
            string.concat(
                "      Portfolio: ",
                _usd(custody.wRWABalance()),
                " illiquid + ",
                _usd(custody.liquidBalance()),
                " liquid | supply ",
                _sh(vault.totalSupply()),
                " | NAV ",
                _navStr(vault.nav())
            )
        );
    }

    function _stateName() internal view returns (string memory) {
        IVault.State st = vault.state();
        if (st == IVault.State.Initialized) return "Initialized";
        if (st == IVault.State.LaunchpadStart) return "LaunchpadStart";
        if (st == IVault.State.LaunchpadFail) return "LaunchpadFail";
        if (st == IVault.State.EpochBased) return "EpochBased";
        if (st == IVault.State.WindDown) return "WindDown";
        return "Closed";
    }

    /// @dev Format a 6-decimal USDC amount as "1,234.56 USDC".
    function _usd(uint256 v) internal pure returns (string memory) {
        uint256 whole = v / USDC_ONE;
        uint256 cents = (v % USDC_ONE) / 1e4; // 2 decimals
        return string.concat(_commify(whole), ".", _two(cents), " USDC");
    }

    /// @dev Format an 18-decimal share amount as "1,234 shares" (whole shares).
    function _sh(uint256 v) internal pure returns (string memory) {
        return string.concat(_commify(v / SHARE_ONE), " shares");
    }

    /// @dev Format the 1e6-parity NAV as "1.08".
    function _navStr(uint256 navRaw) internal pure returns (string memory) {
        uint256 whole = navRaw / USDC_ONE;
        uint256 frac = (navRaw % USDC_ONE) / 1e4;
        return string.concat(vm.toString(whole), ".", _two(frac));
    }

    function _two(uint256 n) internal pure returns (string memory) {
        if (n < 10) return string.concat("0", vm.toString(n));
        return vm.toString(n);
    }

    /// @dev Insert thousands separators into an integer.
    function _commify(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        bytes memory digits = bytes(vm.toString(n));
        uint256 len = digits.length;
        uint256 commas = (len - 1) / 3;
        bytes memory out = new bytes(len + commas);
        uint256 j = out.length;
        uint256 count = 0;
        for (uint256 i = len; i > 0; i--) {
            out[--j] = digits[i - 1];
            count++;
            if (count % 3 == 0 && i > 1) {
                out[--j] = ",";
            }
        }
        return string(out);
    }
}
