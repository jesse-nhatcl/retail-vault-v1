// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBidVault} from "../interfaces/IBidVault.sol";
import {IVault} from "../interfaces/IVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice One per OTC fill. Holds bought shares, mints LP 1:1 to the buyer, redeems via the Vault.
contract BidVault is IBidVault, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IVault public immutable vault;
    IERC20 public immutable usdc;
    address public immutable buyer;
    uint256 public immutable shares;
    uint256 public redeemRequestId;
    bool public redeemInitiated;

    constructor(address vault_, MockUSDC usdc_, address buyer_, uint256 shares_) ERC20("OTC BidVault LP", "otcLP") {
        vault = IVault(vault_);
        usdc = IERC20(address(usdc_));
        buyer = buyer_;
        shares = shares_;
        _mint(buyer_, shares_); // LP 1:1 with shares held
    }

    /// @notice Queue the held shares for redemption through the Vault. Permissionless, once.
    function initRedeem() external {
        if (redeemInitiated) revert AlreadyInitiated();
        redeemInitiated = true;
        redeemRequestId = vault.requestRedeem(shares);
        emit RedeemInitiated(redeemRequestId);
    }

    /// @notice After the epoch settles, pull this vault's USDC payout from the Vault.
    function claimRedemption() external nonReentrant {
        vault.claim(redeemRequestId);
        emit RedemptionClaimed(usdc.balanceOf(address(this)));
    }

    /// @notice Recover value when wind-down cancelled the auto-redeem and returned the shares here:
    ///         burn this vault's shares into the Vault's pro-rata wind-down pool so LP stays redeemable.
    function claimWindDown() external nonReentrant {
        vault.claimWindDown();
        emit RedemptionClaimed(usdc.balanceOf(address(this)));
    }

    /// @notice Burn LP for a pro-rata share of the USDC this vault has received.
    function redeem(uint256 lp) external nonReentrant returns (uint256 usdcOut) {
        if (lp == 0 || balanceOf(msg.sender) < lp) revert NothingToClaim();
        usdcOut = Math.mulDiv(usdc.balanceOf(address(this)), lp, totalSupply());
        _burn(msg.sender, lp);
        usdc.safeTransfer(msg.sender, usdcOut);
        emit LpRedeemed(msg.sender, lp, usdcOut);
    }
}
