// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IVault
/// @notice Public surface of the Retail Access Vault. See docs/05-spec.md §5.
interface IVault {
    /// @notice Lifecycle states. Transitions are one-way (docs/05-spec.md §4).
    enum State {
        Initialized,
        LaunchpadStart,
        LaunchpadFail,
        EpochBased,
        WindDown,
        Closed
    }

    // ---- Setup (admin, only in Initialized) ----
    function initLaunchpad(uint64 startTime, uint64 endTime, uint256 minAmount) external;
    function configAsset(address pruv, address liquidBuffer, address mockAmm, uint16 illiquidBps) external;

    // ---- Launchpad phase ----
    function depositToLaunchpad(uint256 amount) external;
    function transitionAfterDeadline() external;
    function claimLaunchpadShares() external;
    function refundLaunchpad() external;

    // ---- Epoch phase (users) ----
    function requestDeposit(uint256 amount) external returns (uint256 requestId);
    function requestRedeem(uint256 shares) external returns (uint256 requestId);
    function cancelRequest(uint256 requestId) external;
    function claim(uint256 requestId) external;

    // ---- Admin / settlement ----
    function processEpoch() external;
    function triggerWindDown() external;
    function claimWindDown() external;

    // ---- Views ----
    function state() external view returns (State);
    function totalAssets() external view returns (uint256);
    function nav() external view returns (uint256);
    function pendingSubAmount(address user) external view returns (uint256);
    function pendingRedeemShares(address user) external view returns (uint256);
    function currentEpoch() external view returns (uint64);
}
