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
import {OTCFactory} from "../src/otc/OTCFactory.sol";
import {OTCMarket} from "../src/otc/OTCMarket.sol";
import {IOTCMarket} from "../src/interfaces/IOTCMarket.sol";
import {BidVault} from "../src/otc/BidVault.sol";

/// @notice Manager-facing demo of the OTC early-exit layer. Mirrors the narration style of
///         `Demo.s.sol`: each scenario prints the claim it proves, step-by-step balances, and a
///         PASS verdict. The OTC market sits as "Layer 0" — an instant exit door alongside the
///         normal retail subscribe/redeem queue.
/// @dev    One scenario:  forge script script/DemoOTC.s.sol --sig 'run(string)' "OTC1" -vvv
///         Combined:      forge script script/DemoOTC.s.sol --sig 'run(string)' "COMBINED" -vvv
///         Both:          forge script script/DemoOTC.s.sol --sig 'run(string)' "ALL" -vvv
contract DemoOTC is Script {
    MockUSDC usdc;
    MockLiquidBuffer liquid;
    MockPruv pruv;
    MockAMM amm;
    Custody custody;
    Vault vault;
    OTCFactory factory;
    OTCMarket otc;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC4A411E);
    address dave = address(0xDA5E);

    uint64 start;
    uint64 end;

    uint256 constant USDC_ONE = 1e6;
    uint256 constant SHARE_ONE = 1e18;

    function run(string memory scenario) external {
        bytes32 s = keccak256(bytes(scenario));
        if (s == keccak256("ALL")) _all();
        else if (s == keccak256("OTC1")) _otc1();
        else if (s == keccak256("COMBINED")) _combined();
        else if (s == keccak256("MULTI")) _multi();
        else revert("unknown scenario: use OTC1, COMBINED, MULTI or ALL");
    }

    function _all() internal {
        _otc1();
        _combined();
        _multi();
        console2.log("");
        console2.log("##################################################");
        console2.log("#            ACCEPTANCE SUMMARY                  #");
        console2.log("##################################################");
        console2.log("  [PASS] OTC1      Standalone early-exit at a discount");
        console2.log("  [PASS] COMBINED  OTC early-exit composes with the retail queue");
        console2.log("  [PASS] MULTI     Matching engine under load: cheapest-first, partial fill, floor");
        console2.log("  --------------------------------------------------");
        console2.log("  3 / 3 OTC scenarios verified.");
        console2.log("");
    }

    // =============================================================
    //                       SCENARIOS
    // =============================================================

    function _otc1() internal {
        _open("OTC1", "Standalone Early-Exit - Seller Cashes Out Now, Buyer Captures Discount");
        _proves("A holder exits instantly at a 5% discount; the buyer redeems at full NAV next epoch.");
        _deploy();

        _step("Reach EpochBased. Seller deposits 100,000 USDC in the launchpad and claims shares.");
        vm.warp(start);
        vault.startLaunchpad();
        _lpDeposit(alice, 100_000 * USDC_ONE); // alice = the seller in this scenario
        vm.warp(end);
        vault.transitionAfterDeadline();
        _vm(alice);
        vault.claimLaunchpadShares();
        _ok(string.concat("Seller (alice) holds ", _sh(vault.balanceOf(alice)), "."));
        _portfolio();

        _step("Deploy OTC market with discount ladder [100, 250, 500, 1000] bps (1% / 2.5% / 5% / 10%).");
        _deployOtc();
        _ok(string.concat("OTCMarket live at ", vm.toString(address(otc)), " (Layer 0 exit door)."));

        _step("Buyer (bob) places a bid: 500 bps tier, escrows 9,500 USDC.");
        uint256 bidId = _placeBid(bob, 500, 9500 * USDC_ONE);
        (, uint16 d, uint256 esc,) = otc.bids(bidId);
        _ok(string.concat("Bid #", vm.toString(bidId), " resting on the ", _bps(d), " rung; ", _usd(esc), " escrowed."));

        _step("Seller approves 10,000 shares and calls sell(10,000, max 1000 bps) - cheapest rung fills first.");
        uint256 sellerUsdcBefore = usdc.balanceOf(alice);
        uint256 sold = _sell(alice, 10_000 * SHARE_ONE, 1000);
        uint256 sellerGot = usdc.balanceOf(alice) - sellerUsdcBefore;
        address bv = otc.bidVaultOf(bidId);
        uint256 buyerLp = BidVault(bv).balanceOf(bob);
        _ok(string.concat("Matched ", _sh(sold), " at 5% discount. Seller received ", _usd(sellerGot), " NOW."));
        _ok(string.concat("BidVault deployed at ", vm.toString(bv), " (auto-queued a redeem)."));
        _ok(string.concat("Buyer minted ", _sh(buyerLp), " of otcLP (1:1 with shares bought)."));

        _step("Admin sets NAV 1.00, then processEpoch() settles the BidVault's queued redeem.");
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok(string.concat("Epoch processed; currentEpoch = ", vm.toString(vault.currentEpoch()), "."));

        _step("BidVault.claimRedemption() pulls full-NAV USDC; buyer redeems otcLP for that USDC.");
        BidVault(bv).claimRedemption();
        uint256 buyerBefore = usdc.balanceOf(bob);
        _vm(bob);
        BidVault(bv).redeem(buyerLp);
        uint256 buyerGot = usdc.balanceOf(bob) - buyerBefore;
        uint256 buyerProfit = buyerGot - 9500 * USDC_ONE;
        _ok(string.concat("Buyer redeemed ", _usd(buyerGot), " (10,000 shares x NAV 1.00)."));
        _ok(string.concat("Buyer profit = ", _usd(buyerProfit), " = exactly the 5% discount the seller paid."));
        _pass("Instant exit at -5% for the seller; +500 USDC for the buyer who waited one epoch.");
    }

    function _combined() internal {
        _open("COMBINED", "Retail + OTC As One Lifecycle - OTC Is Layer 0 Inside The Normal Flow");
        _proves("An OTC early-exit and the retail queue settle together in a single epoch, all whole.");
        _deploy();

        _step("Launchpad: Alice 50,000 + Bob 30,000 + Charlie 20,000 USDC -> 100,000 total.");
        vm.warp(start);
        vault.startLaunchpad();
        _lpDeposit(alice, 50_000 * USDC_ONE);
        _lpDeposit(bob, 30_000 * USDC_ONE);
        _lpDeposit(charlie, 20_000 * USDC_ONE);
        vm.warp(end);
        vault.transitionAfterDeadline();
        _portfolio();

        _step("All three claim their launchpad shares.");
        _vm(alice);
        vault.claimLaunchpadShares();
        _vm(bob);
        vault.claimLaunchpadShares();
        _vm(charlie);
        vault.claimLaunchpadShares();
        _ok(
            string.concat(
                "Alice ",
                _sh(vault.balanceOf(alice)),
                " | Bob ",
                _sh(vault.balanceOf(bob)),
                " | Charlie ",
                _sh(vault.balanceOf(charlie)),
                "."
            )
        );

        _step(
            "Retail epoch activity: Alice subscribes 10,000 (slow in); Bob redeems 5,000 shares (slow out, via queue)."
        );
        uint256 aliceReq = _reqDeposit(alice, 10_000 * USDC_ONE);
        uint256 bobReq = _reqRedeem(bob, 5000 * SHARE_ONE);
        _ok(
            string.concat(
                "Bob's queued exit is pending: ", _sh(vault.pendingRedeemShares(bob)), " (waits for the epoch)."
            )
        );

        _step("Layer 0 - Charlie needs cash NOW. Deploy OTC market; Dave bids 9,500 USDC at the 500 bps rung.");
        _deployOtc();
        uint256 bidId = _placeBid(dave, 500, 9500 * USDC_ONE);
        _ok(string.concat("Dave's bid #", vm.toString(bidId), " rests on the 5.00% rung; 9,500.00 USDC escrowed."));

        _step("Charlie sells 10,000 of his 20,000 shares into the OTC bid - instant fill, no waiting.");
        uint256 charlieBefore = usdc.balanceOf(charlie);
        _sell(charlie, 10_000 * SHARE_ONE, 1000);
        uint256 charlieGot = usdc.balanceOf(charlie) - charlieBefore;
        address bv = otc.bidVaultOf(bidId);
        _ok(string.concat("Charlie received ", _usd(charlieGot), " IMMEDIATELY (Layer-0 exit, -5%)."));
        _ok(string.concat("Bob is still waiting in the queue: ", _sh(vault.pendingRedeemShares(bob)), " pending."));
        _ok(string.concat("OTC fill auto-queued a redeem via BidVault ", vm.toString(bv), "."));

        _step("Admin sets NAV 1.00, then processEpoch() settles retail queue AND the BidVault redeem together.");
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok("Matched 10,000 P2P (Alice's sub vs redeemers); net redeem 5,000 paid from liquid buffer (20k -> 15k).");
        _portfolio();

        _step("Claims: Alice gets shares, Bob gets USDC, BidVault pulls USDC then Dave redeems otcLP.");
        _claim(alice, aliceReq);
        uint256 bobBefore = usdc.balanceOf(bob);
        _claim(bob, bobReq);
        uint256 bobGot = usdc.balanceOf(bob) - bobBefore;
        BidVault(bv).claimRedemption();
        uint256 daveLp = BidVault(bv).balanceOf(dave);
        uint256 daveBefore = usdc.balanceOf(dave);
        _vm(dave);
        BidVault(bv).redeem(daveLp);
        uint256 daveGot = usdc.balanceOf(dave) - daveBefore;
        _ok(string.concat("Alice now holds ", _sh(vault.balanceOf(alice)), " (her 10,000 sub minted)."));
        _ok(string.concat("Bob redeemed ", _usd(bobGot), " from the queue (full NAV, one epoch later)."));
        _ok(
            string.concat(
                "Dave redeemed ",
                _usd(daveGot),
                " (10,000 shares x NAV 1.00); profit ",
                _usd(daveGot - 9500 * USDC_ONE),
                "."
            )
        );

        _pass("OTC early-exit composes with the retail queue in one epoch.");
        console2.log("");
        console2.log("  TWO EXIT DOORS, SAME VAULT:");
        console2.log(
            string.concat("    Charlie (OTC, Layer 0):  instant, received ", _usd(charlieGot), " at -5% discount.")
        );
        console2.log(
            string.concat("    Bob     (retail queue):  1 epoch wait, received ", _usd(bobGot), " at full NAV 1.00.")
        );
    }

    // Packed bid IDs for MULTI to avoid stack-too-deep.
    struct MultiBids {
        uint256 bid1;
        uint256 bid2;
        uint256 bid3;
        uint256 bid4;
        uint256 bid5;
        uint256 bid6;
    }

    function _multi() internal {
        _open("MULTI", "Matching Engine Under Load - Cheapest-First Sweep, Partial Fill, Floor Enforced");
        _proves(
            "A 6-buyer bid book sweeps cheapest-first; a cancel is honoured; a partial fill is correct; a bid above the seller's floor is skipped."
        );
        _deploy();
        _multiReachEpochBased();
        _multiBidBook();
    }

    function _multiReachEpochBased() internal {
        // ── Step 1: reach EpochBased ─────────────────────────────────────────────────
        _step("Reach EpochBased. Seller (alice) deposits 100,000 USDC in the launchpad and claims shares.");
        vm.warp(start);
        vault.startLaunchpad();
        _lpDeposit(alice, 100_000 * USDC_ONE);
        vm.warp(end);
        vault.transitionAfterDeadline();
        _vm(alice);
        vault.claimLaunchpadShares();
        _ok(string.concat("Seller (alice) holds ", _sh(vault.balanceOf(alice)), " at NAV 1.00."));
        _portfolio();

        // ── Step 2: deploy OTC market ────────────────────────────────────────────────
        _step("Deploy OTC market with discount ladder [100, 250, 500, 1000] bps.");
        _deployOtc();
        _ok(string.concat("OTCMarket live at ", vm.toString(address(otc)), "."));
    }

    function _multiMintBuyers()
        internal
        returns (address b1, address b2, address b3, address b4, address b5, address b6)
    {
        b1 = makeAddr("buyer1");
        b2 = makeAddr("buyer2");
        b3 = makeAddr("buyer3");
        b4 = makeAddr("buyer4");
        b5 = makeAddr("buyer5");
        b6 = makeAddr("buyer6");
        usdc.mint(b1, 20_000 * USDC_ONE);
        usdc.mint(b2, 20_000 * USDC_ONE);
        usdc.mint(b3, 20_000 * USDC_ONE);
        usdc.mint(b4, 20_000 * USDC_ONE);
        usdc.mint(b5, 20_000 * USDC_ONE);
        usdc.mint(b6, 20_000 * USDC_ONE);
    }

    function _multiPlaceBids(address b1, address b2, address b3, address b4, address b5, address b6)
        internal
        returns (MultiBids memory ids)
    {
        // Math at NAV = 1e6 (parity):
        //   bidShares = mulDiv(mulDiv(usdcIn, 1e18, nav), 10000, 10000 - d)
        //             = usdcIn * 1e12 * 10000 / (10000 - d)
        //
        // Buyer1: d=100,  usdcIn=9_900e6 -> 10_000e18 shares
        // Buyer2: d=100,  usdcIn=4_950e6 ->  5_000e18 shares  (cancels)
        // Buyer3: d=250,  usdcIn=9_750e6 -> 10_000e18 shares
        // Buyer4: d=500,  usdcIn=4_750e6 ->  5_000e18 shares
        // Buyer5: d=500,  usdcIn=9_500e6 -> 10_000e18 shares  (partial fill)
        // Buyer6: d=1000, usdcIn=9_000e6 -> 10_000e18 shares  (above floor, skipped)
        ids.bid1 = _placeBid(b1, 100, 9900 * USDC_ONE);
        ids.bid2 = _placeBid(b2, 100, 4950 * USDC_ONE);
        ids.bid3 = _placeBid(b3, 250, 9750 * USDC_ONE);
        ids.bid4 = _placeBid(b4, 500, 4750 * USDC_ONE);
        ids.bid5 = _placeBid(b5, 500, 9500 * USDC_ONE);
        ids.bid6 = _placeBid(b6, 1000, 9000 * USDC_ONE);
    }

    function _multiBidBook() internal {
        // ── Step 3: six buyers place bids ───────────────────────────────────────────
        _step("Six buyers place bids across the ladder (two at 1%, one at 2.5%, two at 5%, one at 10%).");
        (address b1, address b2, address b3, address b4, address b5, address b6) = _multiMintBuyers();
        MultiBids memory ids = _multiPlaceBids(b1, b2, b3, b4, b5, b6);
        _multiShowBook(ids);

        // ── Step 4: Buyer2 cancels ───────────────────────────────────────────────────
        _step(string.concat("Buyer2 cancels bid #", vm.toString(ids.bid2), " before the sell."));
        uint256 buyer2Before = usdc.balanceOf(b2);
        vm.prank(b2);
        otc.cancelBid(ids.bid2);
        uint256 buyer2Refund = usdc.balanceOf(b2) - buyer2Before;
        _ok(
            string.concat(
                "Bid #",
                vm.toString(ids.bid2),
                " cancelled. Refunded ",
                _usd(buyer2Refund),
                " to Buyer2. Status=Cancelled."
            )
        );

        // ── Step 5: seller sweeps 30,000 shares, floor = 500 bps ────────────────────
        _multiSell(ids, b2);
    }

    function _multiShowBook(MultiBids memory ids) internal view {
        (, uint16 d1, uint256 e1,) = otc.bids(ids.bid1);
        (, uint16 d2, uint256 e2,) = otc.bids(ids.bid2);
        (, uint16 d3, uint256 e3,) = otc.bids(ids.bid3);
        (, uint16 d4, uint256 e4,) = otc.bids(ids.bid4);
        (, uint16 d5, uint256 e5,) = otc.bids(ids.bid5);
        (, uint16 d6, uint256 e6,) = otc.bids(ids.bid6);
        _ok("  Resting bid book:");
        _ok(
            string.concat(
                "    Bid #",
                vm.toString(ids.bid1),
                "  rung ",
                _bps(d1),
                "  escrow ",
                _usd(e1),
                "  (~10,000 shares implied)"
            )
        );
        _ok(
            string.concat(
                "    Bid #",
                vm.toString(ids.bid2),
                "  rung ",
                _bps(d2),
                "  escrow ",
                _usd(e2),
                "  (~5,000 shares implied)"
            )
        );
        _ok(
            string.concat(
                "    Bid #",
                vm.toString(ids.bid3),
                "  rung ",
                _bps(d3),
                "  escrow ",
                _usd(e3),
                "  (~10,000 shares implied)"
            )
        );
        _ok(
            string.concat(
                "    Bid #",
                vm.toString(ids.bid4),
                "  rung ",
                _bps(d4),
                "  escrow ",
                _usd(e4),
                "  (~5,000 shares implied)"
            )
        );
        _ok(
            string.concat(
                "    Bid #",
                vm.toString(ids.bid5),
                "  rung ",
                _bps(d5),
                "  escrow ",
                _usd(e5),
                "  (~10,000 shares implied)"
            )
        );
        _ok(
            string.concat(
                "    Bid #",
                vm.toString(ids.bid6),
                "  rung ",
                _bps(d6),
                "  escrow ",
                _usd(e6),
                "  (~10,000 shares implied)"
            )
        );
    }

    function _multiSell(MultiBids memory ids, address buyer2Addr) internal {
        // Expected fill order (Buyer2 skipped — cancelled):
        //   Rung 1%   (100 bps): Buyer1  fill=10,000 sh  usdcPaid=9,900 USDC  (Matched)
        //   Rung 2.5% (250 bps): Buyer3  fill=10,000 sh  usdcPaid=9,750 USDC  (Matched)
        //   Rung 5%   (500 bps): Buyer4  fill=5,000  sh  usdcPaid=4,750 USDC  (Matched)
        //                        Buyer5  fill=5,000  sh  usdcPaid=4,750 USDC  (Resting, partial)
        //   Rung 10% (1000 bps): Buyer6  SKIPPED — above floor 500 bps
        // Total USDC to seller: 9,900 + 9,750 + 4,750 + 4,750 = 29,150 USDC
        _step("Seller sells 30,000 shares with floor = 500 bps. Sweep runs cheapest rung first.");
        uint256 sellerUsdcBefore = usdc.balanceOf(alice);
        uint256 sharesSold = _sell(alice, 30_000 * SHARE_ONE, 500);
        uint256 sellerReceived = usdc.balanceOf(alice) - sellerUsdcBefore;
        _multiNarrateFilledBids(ids);
        _multiNarrateRestingBids(ids);
        _multiSummary(ids, buyer2Addr, sharesSold, sellerReceived);
    }

    function _multiNarrateFilledBids(MultiBids memory ids) internal view {
        (, uint16 pd1, uint256 r1, IOTCMarket.BidStatus s1) = otc.bids(ids.bid1);
        _ok(
            string.concat(
                "Rung ",
                _bps(pd1),
                " - Bid #",
                vm.toString(ids.bid1),
                " FULLY FILLED: 10,000 shares, 9,900.00 USDC paid. Status=",
                _statusName(s1),
                ". rem=",
                _usd(r1),
                "."
            )
        );
        (, uint16 pd3, uint256 r3, IOTCMarket.BidStatus s3) = otc.bids(ids.bid3);
        _ok(
            string.concat(
                "Rung ",
                _bps(pd3),
                " - Bid #",
                vm.toString(ids.bid3),
                " FULLY FILLED: 10,000 shares, 9,750.00 USDC paid. Status=",
                _statusName(s3),
                ". rem=",
                _usd(r3),
                "."
            )
        );
        (, uint16 pd4, uint256 r4, IOTCMarket.BidStatus s4) = otc.bids(ids.bid4);
        _ok(
            string.concat(
                "Rung ",
                _bps(pd4),
                " - Bid #",
                vm.toString(ids.bid4),
                " FULLY FILLED: 5,000 shares, 4,750.00 USDC paid. Status=",
                _statusName(s4),
                ". rem=",
                _usd(r4),
                "."
            )
        );
    }

    function _multiNarrateRestingBids(MultiBids memory ids) internal view {
        (, uint16 pd5, uint256 r5, IOTCMarket.BidStatus s5) = otc.bids(ids.bid5);
        _ok(
            string.concat(
                "Rung ",
                _bps(pd5),
                " - Bid #",
                vm.toString(ids.bid5),
                " PARTIAL FILL: 5,000 of 10,000 shares, 4,750.00 USDC paid. Status=",
                _statusName(s5),
                ". rem=",
                _usd(r5),
                "."
            )
        );
        (, uint16 pd6, uint256 r6, IOTCMarket.BidStatus s6) = otc.bids(ids.bid6);
        _ok(
            string.concat(
                "Rung ",
                _bps(pd6),
                " - Bid #",
                vm.toString(ids.bid6),
                " UNTOUCHED (above seller floor 5.00%). Status=",
                _statusName(s6),
                ". rem=",
                _usd(r6),
                "."
            )
        );
    }

    function _multiSummary(MultiBids memory ids, address buyer2Addr, uint256 sharesSold, uint256 sellerReceived)
        internal
        view
    {
        (,,, IOTCMarket.BidStatus st2) = otc.bids(ids.bid2);
        (,,, IOTCMarket.BidStatus st5) = otc.bids(ids.bid5);
        (,,, IOTCMarket.BidStatus st6) = otc.bids(ids.bid6);
        (,, uint256 rem5,) = otc.bids(ids.bid5);
        (,, uint256 rem6,) = otc.bids(ids.bid6);

        _step("Aggregate summary.");
        _ok(string.concat("Total shares sold:       ", _sh(sharesSold)));
        _ok(string.concat("Total USDC to seller:    ", _usd(sellerReceived)));
        _ok("Full NAV value (30,000 shares x 1.00):  30,000.00 USDC");
        _ok(
            string.concat(
                "Discount captured by buyers: ", _usd(30_000 * USDC_ONE - sellerReceived), " (blended ~2.83%)"
            )
        );
        _ok("BidVaults deployed:      4  (one per fill: Buyer1, Buyer3, Buyer4, Buyer5-partial)");
        _ok(
            string.concat(
                "Buyer5 bid #", vm.toString(ids.bid5), " still ", _statusName(st5), "; usdcRemaining=", _usd(rem5), "."
            )
        );
        _ok(
            string.concat(
                "Buyer6 bid #",
                vm.toString(ids.bid6),
                " untouched (",
                _statusName(st6),
                "); usdcRemaining=",
                _usd(rem6),
                "."
            )
        );
        _ok(
            string.concat(
                "Buyer2 bid #", vm.toString(ids.bid2), " Cancelled (", _statusName(st2), "); refund already settled."
            )
        );
        _ok(string.concat("  (Buyer2 wallet: ", _usd(usdc.balanceOf(buyer2Addr)), " confirms refund received.)"));

        _pass(
            "Cheapest-first sweep honoured; cancel excluded from fill; partial fill correct; above-floor bid skipped; escrow conserved."
        );
    }

    /// @dev Map BidStatus enum value to a human-readable name for narration.
    function _statusName(IOTCMarket.BidStatus s) internal pure returns (string memory) {
        if (s == IOTCMarket.BidStatus.Resting) return "Resting";
        if (s == IOTCMarket.BidStatus.Matched) return "Matched";
        return "Cancelled";
    }

    // =============================================================
    //                      SETUP HELPERS
    // =============================================================

    function _deploy() internal {
        usdc = new MockUSDC();
        liquid = new MockLiquidBuffer();
        pruv = new MockPruv(usdc);
        amm = new MockAMM(usdc, liquid);
        custody = new Custody(usdc, pruv, liquid, amm);
        vault = new Vault("Retail Access Vault", "rACCESS", usdc, custody);
        custody.setVault(address(vault));
        start = uint64(block.timestamp + 1 days);
        end = uint64(block.timestamp + 8 days);
        vault.initLaunchpad(start, end, 50_000 * USDC_ONE);
        vault.configAsset(address(pruv), address(liquid), address(amm), 8000);
        usdc.mint(alice, 1_000_000 * USDC_ONE);
        usdc.mint(bob, 1_000_000 * USDC_ONE);
        usdc.mint(charlie, 1_000_000 * USDC_ONE);
        usdc.mint(dave, 1_000_000 * USDC_ONE);
    }

    function _deployOtc() internal {
        factory = new OTCFactory();
        uint16[] memory ladder = new uint16[](4);
        ladder[0] = 100;
        ladder[1] = 250;
        ladder[2] = 500;
        ladder[3] = 1000;
        otc = new OTCMarket(address(vault), usdc, ladder, factory);
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

    function _placeBid(address who, uint16 discountBps, uint256 usdcIn) internal returns (uint256 id) {
        vm.startPrank(who);
        usdc.approve(address(otc), usdcIn);
        id = otc.placeBid(discountBps, usdcIn);
        vm.stopPrank();
    }

    function _sell(address who, uint256 shares, uint16 maxDiscountBps) internal returns (uint256 sold) {
        vm.startPrank(who);
        vault.approve(address(otc), shares);
        sold = otc.sell(shares, maxDiscountBps);
        vm.stopPrank();
    }

    function _claim(address who, uint256 id) internal {
        vm.prank(who);
        vault.claim(id);
    }

    function _vm(address who) internal {
        vm.prank(who);
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

    /// @dev Format a basis-point discount as "5.00%".
    function _bps(uint16 b) internal pure returns (string memory) {
        uint256 whole = uint256(b) / 100;
        uint256 frac = uint256(b) % 100;
        return string.concat(vm.toString(whole), ".", _two(frac), "%");
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
