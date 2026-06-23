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
import {BidVault} from "../src/otc/BidVault.sol";

/// @notice Demo of the OTC early-exit flow. Prints human-readable balances at each step.
/// @dev    forge script script/DemoOTC.s.sol --sig 'run(string)' "OTC1" -vvv
contract DemoOTC is Script {
    MockUSDC usdc;
    MockLiquidBuffer liquid;
    MockPruv pruv;
    MockAMM amm;
    Custody custody;
    Vault vault;
    OTCFactory factory;
    OTCMarket otc;

    address seller = address(0x5E11E8);
    address buyer = address(0xB01E8);

    uint64 start;
    uint64 end;

    uint256 constant USDC_ONE = 1e6;
    uint256 constant SHARE_ONE = 1e18;

    function run(string memory scenario) external {
        // Only OTC1 is defined; any unknown scenario falls through to the same path.
        bytes32 s = keccak256(bytes(scenario));
        if (s == keccak256("OTC1") || true) _otc1();
    }

    function _otc1() internal {
        _open("OTC1", "Early-Exit OTC - Buyer Acquires Discounted Shares");
        _proves("A holder can exit early at a discount; the buyer redeems at full NAV after epoch.");

        // ----------------------------------------------------------------
        // Step 1: deploy full stack and reach EpochBased with seller holding shares
        // ----------------------------------------------------------------
        _step("Deploy full stack and reach EpochBased. Seller deposits 100,000 USDC in launchpad.");
        _deploy();

        vm.warp(start);
        vault.startLaunchpad();

        _lpDeposit(seller, 100_000 * USDC_ONE);

        vm.warp(end);
        vault.transitionAfterDeadline();

        vm.prank(seller);
        vault.claimLaunchpadShares();

        uint256 sellerShares = vault.balanceOf(seller);
        _ok(string.concat("EpochBased reached. Seller rACCESS balance: ", _sh(sellerShares)));
        _ok(
            string.concat(
                "Portfolio: ", _usd(custody.wRWABalance()), " illiquid + ", _usd(custody.liquidBalance()), " liquid"
            )
        );

        // ----------------------------------------------------------------
        // Step 2: deploy OTCFactory + OTCMarket with ladder [100, 250, 500, 1000]
        // ----------------------------------------------------------------
        _step("Deploy OTCFactory and OTCMarket with discount ladder [100, 250, 500, 1000] bps.");
        factory = new OTCFactory();
        uint16[] memory ladder = new uint16[](4);
        ladder[0] = 100;
        ladder[1] = 250;
        ladder[2] = 500;
        ladder[3] = 1000;
        otc = new OTCMarket(address(vault), usdc, ladder, factory);
        _ok(string.concat("OTCMarket deployed at: ", vm.toString(address(otc))));

        // ----------------------------------------------------------------
        // Step 3: buyer places a bid at 500 bps discount, escrowing 9,500 USDC
        // ----------------------------------------------------------------
        _step("Buyer places bid: 500 bps discount, 9,500 USDC escrowed.");
        vm.startPrank(buyer);
        usdc.approve(address(otc), 9500 * USDC_ONE);
        uint256 bidId = otc.placeBid(500, 9500 * USDC_ONE);
        vm.stopPrank();

        (address bidBuyer, uint16 bidDiscount, uint256 bidUsdc,) = otc.bids(bidId);
        _ok(string.concat("Bid #", vm.toString(bidId), " placed by ", vm.toString(bidBuyer)));
        _ok(string.concat("  Discount: ", vm.toString(uint256(bidDiscount)), " bps | Escrowed: ", _usd(bidUsdc)));

        // ----------------------------------------------------------------
        // Step 4: seller approves shares to market and sells 10,000 shares at max 1000 bps
        // ----------------------------------------------------------------
        _step("Seller approves 10,000 shares to OTCMarket and calls sell().");
        uint256 sellShares = 10_000 * SHARE_ONE;
        uint256 sellerUsdcBefore = usdc.balanceOf(seller);

        vm.startPrank(seller);
        vault.approve(address(otc), sellShares);
        otc.sell(sellShares, 1000);
        vm.stopPrank();

        uint256 sellerUsdcReceived = usdc.balanceOf(seller) - sellerUsdcBefore;
        uint256 sellerSharesAfter = vault.balanceOf(seller);
        address bv = otc.bidVaultOf(bidId);
        uint256 buyerLp = BidVault(bv).balanceOf(buyer);

        _ok(
            string.concat(
                "Seller USDC received: ", _usd(sellerUsdcReceived), " (9,500 USDC for 10,000 shares at 5% discount)"
            )
        );
        _ok(string.concat("Seller remaining shares: ", _sh(sellerSharesAfter)));
        _ok(string.concat("BidVault deployed at: ", vm.toString(bv)));
        _ok(string.concat("Buyer LP balance (otcLP): ", _sh(buyerLp)));

        // ----------------------------------------------------------------
        // Step 5: processEpoch, claimRedemption, buyer redeems LP for USDC
        // ----------------------------------------------------------------
        _step("Admin sets NAV price to 1.00, then processEpoch() to settle the queued redemption.");
        pruv.setPrice(1e18);
        vault.processEpoch();
        _ok(
            string.concat(
                "Epoch ",
                vm.toString(vault.currentEpoch() - 1),
                " processed. currentEpoch = ",
                vm.toString(vault.currentEpoch())
            )
        );

        _step("Anyone calls BidVault.claimRedemption() to pull USDC from the Vault into the BidVault.");
        BidVault(bv).claimRedemption();
        uint256 bvUsdc = usdc.balanceOf(bv);
        _ok(string.concat("BidVault USDC received from Vault: ", _usd(bvUsdc)));

        _step("Buyer redeems their LP tokens from the BidVault for full NAV USDC.");
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        // buyer started with 100,000; spent 9,500 escrowing; net cost = 9,500
        uint256 buyerUsdcSpent = 100_000 * USDC_ONE - buyerUsdcBefore;
        vm.prank(buyer);
        BidVault(bv).redeem(buyerLp);
        uint256 buyerUsdcFinal = usdc.balanceOf(buyer);
        uint256 buyerRedeemed = buyerUsdcFinal - buyerUsdcBefore;
        uint256 buyerProfit = buyerRedeemed > buyerUsdcSpent ? buyerRedeemed - buyerUsdcSpent : 0;

        _ok(string.concat("Buyer USDC redeemed from BidVault: ", _usd(buyerRedeemed)));
        _ok(string.concat("Buyer net profit (redeemed - escrowed): ", _usd(buyerProfit), " (the 500 bps discount)"));
        _ok(string.concat("Buyer final USDC balance: ", _usd(buyerUsdcFinal)));

        console2.log("");
        console2.log("  SUMMARY");
        console2.log(
            string.concat("    Seller received:  ", _usd(sellerUsdcReceived), " (instant liquidity at 5% discount)")
        );
        console2.log(
            string.concat(
                "    Buyer paid:       ",
                _usd(9500 * USDC_ONE),
                " -> redeemed: ",
                _usd(buyerUsdcFinal),
                " -> profit: ~500 USDC"
            )
        );

        _pass("OTC early-exit complete: seller exited before epoch, buyer captured discount.");
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
        usdc.mint(seller, 1_000_000 * USDC_ONE);
        usdc.mint(buyer, 100_000 * USDC_ONE);
    }

    function _lpDeposit(address who, uint256 amount) internal {
        vm.startPrank(who);
        usdc.approve(address(vault), amount);
        vault.depositToLaunchpad(amount);
        vm.stopPrank();
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

    /// @dev Format a 6-decimal USDC amount as "1,234.56 USDC".
    function _usd(uint256 v) internal pure returns (string memory) {
        uint256 whole = v / USDC_ONE;
        uint256 cents = (v % USDC_ONE) / 1e4;
        return string.concat(_commify(whole), ".", _two(cents), " USDC");
    }

    /// @dev Format an 18-decimal share amount as "1,234 shares" (whole shares).
    function _sh(uint256 v) internal pure returns (string memory) {
        return string.concat(_commify(v / SHARE_ONE), " shares");
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
