// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IBidVault {
    error NotMarket();
    error NothingToClaim();

    event Escrowed(uint256 usdc);
    event Filled(uint256 shares, uint256 redeemRequestId);
    event PaidOut(address indexed to, uint256 usdc);
    event Refunded(address indexed to, uint256 usdc);
    event RedemptionClaimed(uint256 usdc);
    event LpRedeemed(address indexed holder, uint256 lp, uint256 usdc);

    /// @notice Returns the address of the buyer who placed the bid and holds the LP tokens.
    function buyer() external view returns (address);
    /// @notice Returns the USDC still escrowed (unfilled) backing the open part of the bid.
    function escrow() external view returns (uint256); // USDC still escrowed (unfilled)
    /// @notice Market-only: pay the seller out of escrow on a fill.
    function payOut(address to, uint256 amount) external; // market-only: pay seller on a fill
    /// @notice Market-only: refund escrowed USDC on cancel or wind-down.
    function refund(address to, uint256 amount) external; // market-only: cancel / wind-down
    /// @notice Market-only: mint LP for this fill and queue a redeem of the bought shares.
    function onFill(uint256 shares) external; // market-only: mint LP + queue redeem for this fill
    /// @notice Pull settled NAV USDC for all settled fills into the redeemable proceeds pool.
    function claimRedemption() external; // pull NAV USDC for all settled fills
    /// @notice Recover value via the Vault's wind-down pool into the redeemable proceeds pool.
    function claimWindDown() external; // recover via the vault's wind-down pool
    /// @notice Burn `lp` LP tokens for a pro-rata share of the redeemable proceeds.
    function redeem(uint256 lp) external returns (uint256 usdcOut);
}
