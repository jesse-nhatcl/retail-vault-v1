// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ICustody
/// @notice Surface the Vault uses to drive the Custody contract. Custody holds all external
///         tokens (wRWA, liquid buffer, idle USDC) and is the only contract that talks to the
///         external mocks. Every function is `onlyVault` in the implementation.
interface ICustody {
    /// @notice Subscribe `usdcAmount` of idle USDC into Pruv, receiving wRWA in return.
    /// @return wRWAReceived Amount of wRWA minted to custody.
    function subscribeToPruv(uint256 usdcAmount) external returns (uint256 wRWAReceived);

    /// @notice Redeem `wRWAAmount` of wRWA from Pruv, receiving USDC in return.
    /// @return usdcReceived Amount of USDC received by custody.
    function redeemFromPruv(uint256 wRWAAmount) external returns (uint256 usdcReceived);

    /// @notice Swap `liquidAmount` of the liquid buffer for USDC (1:1 via mock AMM).
    /// @return usdcReceived Amount of USDC received by custody.
    function swapLiquidForUSDC(uint256 liquidAmount) external returns (uint256 usdcReceived);

    /// @notice Swap `usdcAmount` of idle USDC for the liquid buffer token (1:1 via mock AMM).
    /// @return liquidReceived Amount of liquid buffer token received by custody.
    function swapUSDCForLiquid(uint256 usdcAmount) external returns (uint256 liquidReceived);

    /// @notice Pull `amount` of USDC from the Vault into custody (Vault must approve first).
    function depositUSDC(uint256 amount) external;

    /// @notice Send `amount` of idle USDC from custody to `to`.
    function withdrawUSDC(address to, uint256 amount) external;

    /// @notice wRWA balance held by custody (6 decimals).
    function wRWABalance() external view returns (uint256);

    /// @notice Liquid buffer balance held by custody (6 decimals).
    function liquidBalance() external view returns (uint256);

    /// @notice Idle USDC balance held by custody (6 decimals).
    function usdcBalance() external view returns (uint256);
}
