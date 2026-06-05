// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICustody} from "./interfaces/ICustody.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockPruv} from "./mocks/MockPruv.sol";
import {MockLiquidBuffer} from "./mocks/MockLiquidBuffer.sol";
import {MockAMM} from "./mocks/MockAMM.sol";

/// @title Custody
/// @notice Holds all external tokens for the protocol (wRWA, liquid buffer, idle USDC) and is the
///         sole contract that interacts with the external mocks (Pruv, AMM). Every mutating call is
///         gated to the Vault — Custody never trusts an EOA. See docs/02-architecture/decision.md.
contract Custody is ICustody, Ownable, ReentrancyGuard {
    using SafeERC20 for MockUSDC;
    using SafeERC20 for MockPruv;
    using SafeERC20 for MockLiquidBuffer;

    MockUSDC public immutable usdc;
    MockPruv public immutable pruv;
    MockLiquidBuffer public immutable liquid;
    MockAMM public immutable amm;

    /// @notice The only address allowed to drive custody. Set once after the Vault is deployed.
    address public vault;

    error NotVault();
    error VaultAlreadySet();
    error ZeroAddress();

    event VaultSet(address indexed vault);

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(MockUSDC _usdc, MockPruv _pruv, MockLiquidBuffer _liquid, MockAMM _amm) Ownable(msg.sender) {
        usdc = _usdc;
        pruv = _pruv;
        liquid = _liquid;
        amm = _amm;
        // Pre-approve the external venues; balances live here, the venues pull what they need.
        usdc.forceApprove(address(_pruv), type(uint256).max);
        usdc.forceApprove(address(_amm), type(uint256).max);
        liquid.forceApprove(address(_amm), type(uint256).max);
    }

    /// @notice Bind the Vault address. Callable once by the deployer.
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) revert VaultAlreadySet();
        if (_vault == address(0)) revert ZeroAddress();
        vault = _vault;
        emit VaultSet(_vault);
    }

    /// @inheritdoc ICustody
    function subscribeToPruv(uint256 usdcAmount) external onlyVault returns (uint256 wRWAReceived) {
        wRWAReceived = pruv.subscribe(usdcAmount);
    }

    /// @inheritdoc ICustody
    function redeemFromPruv(uint256 wRWAAmount) external onlyVault returns (uint256 usdcReceived) {
        usdcReceived = pruv.redeem(wRWAAmount);
    }

    /// @inheritdoc ICustody
    function swapLiquidForUSDC(uint256 liquidAmount) external onlyVault returns (uint256 usdcReceived) {
        usdcReceived = amm.swapLiquidForUSDC(liquidAmount);
    }

    /// @inheritdoc ICustody
    function swapUSDCForLiquid(uint256 usdcAmount) external onlyVault returns (uint256 liquidReceived) {
        liquidReceived = amm.swapUSDCForLiquid(usdcAmount);
    }

    /// @inheritdoc ICustody
    function depositUSDC(uint256 amount) external onlyVault {
        usdc.safeTransferFrom(vault, address(this), amount);
    }

    /// @inheritdoc ICustody
    function withdrawUSDC(address to, uint256 amount) external onlyVault nonReentrant {
        usdc.safeTransfer(to, amount);
    }

    /// @inheritdoc ICustody
    function wRWABalance() external view returns (uint256) {
        return pruv.balanceOf(address(this));
    }

    /// @inheritdoc ICustody
    function liquidBalance() external view returns (uint256) {
        return liquid.balanceOf(address(this));
    }

    /// @inheritdoc ICustody
    function usdcBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
