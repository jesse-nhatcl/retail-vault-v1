// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {OTCFactory} from "../../src/otc/OTCFactory.sol";
import {BidVault} from "../../src/otc/BidVault.sol";

contract OTCFactoryTest is OTCFixture {
    function test_DeploysBidVault() public {
        _setUpOTC();
        OTCFactory f = new OTCFactory();
        address bv = f.createBidVault(address(vault), usdc, bob, 1000e18);
        assertEq(BidVault(bv).buyer(), bob);
        assertEq(BidVault(bv).shares(), 1000e18);
    }
}
