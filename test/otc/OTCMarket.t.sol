// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../src/interfaces/IOTCMarket.sol";

contract OTCMarketTest is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_LadderConfigured() public {
        uint16[] memory l = otc.ladder();
        assertEq(l.length, 4);
        assertEq(l[0], 100);
        assertEq(l[3], 1000);
    }
}
