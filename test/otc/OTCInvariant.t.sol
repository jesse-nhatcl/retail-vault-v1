// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OTCFixture} from "../helpers/OTCFixture.sol";
import {OTCMarket} from "../../src/otc/OTCMarket.sol";
import {BidVault} from "../../src/otc/BidVault.sol";
import {IOTCMarket} from "../../src/interfaces/IOTCMarket.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @notice Drives real placeBid/cancelBid traffic so the escrow invariant exercises live state
///         instead of reverting on every fuzz call.
contract OTCHandler is Test {
    OTCMarket public otc;
    MockUSDC public usdc;
    address[3] public actors;
    uint16[4] internal rungs = [uint16(100), 250, 500, 1000];
    uint256[] public bidIds;

    constructor(OTCMarket _otc, MockUSDC _usdc, address a0, address a1, address a2) {
        otc = _otc;
        usdc = _usdc;
        actors[0] = a0;
        actors[1] = a1;
        actors[2] = a2;
    }

    function placeBid(uint256 actorSeed, uint256 rungSeed, uint256 amt) external {
        address actor = actors[actorSeed % 3];
        uint16 d = rungs[rungSeed % 4];
        amt = bound(amt, 1e6, usdc.balanceOf(actor));
        if (amt == 0) return;
        vm.startPrank(actor);
        usdc.approve(address(otc), amt);
        try otc.placeBid(d, amt) returns (uint256 id) {
            bidIds.push(id);
        } catch {}
        vm.stopPrank();
    }

    function cancelBid(uint256 idSeed) external {
        if (bidIds.length == 0) return;
        uint256 id = bidIds[idSeed % bidIds.length];
        (address buyer,,,,) = otc.bids(id);
        vm.prank(buyer);
        try otc.cancelBid(id) {} catch {}
    }

    /// @notice Number of bids successfully placed (bidId == index in OTCMarket.bids).
    function bidCount() external view returns (uint256) {
        return bidIds.length;
    }
}

/// @notice Per-bid escrow accounting: each resting bid's BidVault holds exactly its `usdcRemaining`
///         (never under-backed, never double-counted), and the market itself custodies no USDC —
///         escrow lives in the per-bid vaults, not the OTCMarket.
contract OTCInvariant is OTCFixture {
    OTCHandler internal handler;

    function setUp() public {
        _setUpOTC();

        address dave = makeAddr("dave");
        usdc.mint(dave, 1_000_000e6);

        handler = new OTCHandler(otc, usdc, bob, charlie, dave);
        targetContract(address(handler));
    }

    /// @notice Every resting bid is fully and exactly backed by its own BidVault's escrow.
    function invariant_EscrowFullyBacked() public view {
        uint256 n = handler.bidCount();
        for (uint256 i = 0; i < n; i++) {
            (,, uint256 usdcRemaining, IOTCMarket.BidStatus status,) = otc.bids(i);
            if (status != IOTCMarket.BidStatus.Resting) continue;
            assertEq(BidVault(otc.bidVaultOf(i)).escrow(), usdcRemaining);
        }
    }

    /// @notice The OTCMarket never custodies USDC; escrow is held in each bid's BidVault.
    function invariant_MarketHoldsNoUsdc() public view {
        assertEq(usdc.balanceOf(address(otc)), 0);
    }
}
