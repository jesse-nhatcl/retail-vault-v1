// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BidVault} from "./BidVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice Deploys one BidVault per OTC bid. Stateless.
contract OTCFactory {
    event BidVaultCreated(address indexed vault, address indexed buyer);

    /// @notice Deploy a BidVault for one OTC bid and return its address.
    /// @param vault_  Address of the Vault (also the share token).
    /// @param usdc_   USDC token used for payouts.
    /// @param buyer_  Address of the buyer who receives LP tokens for bought shares.
    /// @return bidVault Address of the newly deployed BidVault.
    function createBidVault(address vault_, MockUSDC usdc_, address buyer_) external returns (address bidVault) {
        bidVault = address(new BidVault(vault_, usdc_, buyer_, msg.sender));
        emit BidVaultCreated(bidVault, buyer_);
    }
}
