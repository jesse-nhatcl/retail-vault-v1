// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVault} from "./interfaces/IVault.sol";
import {INavSource} from "./interfaces/INavSource.sol";
import {Custody} from "./Custody.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @title Vault
/// @notice ERC-7540-style async vault for the Retail Access POC. Holds the lifecycle state machine,
///         the subscription / redemption queues, the P2P matching engine, and the share token.
///         Token custody and DeFi interactions are delegated to the Custody contract.
/// @dev    Decimals: USDC / wRWA / liquid are 6-dec; shares are 18-dec; price & nav are 1e18-scaled
///         (nav parity falls out at ~1e6, see CLAUDE.md). Spec: docs/05-spec.md.
contract Vault is IVault, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for MockUSDC;

    uint256 internal constant WAD = 1e18;
    uint16 internal constant BPS = 10_000;
    uint256 internal constant SHARE_SCALE = 1e12; // 6-dec USDC -> 18-dec shares at launchpad parity
    uint256 internal constant MAX_REQUESTS_PER_EPOCH = 100;
    uint256 internal constant WIND_DOWN_PERIOD = 30 days;

    // ---- External wiring ----
    MockUSDC public immutable usdc;
    Custody public immutable custody;
    INavSource public navSource;
    address public liquidBuffer;
    address public mockAmm;
    uint16 public illiquidBps;

    // ---- State machine ----
    State public state;

    // ---- Launchpad ----
    uint64 public launchpadStart;
    uint64 public launchpadEnd;
    uint256 public minAmount;
    uint256 public totalLaunchpadLocked;
    uint256 public launchpadShares; // total shares minted for the launchpad cohort
    mapping(address => uint256) public launchpadDeposits;

    // ---- Epoch queues ----
    struct Request {
        address user;
        uint256 amount; // USDC (deposit) or shares (redeem)
        uint64 epoch;
        bool isDeposit;
        bool cancelled;
        bool fulfilled; // claimed
        uint256 sharesOwed; // for deposit requests, set at processEpoch
        uint256 usdcOwed; // for redeem requests, set at processEpoch
    }

    Request[] public requests;
    mapping(uint64 => uint256[]) public epochRequests;
    uint64 public currentEpoch;

    /// @dev Bundles the epoch's matching results so allocation helpers stay under the stack limit.
    struct EpochMath {
        uint256 navNow;
        uint256 subPending;
        uint256 redeemShares;
        uint256 matchedUSDC;
        uint256 matchedShares;
        uint256 netSubUSDC;
        uint256 netRedeemUSDC;
    }

    // ---- Wind-down ----
    uint256 public windDownUSDC; // USDC pool available to remaining holders, pro-rata
    uint256 public windDownSupply; // share supply snapshot at wind-down
    uint256 public windDownStart;

    // ---- Errors ----
    error InvalidState();
    error LaunchpadNotStarted();
    error LaunchpadNotEnded();
    error ZeroAmount();
    error NothingToClaim();
    error NotRequestOwner();
    error RequestNotClaimable();
    error RequestNotPending();
    error EpochQueueFull();
    error InvalidBps();
    error WindDownNotComplete();

    // ---- Events ----
    event LaunchpadInitialized(uint64 start, uint64 end, uint256 minAmount);
    event AssetConfigured(address pruv, address liquidBuffer, address mockAmm, uint16 illiquidBps);
    event LaunchpadStarted();
    event LaunchpadDeposited(address indexed user, uint256 amount);
    event LaunchpadSucceeded(uint256 totalLocked, uint256 sharesMinted);
    event LaunchpadFailed(uint256 totalLocked);
    event LaunchpadSharesClaimed(address indexed user, uint256 shares);
    event LaunchpadRefunded(address indexed user, uint256 amount);
    event DepositRequested(address indexed user, uint256 indexed id, uint256 amount, uint64 epoch);
    event RedeemRequested(address indexed user, uint256 indexed id, uint256 shares, uint64 epoch);
    event RequestCancelled(uint256 indexed id);
    event Claimed(address indexed user, uint256 indexed id, uint256 sharesOut, uint256 usdcOut);
    event MatchingPerformed(uint64 indexed epoch, uint256 matchedUSDC, uint256 matchedShares);
    event NetSubSettled(uint64 indexed epoch, uint256 netSubUSDC, uint256 buyIlliquid, uint256 buyLiquid);
    event NetRedeemSettled(uint64 indexed epoch, uint256 netRedeemUSDC, uint256 fromLiquid, uint256 fromIlliquid);
    event EpochProcessed(
        uint64 indexed epoch, uint256 nav, uint256 matchedUSDC, uint256 netSubUSDC, uint256 netRedeemUSDC
    );
    event WindDownTriggered(uint256 nav, uint256 poolUSDC, uint256 supply);
    event WindDownClaimed(address indexed user, uint256 shares, uint256 usdcOut);
    event PoolClosed();

    modifier onlyState(State s) {
        if (state != s) revert InvalidState();
        _;
    }

    constructor(string memory name_, string memory symbol_, MockUSDC _usdc, Custody _custody)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        usdc = _usdc;
        custody = _custody;
        state = State.Initialized;
    }

    // =============================================================
    //                          SETUP
    // =============================================================

    /// @inheritdoc IVault
    function initLaunchpad(uint64 startTime, uint64 endTime, uint256 minAmount_)
        external
        onlyOwner
        onlyState(State.Initialized)
    {
        if (endTime <= startTime) revert InvalidState();
        launchpadStart = startTime;
        launchpadEnd = endTime;
        minAmount = minAmount_;
        emit LaunchpadInitialized(startTime, endTime, minAmount_);
    }

    /// @inheritdoc IVault
    function configAsset(address pruv_, address liquidBuffer_, address mockAmm_, uint16 illiquidBps_)
        external
        onlyOwner
        onlyState(State.Initialized)
    {
        if (illiquidBps_ > BPS) revert InvalidBps();
        navSource = INavSource(pruv_);
        liquidBuffer = liquidBuffer_;
        mockAmm = mockAmm_;
        illiquidBps = illiquidBps_;
        emit AssetConfigured(pruv_, liquidBuffer_, mockAmm_, illiquidBps_);
    }

    // =============================================================
    //                        LAUNCHPAD
    // =============================================================

    /// @notice Permissionless transition Initialized -> LaunchpadStart once the start time is reached.
    function startLaunchpad() external onlyState(State.Initialized) {
        if (block.timestamp < launchpadStart) revert LaunchpadNotStarted();
        state = State.LaunchpadStart;
        emit LaunchpadStarted();
    }

    /// @inheritdoc IVault
    function depositToLaunchpad(uint256 amount) external nonReentrant onlyState(State.LaunchpadStart) {
        if (amount == 0) revert ZeroAmount();
        launchpadDeposits[msg.sender] += amount;
        totalLaunchpadLocked += amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit LaunchpadDeposited(msg.sender, amount);
    }

    /// @inheritdoc IVault
    function transitionAfterDeadline() external nonReentrant onlyState(State.LaunchpadStart) {
        if (block.timestamp < launchpadEnd) revert LaunchpadNotEnded();

        if (totalLaunchpadLocked >= minAmount) {
            state = State.EpochBased;
            // Deploy the locked USDC into the target asset mix and mint the cohort's shares.
            uint256 total = totalLaunchpadLocked;
            uint256 buyIlliquid = Math.mulDiv(total, illiquidBps, BPS);
            uint256 buyLiquid = total - buyIlliquid;

            usdc.forceApprove(address(custody), total);
            custody.depositUSDC(total);
            if (buyIlliquid > 0) custody.subscribeToPruv(buyIlliquid);
            if (buyLiquid > 0) custody.swapUSDCForLiquid(buyLiquid);

            launchpadShares = total * SHARE_SCALE;
            _mint(address(this), launchpadShares); // held by vault, distributed via claimLaunchpadShares
            emit LaunchpadSucceeded(total, launchpadShares);
        } else {
            state = State.LaunchpadFail;
            emit LaunchpadFailed(totalLaunchpadLocked);
        }
    }

    /// @inheritdoc IVault
    function claimLaunchpadShares() external nonReentrant onlyState(State.EpochBased) {
        uint256 deposited = launchpadDeposits[msg.sender];
        if (deposited == 0) revert NothingToClaim();
        launchpadDeposits[msg.sender] = 0;
        uint256 shares = Math.mulDiv(deposited, launchpadShares, totalLaunchpadLocked);
        _transfer(address(this), msg.sender, shares);
        emit LaunchpadSharesClaimed(msg.sender, shares);
    }

    /// @inheritdoc IVault
    function refundLaunchpad() external nonReentrant onlyState(State.LaunchpadFail) {
        uint256 deposited = launchpadDeposits[msg.sender];
        if (deposited == 0) revert NothingToClaim();
        launchpadDeposits[msg.sender] = 0;
        totalLaunchpadLocked -= deposited;
        usdc.safeTransfer(msg.sender, deposited);
        emit LaunchpadRefunded(msg.sender, deposited);
    }

    // =============================================================
    //                       EPOCH QUEUES
    // =============================================================

    /// @inheritdoc IVault
    function requestDeposit(uint256 amount)
        external
        nonReentrant
        onlyState(State.EpochBased)
        returns (uint256 requestId)
    {
        if (amount == 0) revert ZeroAmount();
        if (epochRequests[currentEpoch].length >= MAX_REQUESTS_PER_EPOCH) revert EpochQueueFull();
        requestId = _newRequest(msg.sender, amount, true);
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit DepositRequested(msg.sender, requestId, amount, currentEpoch);
    }

    /// @inheritdoc IVault
    function requestRedeem(uint256 shares)
        external
        nonReentrant
        onlyState(State.EpochBased)
        returns (uint256 requestId)
    {
        if (shares == 0) revert ZeroAmount();
        if (epochRequests[currentEpoch].length >= MAX_REQUESTS_PER_EPOCH) revert EpochQueueFull();
        requestId = _newRequest(msg.sender, shares, false);
        _transfer(msg.sender, address(this), shares); // lock shares
        emit RedeemRequested(msg.sender, requestId, shares, currentEpoch);
    }

    function _newRequest(address user, uint256 amount, bool isDeposit) internal returns (uint256 id) {
        id = requests.length;
        requests.push(
            Request({
                user: user,
                amount: amount,
                epoch: currentEpoch,
                isDeposit: isDeposit,
                cancelled: false,
                fulfilled: false,
                sharesOwed: 0,
                usdcOwed: 0
            })
        );
        epochRequests[currentEpoch].push(id);
    }

    /// @inheritdoc IVault
    function cancelRequest(uint256 requestId) external nonReentrant {
        Request storage r = requests[requestId];
        if (r.user != msg.sender) revert NotRequestOwner();
        // Only cancellable while still pending in the current (unprocessed) epoch.
        if (r.cancelled || r.fulfilled || r.epoch != currentEpoch) revert RequestNotPending();
        r.cancelled = true;
        if (r.isDeposit) {
            usdc.safeTransfer(r.user, r.amount);
        } else {
            _transfer(address(this), r.user, r.amount);
        }
        emit RequestCancelled(requestId);
    }

    /// @inheritdoc IVault
    function claim(uint256 requestId) external nonReentrant {
        Request storage r = requests[requestId];
        if (r.user != msg.sender) revert NotRequestOwner();
        if (r.cancelled || r.fulfilled || r.epoch >= currentEpoch) revert RequestNotClaimable();
        r.fulfilled = true;
        uint256 sharesOut;
        uint256 usdcOut;
        if (r.isDeposit) {
            sharesOut = r.sharesOwed;
            if (sharesOut > 0) _transfer(address(this), r.user, sharesOut);
        } else {
            usdcOut = r.usdcOwed;
            if (usdcOut > 0) usdc.safeTransfer(r.user, usdcOut);
        }
        emit Claimed(r.user, requestId, sharesOut, usdcOut);
    }

    // =============================================================
    //                     EPOCH SETTLEMENT
    // =============================================================

    /// @inheritdoc IVault
    function processEpoch() external onlyOwner nonReentrant onlyState(State.EpochBased) {
        uint64 epoch = currentEpoch;
        uint256[] storage ids = epochRequests[epoch];

        EpochMath memory m;
        m.navNow = nav();
        (m.subPending, m.redeemShares) = _snapshotQueues(ids);
        uint256 redeemValueUSDC = Math.mulDiv(m.redeemShares, m.navNow, WAD);
        m.matchedUSDC = Math.min(m.subPending, redeemValueUSDC);
        m.matchedShares = m.navNow == 0 ? 0 : Math.mulDiv(m.matchedUSDC, WAD, m.navNow);
        m.netSubUSDC = m.subPending - m.matchedUSDC;
        m.netRedeemUSDC = redeemValueUSDC - m.matchedUSDC;

        emit MatchingPerformed(epoch, m.matchedUSDC, m.matchedShares);

        // --- Settle the net delta against custody ---
        if (m.netSubUSDC > 0) {
            (uint256 buyIll, uint256 buyLiq) = computeRebalanceBuy(m.netSubUSDC);
            usdc.forceApprove(address(custody), m.netSubUSDC);
            custody.depositUSDC(m.netSubUSDC);
            if (buyIll > 0) custody.subscribeToPruv(buyIll);
            if (buyLiq > 0) custody.swapUSDCForLiquid(buyLiq);
            emit NetSubSettled(epoch, m.netSubUSDC, buyIll, buyLiq);
        } else if (m.netRedeemUSDC > 0) {
            (uint256 fromLiquid, uint256 fromIlliquid) = _sourceRedemptionUSDC(m.netRedeemUSDC);
            custody.withdrawUSDC(address(this), m.netRedeemUSDC);
            emit NetRedeemSettled(epoch, m.netRedeemUSDC, fromLiquid, fromIlliquid);
        }

        // --- Per-request fulfilment bookkeeping ---
        _allocate(ids, m);

        // --- Supply changes: burn redeemed shares (locked in vault), mint subscriber shares ---
        if (m.redeemShares > 0) _burn(address(this), m.redeemShares);
        uint256 toMint = _sumSharesOwed(ids);
        if (toMint > 0) _mint(address(this), toMint);

        emit EpochProcessed(epoch, m.navNow, m.matchedUSDC, m.netSubUSDC, m.netRedeemUSDC);
        currentEpoch = epoch + 1;
    }

    function _snapshotQueues(uint256[] storage ids) internal view returns (uint256 subPending, uint256 redeemShares) {
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            Request storage r = requests[ids[i]];
            if (r.cancelled) continue;
            if (r.isDeposit) {
                subPending += r.amount;
            } else {
                redeemShares += r.amount;
            }
        }
    }

    /// @notice 3-layer sourcing for a net redemption: liquid buffer first, then illiquid Pruv.
    function _sourceRedemptionUSDC(uint256 needed) internal returns (uint256 fromLiquid, uint256 fromIlliquid) {
        uint256 remaining = needed;
        uint256 liquidAvail = custody.liquidBalance();
        uint256 take = Math.min(remaining, liquidAvail);
        if (take > 0) {
            custody.swapLiquidForUSDC(take);
            remaining -= take;
            fromLiquid = take;
        }
        if (remaining > 0) {
            // wRWA to redeem for the remaining USDC at the current price.
            uint256 wrwa = Math.mulDiv(remaining, WAD, navSource.pricePerWRWA());
            custody.redeemFromPruv(wrwa);
            fromIlliquid = remaining;
            // POC assumes Pruv fully fills; rollover is a documented deferred edge case.
        }
    }

    function _allocate(uint256[] storage ids, EpochMath memory m) internal {
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            Request storage r = requests[ids[i]];
            if (r.cancelled) continue;
            if (r.isDeposit) {
                r.sharesOwed = _depositSharesOwed(r.amount, m);
            } else {
                r.usdcOwed = _redeemUSDCOwed(r.amount, m);
            }
        }
    }

    function _depositSharesOwed(uint256 amount, EpochMath memory m) internal pure returns (uint256) {
        uint256 matchedSh = m.subPending == 0 ? 0 : Math.mulDiv(amount, m.matchedShares, m.subPending);
        if (m.netSubUSDC == 0 || m.navNow == 0) return matchedSh;
        uint256 userNetUSDC = amount - Math.mulDiv(amount, m.matchedUSDC, m.subPending);
        return matchedSh + Math.mulDiv(userNetUSDC, WAD, m.navNow);
    }

    function _redeemUSDCOwed(uint256 amount, EpochMath memory m) internal pure returns (uint256) {
        uint256 matchedU = m.redeemShares == 0 ? 0 : Math.mulDiv(amount, m.matchedUSDC, m.redeemShares);
        if (m.netRedeemUSDC == 0) return matchedU;
        uint256 userNetShares = amount - Math.mulDiv(amount, m.matchedShares, m.redeemShares);
        return matchedU + Math.mulDiv(userNetShares, m.navNow, WAD);
    }

    function _sumSharesOwed(uint256[] storage ids) internal view returns (uint256 total) {
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            Request storage r = requests[ids[i]];
            if (!r.cancelled && r.isDeposit) total += r.sharesOwed;
        }
    }

    /// @notice Rebalance-toward-target buy split for a net subscription (spec §6.2).
    function computeRebalanceBuy(uint256 netSubUSDC) public view returns (uint256 buyIlliquid, uint256 buyLiquid) {
        uint256 totalAfter = totalAssets() + netSubUSDC;
        uint256 targetIlliquid = Math.mulDiv(totalAfter, illiquidBps, BPS);
        uint256 targetLiquid = totalAfter - targetIlliquid;

        uint256 currentIlliquid = Math.mulDiv(custody.wRWABalance(), navSource.pricePerWRWA(), WAD);
        uint256 currentLiquid = custody.liquidBalance();

        buyIlliquid = currentIlliquid < targetIlliquid ? targetIlliquid - currentIlliquid : 0;
        buyLiquid = currentLiquid < targetLiquid ? targetLiquid - currentLiquid : 0;

        uint256 total = buyIlliquid + buyLiquid;
        if (total > netSubUSDC && total > 0) {
            buyIlliquid = Math.mulDiv(buyIlliquid, netSubUSDC, total);
            buyLiquid = Math.mulDiv(buyLiquid, netSubUSDC, total);
        } else if (total < netSubUSDC) {
            buyIlliquid += (netSubUSDC - total); // excess to illiquid (POC choice)
        }
    }

    // =============================================================
    //                        WIND-DOWN
    // =============================================================

    /// @inheritdoc IVault
    function triggerWindDown() external onlyOwner nonReentrant onlyState(State.EpochBased) {
        uint256 navNow = nav();
        state = State.WindDown;

        // 1. Refund pending sub requests; return locked redeem shares to their owners so that all
        //    outstanding shares are held by EOAs and settle pro-rata via claimWindDown().
        uint256[] storage ids = epochRequests[currentEpoch];
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            Request storage r = requests[ids[i]];
            if (r.cancelled || r.fulfilled) continue;
            r.cancelled = true;
            if (r.isDeposit) {
                usdc.safeTransfer(r.user, r.amount);
            } else {
                _transfer(address(this), r.user, r.amount);
            }
        }

        // 2. Liquidate the liquid buffer, then 3. the illiquid Pruv position, into USDC.
        uint256 liq = custody.liquidBalance();
        if (liq > 0) custody.swapLiquidForUSDC(liq);
        uint256 wrwa = custody.wRWABalance();
        if (wrwa > 0) custody.redeemFromPruv(wrwa);

        // 4. Move all custody USDC to the vault as the pro-rata pool.
        uint256 cu = custody.usdcBalance();
        if (cu > 0) custody.withdrawUSDC(address(this), cu);

        windDownUSDC = usdc.balanceOf(address(this));
        windDownSupply = totalSupply();
        windDownStart = block.timestamp;
        emit WindDownTriggered(navNow, windDownUSDC, windDownSupply);

        if (windDownSupply == 0) {
            state = State.Closed;
            emit PoolClosed();
        }
    }

    /// @notice Burn your shares for a pro-rata slice of the wind-down USDC pool.
    function claimWindDown() external nonReentrant onlyState(State.WindDown) {
        uint256 shares = balanceOf(msg.sender);
        if (shares == 0) revert NothingToClaim();
        uint256 payout = Math.mulDiv(shares, windDownUSDC, windDownSupply);
        _burn(msg.sender, shares);
        if (payout > 0) usdc.safeTransfer(msg.sender, payout);
        emit WindDownClaimed(msg.sender, shares, payout);
        if (totalSupply() == 0) {
            state = State.Closed;
            emit PoolClosed();
        }
    }

    /// @notice After the 30-day wind-down window, the admin closes the pool (sweeps dust).
    function closePool() external onlyOwner onlyState(State.WindDown) {
        if (block.timestamp < windDownStart + WIND_DOWN_PERIOD) revert WindDownNotComplete();
        state = State.Closed;
        uint256 dust = usdc.balanceOf(address(this));
        if (dust > 0) usdc.safeTransfer(owner(), dust);
        emit PoolClosed();
    }

    // =============================================================
    //                          VIEWS
    // =============================================================

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @inheritdoc IVault
    function totalAssets() public view returns (uint256) {
        if (address(navSource) == address(0)) return 0;
        uint256 illiquid = Math.mulDiv(custody.wRWABalance(), navSource.pricePerWRWA(), WAD);
        return illiquid + custody.liquidBalance();
    }

    /// @inheritdoc IVault
    function nav() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return Math.mulDiv(totalAssets(), WAD, supply);
    }

    /// @inheritdoc IVault
    function pendingSubAmount(address user) external view returns (uint256 amount) {
        uint256[] storage ids = epochRequests[currentEpoch];
        for (uint256 i = 0; i < ids.length; i++) {
            Request storage r = requests[ids[i]];
            if (r.user == user && r.isDeposit && !r.cancelled) amount += r.amount;
        }
    }

    /// @inheritdoc IVault
    function pendingRedeemShares(address user) external view returns (uint256 shares) {
        uint256[] storage ids = epochRequests[currentEpoch];
        for (uint256 i = 0; i < ids.length; i++) {
            Request storage r = requests[ids[i]];
            if (r.user == user && !r.isDeposit && !r.cancelled) shares += r.amount;
        }
    }
}
