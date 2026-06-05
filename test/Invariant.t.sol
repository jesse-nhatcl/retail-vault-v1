// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "./helpers/Fixture.sol";

/// @notice Property checks on the epoch settlement: at NAV 1.0, matched value is conserved (no value
///         minted or destroyed by matching) and totalAssets backs the share supply.
contract InvariantTest is Fixture {
    function setUp() public {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 60_000e6);
        _launchpadDeposit(bob, 40_000e6);
        _finalizeLaunchpad();
        _claimLaunchpad(alice);
        _claimLaunchpad(bob);
        pruv.setPrice(1e18);
    }

    /// @dev At NAV 1.0, totalAssets (6-dec) must equal totalSupply (18-dec) scaled down by 1e12.
    function _assertBacked() internal view {
        assertEq(vault.totalAssets(), vault.totalSupply() / 1e12, "assets back supply at NAV 1.0");
    }

    /// @dev Fuzz over whole units so the conservation property is exact; sub-unit rounding is
    ///      already exercised by the deterministic S* scenarios (e.g. S7's 10.8 USDC).
    /// forge-config: default.fuzz.runs = 200
    function testFuzz_MatchingConservesValue(uint256 subWhole, uint256 redeemWhole) public {
        uint256 subAmt = bound(subWhole, 1, 30_000) * 1e6;
        uint256 redeemShares = bound(redeemWhole, 1, 40_000) * 1e18;

        _requestDeposit(alice, subAmt);
        _requestRedeem(bob, redeemShares);

        uint256 assetsBefore = vault.totalAssets();
        vault.processEpoch();

        // The vault still fully backs its shares at NAV 1.0 (matching mints/destroys no value).
        _assertBacked();
        // Assets move only by the net delta, never by the matched (P2P) portion.
        uint256 assetsAfter = vault.totalAssets();
        uint256 redeemValue = redeemShares / 1e12; // NAV 1.0
        if (subAmt > redeemValue) {
            assertEq(assetsAfter, assetsBefore + (subAmt - redeemValue), "net sub grows assets");
        } else {
            assertEq(assetsAfter, assetsBefore - (redeemValue - subAmt), "net redeem shrinks assets");
        }
    }
}
