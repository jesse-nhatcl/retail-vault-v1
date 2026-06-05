// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title INavSource
/// @notice Read-only source of the per-wRWA price (the fund's NAV per share), 1e18-scaled.
/// @dev    The Vault reads NAV through this narrow seam so the concrete price source can be
///         swapped without touching Vault logic. In this POC the source is `MockPruv`, which
///         self-reports its NAV (faithful to private credit: the fund administrator strikes the
///         NAV). In production this becomes a real Pruv NAV feed — or a dedicated oracle — that
///         implements the same one-method interface. Price is manual per spec decision 5; this
///         seam does NOT introduce an oracle, only the injection point for one later.
///         1e18 == parity (1.0 USDC per wRWA).
interface INavSource {
    /// @notice Current price of one wRWA in USDC, scaled to 1e18.
    /// @return price 1e18-scaled price; 1e18 == 1.0.
    function pricePerWRWA() external view returns (uint256 price);
}
