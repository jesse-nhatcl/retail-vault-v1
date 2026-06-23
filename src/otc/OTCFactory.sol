// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BidVault} from "./BidVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice Deploys one BidVault per OTC fill. Stateless.
contract OTCFactory {
    event BidVaultCreated(address indexed vault, address indexed buyer, uint256 shares);

    function createBidVault(address vault_, MockUSDC usdc_, address buyer_, uint256 shares_)
        external
        returns (address bidVault)
    {
        bidVault = address(new BidVault(vault_, usdc_, buyer_, shares_));
        emit BidVaultCreated(bidVault, buyer_, shares_);
    }
}
