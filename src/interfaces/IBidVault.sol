// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IBidVault {
    error NothingToClaim();
    error AlreadyInitiated();

    event RedemptionClaimed(uint256 usdc);
    event LpRedeemed(address indexed holder, uint256 lp, uint256 usdc);

    function buyer() external view returns (address);
    function shares() external view returns (uint256);
    function initRedeem() external;
    function claimRedemption() external;
    function redeem(uint256 lp) external returns (uint256 usdcOut);
}
