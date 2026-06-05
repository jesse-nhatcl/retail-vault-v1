// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {INavSource} from "../interfaces/INavSource.sol";

/// @title MockPruv
/// @notice Stand-in for the Hamilton Lane Evergreen fund. This contract *is* the wRWA token
///         (6 decimals). `subscribe` pulls USDC and mints wRWA; `redeem` burns wRWA and pays USDC.
///         The admin sets the price manually (no oracle) per spec §5.5.
/// @dev    `pricePerWRWA` is scaled to 1e18: 1e18 == 1.0 USDC per wRWA. Both wRWA and USDC are
///         6-decimal, so value math is `mulDiv(amount, price, 1e18)` with no extra scaling.
contract MockPruv is ERC20, Ownable, INavSource {
    using SafeERC20 for MockUSDC;

    uint256 internal constant PRICE_SCALE = 1e18;

    MockUSDC public immutable usdc;
    /// @notice USDC value of one wRWA, scaled 1e18 (1e18 = parity).
    uint256 public pricePerWRWA;

    event PriceSet(uint256 newPrice);
    event Subscribed(address indexed account, uint256 usdcIn, uint256 wRWAOut);
    event Redeemed(address indexed account, uint256 wRWAIn, uint256 usdcOut);

    constructor(MockUSDC _usdc) ERC20("Wrapped RWA", "wRWA") Ownable(msg.sender) {
        usdc = _usdc;
        pricePerWRWA = PRICE_SCALE; // start at parity
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Admin-controlled NAV input. Required before each `processEpoch` in the Vault.
    function setPrice(uint256 newPrice) external onlyOwner {
        pricePerWRWA = newPrice;
        emit PriceSet(newPrice);
    }

    /// @notice Subscribe USDC into the fund and receive wRWA at the current price.
    function subscribe(uint256 usdcAmount) external returns (uint256 wRWAOut) {
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        wRWAOut = Math.mulDiv(usdcAmount, PRICE_SCALE, pricePerWRWA);
        _mint(msg.sender, wRWAOut);
        emit Subscribed(msg.sender, usdcAmount, wRWAOut);
    }

    /// @notice Redeem wRWA back to USDC at the current price.
    /// @dev    Mints USDC to the caller (mock convenience) so redemptions never run dry even after
    ///         the price appreciates above what was originally subscribed.
    function redeem(uint256 wRWAAmount) external returns (uint256 usdcOut) {
        _burn(msg.sender, wRWAAmount);
        usdcOut = Math.mulDiv(wRWAAmount, pricePerWRWA, PRICE_SCALE);
        usdc.mint(msg.sender, usdcOut);
        emit Redeemed(msg.sender, wRWAAmount, usdcOut);
    }
}
