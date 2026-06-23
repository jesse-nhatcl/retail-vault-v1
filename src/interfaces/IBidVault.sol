// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IBidVault {
    error NothingToClaim();
    error AlreadyInitiated();

    event RedeemInitiated(uint256 requestId);
    event RedemptionClaimed(uint256 usdc);
    event LpRedeemed(address indexed holder, uint256 lp, uint256 usdc);

    /// @notice Returns the address of the buyer who placed the bid and holds the LP tokens.
    function buyer() external view returns (address);
    /// @notice Returns the number of vault shares (18-dec) held in this BidVault.
    function shares() external view returns (uint256);
    /// @notice Queue the held shares for redemption through the Vault. Permissionless, once.
    function initRedeem() external;
    /// @notice Pull the settled USDC payout from the Vault after the epoch processes.
    function claimRedemption() external;
    /// @notice Burn `lp` LP tokens for a pro-rata share of the USDC this vault has received.
    function redeem(uint256 lp) external returns (uint256 usdcOut);
}
