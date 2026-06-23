// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BidVault} from "./BidVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice Deploys one BidVault per OTC fill. Stateless.
contract OTCFactory {
    event BidVaultCreated(address indexed vault, address indexed buyer, uint256 shares);

    /// @notice Deploy a BidVault for one OTC fill and return its address.
    /// @param vault_  Address of the Vault (also the share token).
    /// @param usdc_   USDC token used for payouts.
    /// @param buyer_  Address of the buyer who receives LP tokens 1:1 with shares.
    /// @param shares_ Number of vault shares (18-dec) transferred into the BidVault.
    /// @return bidVault Address of the newly deployed BidVault.
    function createBidVault(address vault_, MockUSDC usdc_, address buyer_, uint256 shares_)
        external
        returns (address bidVault)
    {
        bidVault = address(new BidVault(vault_, usdc_, buyer_, shares_));
        emit BidVaultCreated(bidVault, buyer_, shares_);
    }
}
