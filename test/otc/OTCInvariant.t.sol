// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";

/// @notice OTC escrow must always be fully backed: the contract's USDC balance is never less than
///         the sum of resting bids' usdcRemaining (no leakage of buyer escrow).
contract OTCInvariant is OTCFixture {
    function setUp() public {
        _setUpOTC();
        // seed a couple of resting bids so the invariant exercises real escrow state
        _placeBid(bob, 500, 5000e6);
        _placeBid(charlie, 1000, 3000e6);
        targetContract(address(otc));
    }

    function invariant_EscrowFullyBacked() public view {
        assertGe(usdc.balanceOf(address(otc)), otc.totalEscrowed());
    }
}
