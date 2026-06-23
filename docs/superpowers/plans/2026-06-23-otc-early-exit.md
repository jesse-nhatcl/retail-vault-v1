# OTC Early-Exit Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Layer 0" OTC early-exit market over `rACCESS` shares so a holder can exit *now* at a discount instead of waiting for the redemption queue; unmatched volume falls through to the existing queue.

**Architecture:** Buyer-first resting bids on a fixed discount ladder. A buyer escrows USDC into an on-chain bid book; a seller's `sell()` tx reads NAV, sweeps bids cheapest-first, and settles atomically — no keeper. Phase 0 swaps shares↔USDC directly (cheapest MVP). Phase 1 wraps each fill in a per-bid `BidVault` (ERC-4626 + LP token) that auto-redeems through the existing `Vault`. The core `Vault`/`Custody` are untouched. Spec: `docs/07-otc-early-exit-alt1-1a-breakdown.md`.

**Tech Stack:** Solidity 0.8.24 (pinned), Foundry, OpenZeppelin (`Math.mulDiv`, `SafeERC20`, `ERC20`, `Ownable`, `ReentrancyGuard`, `IERC20`). TDD per `.claude/rules/testing.md` and `.claude/rules/solidity.md`.

---

## Background the engineer needs

- **`rACCESS` shares ARE the `Vault` contract** (`contract Vault is IVault, ERC20, ...`). To move shares, call `vault.transferFrom` / `vault.approve` / `vault.balanceOf`. Decimals: **shares 18-dec, USDC 6-dec**.
- **NAV:** `vault.nav()` (public view) returns price scaled so that USDC value of `sharesAmt` (18-dec) is `Math.mulDiv(sharesAmt, nav, 1e18)` → 6-dec USDC. At parity `nav ≈ 1e6`. (See `CLAUDE.md` decimal table; verified by S7.)
- **Discounted price:** a bid at `discountBps` pays `(10000 - discountBps)/10000` of NAV value. The shares a bid's `usdcIn` buys: `sharesForBid = mulDiv( mulDiv(usdcIn, 1e18, nav), 10000, 10000 - discountBps )`.
- **State:** OTC only operates while `vault.state() == IVault.State.EpochBased`. On wind-down the market must refund open bids.
- **Conventions (binding):** custom errors only (no `require` strings); every state mutation emits an event; `nonReentrant` on value-moving externals; `SafeERC20` for transfers; `Math.mulDiv` for all cross-decimal math; cap per-tx loop iteration at 100; NatSpec on every `external`/`public`; `external` over `public`; `0.8.24` pinned, no caret.
- **Reused test harness:** `test/helpers/Fixture.sol` gives funded actors (`alice`/`bob`/`charlie`, 1,000,000e6 USDC each) and helpers to reach `EpochBased`. A seller gets shares via launchpad → `claimLaunchpadShares`.

---

## File Structure

**Phase 0 (MVP — atomic discounted swap):**
- Create `src/interfaces/IOTCMarket.sol` — external surface + errors + events + structs.
- Create `src/otc/OTCMarket.sol` — bid book, `placeBid`, `cancelBid`, `sell`, `closeForWindDown`, views. Phase 0 transfers shares straight to the buyer.
- Create `test/helpers/OTCFixture.sol` — extends `Fixture`, reaches `EpochBased`, gives `alice` shares, deploys `OTCMarket`.
- Create `test/otc/OTCMarket.t.sol` — unit tests.
- Create `test/otc/scenarios/OTC1_FullFill.t.sol` … `OTC6_Reverts.t.sol` — acceptance scenarios.

**Phase 1 (variant 1a wrapper):**
- Create `src/interfaces/IBidVault.sol`.
- Create `src/otc/BidVault.sol` — per-bid ERC-4626-style escrow + LP token + auto `requestRedeem`/`claim`.
- Create `src/otc/OTCFactory.sol` — deploys `BidVault` per fill.
- Modify `src/otc/OTCMarket.sol` — on fill, deploy a `BidVault` (via factory) instead of transferring shares to the buyer; track `bidVault` per fill.
- Add `test/otc/BidVault.t.sol`, `test/otc/OTCFactory.t.sol`; extend scenarios for LP redemption.

**Phase 2 (optional, deferred):** off-chain matching helper + `settleBatch`, EIP-712 signed bids. Outlined only.

---

# PHASE 0 — OTCMarket: on-chain atomic discounted swap

### Task 0.1: Interface, errors, events, structs

**Files:**
- Create: `src/interfaces/IOTCMarket.sol`

- [ ] **Step 1: Write the interface file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOTCMarket
/// @notice Layer-0 early-exit OTC market over rACCESS shares. Buyer-first resting bids on a
///         fixed discount ladder; a seller's `sell` sweeps them cheapest-first and settles on-chain.
interface IOTCMarket {
    enum BidStatus { Resting, Matched, Cancelled }

    struct Bid {
        address buyer;
        uint16 discountBps; // must be on the fixed ladder
        uint256 usdcRemaining; // 6-dec, escrowed; decremented as the bid is filled
        BidStatus status;
    }

    error OffLadder(uint16 discountBps);
    error ZeroAmount();
    error NotBidOwner();
    error BidNotResting();
    error MarketClosed(); // vault not in EpochBased
    error NoFill(); // sell() matched nothing at/under the floor
    error TooManyBids();

    event BidPlaced(uint256 indexed bidId, address indexed buyer, uint16 discountBps, uint256 usdcIn);
    event BidCancelled(uint256 indexed bidId, uint256 usdcRefunded);
    event Sold(address indexed seller, uint256 sharesSold, uint256 usdcReceived, uint256 sharesReturned);
    event BidFilled(uint256 indexed bidId, address indexed buyer, uint256 shares, uint256 usdcPaid);
    event MarketClosedForWindDown(uint256 bidsRefunded);

    function placeBid(uint16 discountBps, uint256 usdcIn) external returns (uint256 bidId);
    function cancelBid(uint256 bidId) external;
    function sell(uint256 shares, uint16 maxDiscountBps) external returns (uint256 sharesSold);
    function closeForWindDown() external;

    function ladder() external view returns (uint16[] memory);
    function restingBids(uint16 discountBps) external view returns (uint256[] memory);
}
```

- [ ] **Step 2: Compile to verify the interface is valid**

Run: `forge build`
Expected: compiles (no implementors yet, so no errors).

- [ ] **Step 3: Commit**

```bash
git add src/interfaces/IOTCMarket.sol
git commit -m "feat: add IOTCMarket interface"
```

---

### Task 0.2: OTCMarket skeleton — constructor, ladder, state guard

**Files:**
- Create: `src/otc/OTCMarket.sol`
- Create: `test/helpers/OTCFixture.sol`
- Create: `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: Write the OTC fixture**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Fixture} from "../helpers/Fixture.sol";
import {OTCMarket} from "../../src/otc/OTCMarket.sol";

/// @notice Reaches EpochBased with `alice` holding shares, then deploys an OTCMarket
///         with a {1%,2.5%,5%,10%} discount ladder. Buyers bob/charlie keep their funded USDC.
abstract contract OTCFixture is Fixture {
    OTCMarket internal otc;
    uint16[] internal LADDER; // 100, 250, 500, 1000 bps

    function _setUpOTC() internal {
        _deploy(50_000e6);
        _startLaunchpad();
        _launchpadDeposit(alice, 100_000e6); // alice seeds the whole vault
        _finalizeLaunchpad(); // -> EpochBased, 100_000e18 shares minted to vault
        _claimLaunchpad(alice); // alice now holds 100_000e18 rACCESS shares

        LADDER.push(100);
        LADDER.push(250);
        LADDER.push(500);
        LADDER.push(1000);
        otc = new OTCMarket(address(vault), usdc, LADDER);
    }

    function _placeBid(address who, uint16 discountBps, uint256 usdcIn) internal returns (uint256 id) {
        vm.startPrank(who);
        usdc.approve(address(otc), usdcIn);
        id = otc.placeBid(discountBps, usdcIn);
        vm.stopPrank();
    }

    function _sell(address who, uint256 shares, uint16 maxDiscountBps) internal returns (uint256 sold) {
        vm.startPrank(who);
        vault.approve(address(otc), shares);
        sold = otc.sell(shares, maxDiscountBps);
        vm.stopPrank();
    }
}
```

- [ ] **Step 2: Write the failing test for ladder config + state guard**

`test/otc/OTCMarket.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../src/interfaces/IOTCMarket.sol";

contract OTCMarketTest is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_LadderConfigured() public {
        uint16[] memory l = otc.ladder();
        assertEq(l.length, 4);
        assertEq(l[0], 100);
        assertEq(l[3], 1000);
    }

    function test_Revert_PlaceBidOffLadder() public {
        vm.startPrank(bob);
        usdc.approve(address(otc), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IOTCMarket.OffLadder.selector, uint16(300)));
        otc.placeBid(300, 1_000e6);
        vm.stopPrank();
    }
}
```

- [ ] **Step 3: Run to verify it fails (no OTCMarket yet)**

Run: `forge test --match-contract OTCMarketTest -vvv`
Expected: FAIL — `OTCMarket` not found / does not compile.

- [ ] **Step 4: Write the OTCMarket skeleton**

`src/otc/OTCMarket.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOTCMarket} from "../interfaces/IOTCMarket.sol";
import {IVault} from "../interfaces/IVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice See docs/07-otc-early-exit-alt1-1a-breakdown.md. Phase 0: swaps shares straight to buyers.
contract OTCMarket is IOTCMarket, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_SCAN = 100; // gas bound, mirrors Vault's per-epoch cap
    uint16 internal constant BPS = 10000;

    IVault public immutable vault; // also the rACCESS ERC20
    IERC20 public immutable shareToken;
    IERC20 public immutable usdc;

    uint16[] internal _ladder;
    mapping(uint16 => bool) public onLadder;

    Bid[] public bids; // bidId = index
    mapping(uint16 => uint256[]) internal _book; // discountBps -> FIFO bidIds

    constructor(address vault_, MockUSDC usdc_, uint16[] memory ladder_) {
        vault = IVault(vault_);
        shareToken = IERC20(vault_);
        usdc = IERC20(address(usdc_));
        for (uint256 i = 0; i < ladder_.length; i++) {
            _ladder.push(ladder_[i]);
            onLadder[ladder_[i]] = true;
        }
    }

    modifier marketOpen() {
        if (vault.state() != IVault.State.EpochBased) revert MarketClosed();
        _;
    }

    function ladder() external view returns (uint16[] memory) {
        return _ladder;
    }

    function restingBids(uint16 discountBps) external view returns (uint256[] memory) {
        return _book[discountBps];
    }

    function placeBid(uint16, uint256) external returns (uint256) {
        revert ZeroAmount(); // implemented in Task 0.3
    }

    function cancelBid(uint256) external {
        revert BidNotResting(); // implemented in Task 0.4
    }

    function sell(uint256, uint16) external returns (uint256) {
        revert NoFill(); // implemented in Task 0.5
    }

    function closeForWindDown() external {
        revert MarketClosed(); // implemented in Task 0.6
    }
}
```

- [ ] **Step 5: Add the OpenZeppelin remapping check**

Run: `grep -r "@openzeppelin" remappings.txt foundry.toml 2>/dev/null; ls lib/openzeppelin-contracts/contracts/utils/math/Math.sol`
Expected: the `@openzeppelin/contracts/` remapping resolves (it is already used by `Vault.sol`). If `Vault.sol` imports OZ via a different path, match that exact import prefix instead.

- [ ] **Step 6: Run the test to verify it passes**

Run: `forge test --match-contract OTCMarketTest -vvv`
Expected: `test_LadderConfigured` PASS, `test_Revert_PlaceBidOffLadder` FAIL (placeBid reverts with ZeroAmount, not OffLadder) — that is expected; it is fixed in Task 0.3. Confirm `test_LadderConfigured` passes and the contract compiles.

- [ ] **Step 7: Commit**

```bash
git add src/otc/OTCMarket.sol test/helpers/OTCFixture.sol test/otc/OTCMarket.t.sol
git commit -m "feat: add OTCMarket skeleton with ladder + state guard"
```

---

### Task 0.3: `placeBid` — escrow USDC, push to book

**Files:**
- Modify: `src/otc/OTCMarket.sol`
- Modify: `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: Write failing tests**

Add to `OTCMarketTest`:

```solidity
function test_PlaceBidEscrowsAndBooks() public {
    uint256 balBefore = usdc.balanceOf(bob);
    uint256 id = _placeBid(bob, 500, 1_000e6);

    assertEq(id, 0);
    assertEq(usdc.balanceOf(bob), balBefore - 1_000e6);
    assertEq(usdc.balanceOf(address(otc)), 1_000e6);
    uint256[] memory book = otc.restingBids(500);
    assertEq(book.length, 1);
    assertEq(book[0], 0);
}

function test_Revert_PlaceBidZero() public {
    vm.prank(bob);
    vm.expectRevert(IOTCMarket.ZeroAmount.selector);
    otc.placeBid(500, 0);
}
```

- [ ] **Step 2: Run to verify failure**

Run: `forge test --match-test test_PlaceBid -vvv`
Expected: FAIL (current `placeBid` always reverts `ZeroAmount`).

- [ ] **Step 3: Implement `placeBid`**

Replace the stub:

```solidity
function placeBid(uint16 discountBps, uint256 usdcIn)
    external
    nonReentrant
    marketOpen
    returns (uint256 bidId)
{
    if (usdcIn == 0) revert ZeroAmount();
    if (!onLadder[discountBps]) revert OffLadder(discountBps);

    usdc.safeTransferFrom(msg.sender, address(this), usdcIn);

    bidId = bids.length;
    bids.push(Bid({buyer: msg.sender, discountBps: discountBps, usdcRemaining: usdcIn, status: BidStatus.Resting}));
    _book[discountBps].push(bidId);

    emit BidPlaced(bidId, msg.sender, discountBps, usdcIn);
}
```

- [ ] **Step 4: Run to verify pass**

Run: `forge test --match-test test_PlaceBid -vvv && forge test --match-test test_Revert_PlaceBid -vvv`
Expected: all PASS (including the off-ladder revert from Task 0.2).

- [ ] **Step 5: Commit**

```bash
git add src/otc/OTCMarket.sol test/otc/OTCMarket.t.sol
git commit -m "feat: OTCMarket.placeBid escrows USDC into the bid book"
```

---

### Task 0.4: `cancelBid` — refund a resting bid

**Files:**
- Modify: `src/otc/OTCMarket.sol`
- Modify: `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: Write failing tests**

```solidity
function test_CancelBidRefunds() public {
    uint256 id = _placeBid(bob, 500, 1_000e6);
    uint256 balBefore = usdc.balanceOf(bob);

    vm.prank(bob);
    otc.cancelBid(id);

    assertEq(usdc.balanceOf(bob), balBefore + 1_000e6);
    (, , uint256 rem, IOTCMarket.BidStatus status) = otc.bids(id);
    assertEq(rem, 0);
    assertEq(uint8(status), uint8(IOTCMarket.BidStatus.Cancelled));
}

function test_Revert_CancelBidNotOwner() public {
    uint256 id = _placeBid(bob, 500, 1_000e6);
    vm.prank(charlie);
    vm.expectRevert(IOTCMarket.NotBidOwner.selector);
    otc.cancelBid(id);
}
```

> Note: `bids(id)` is the public array getter; it returns the struct fields in order `(buyer, discountBps, usdcRemaining, status)`.

- [ ] **Step 2: Run to verify failure**

Run: `forge test --match-test test_CancelBid -vvv && forge test --match-test test_Revert_CancelBid -vvv`
Expected: FAIL (stub reverts `BidNotResting`).

- [ ] **Step 3: Implement `cancelBid`**

```solidity
function cancelBid(uint256 bidId) external nonReentrant {
    Bid storage b = bids[bidId];
    if (b.buyer != msg.sender) revert NotBidOwner();
    if (b.status != BidStatus.Resting) revert BidNotResting();

    uint256 refund = b.usdcRemaining;
    b.usdcRemaining = 0;
    b.status = BidStatus.Cancelled;
    usdc.safeTransfer(msg.sender, refund);

    emit BidCancelled(bidId, refund);
}
```

> Cancelled bids stay in `_book` and are skipped during `sell()` iteration (never deleted/reindexed — mirrors the Vault queue convention).

- [ ] **Step 4: Run to verify pass**

Run: `forge test --match-test test_CancelBid -vvv && forge test --match-test test_Revert_CancelBid -vvv`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/otc/OTCMarket.sol test/otc/OTCMarket.t.sol
git commit -m "feat: OTCMarket.cancelBid refunds resting bids"
```

---

### Task 0.5: `sell` — cheapest-first sweep, atomic settle (Phase 0)

**Files:**
- Modify: `src/otc/OTCMarket.sol`
- Modify: `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: Write the failing full-fill test**

Numbers: NAV at parity = `1e6`. A 5% bid pays 0.95 USDC/share. `bob` bids `9_500e6` USDC at 500 bps → buys `9_500e6 / 0.95 = 10_000e18` shares. `alice` sells 10,000 shares with floor 1000 bps.

```solidity
function test_Sell_FullFill_5pct() public {
    uint256 id = _placeBid(bob, 500, 9_500e6); // buys exactly 10,000 shares at 5% off

    uint256 aliceUsdcBefore = usdc.balanceOf(alice);
    uint256 sold = _sell(alice, 10_000e18, 1000);

    assertEq(sold, 10_000e18);
    assertEq(usdc.balanceOf(alice), aliceUsdcBefore + 9_500e6); // seller paid discounted USDC
    assertEq(vault.balanceOf(bob), 10_000e18); // Phase 0: buyer receives shares directly
    assertEq(usdc.balanceOf(address(otc)), 0); // bid fully consumed
    (, , uint256 rem, IOTCMarket.BidStatus status) = otc.bids(id);
    assertEq(rem, 0);
    assertEq(uint8(status), uint8(IOTCMarket.BidStatus.Matched));
}
```

- [ ] **Step 2: Run to verify failure**

Run: `forge test --match-test test_Sell_FullFill_5pct -vvv`
Expected: FAIL (stub reverts `NoFill`).

- [ ] **Step 3: Implement pricing helper + `sell`**

Add the helper and replace the `sell` stub:

```solidity
/// @notice Shares (18-dec) that `usdcIn` (6-dec) buys at `discountBps` off the current NAV.
function _sharesForUsdc(uint256 usdcIn, uint16 discountBps, uint256 navNow) internal pure returns (uint256) {
    uint256 atNav = Math.mulDiv(usdcIn, 1e18, navNow); // shares at full NAV
    return Math.mulDiv(atNav, BPS, BPS - discountBps); // more shares because discounted
}

function sell(uint256 shares, uint16 maxDiscountBps)
    external
    nonReentrant
    marketOpen
    returns (uint256 sharesSold)
{
    if (shares == 0) revert ZeroAmount();
    shareToken.safeTransferFrom(msg.sender, address(this), shares);

    uint256 navNow = vault.nav();
    uint256 remaining = shares;
    uint256 usdcToSeller;
    uint256 scanned;

    for (uint256 t = 0; t < _ladder.length && remaining > 0; t++) {
        uint16 d = _ladder[t];
        if (d > maxDiscountBps) break; // ladder is ascending; nothing cheaper enough left
        uint256[] storage q = _book[d];
        for (uint256 i = 0; i < q.length && remaining > 0; i++) {
            if (scanned++ >= MAX_SCAN) break;
            Bid storage b = bids[q[i]];
            if (b.status != BidStatus.Resting || b.usdcRemaining == 0) continue;

            uint256 bidShares = _sharesForUsdc(b.usdcRemaining, d, navNow);
            uint256 fill = bidShares < remaining ? bidShares : remaining;
            uint256 usdcPaid = Math.mulDiv(b.usdcRemaining, fill, bidShares);

            b.usdcRemaining -= usdcPaid;
            if (fill == bidShares) b.status = BidStatus.Matched;
            remaining -= fill;
            usdcToSeller += usdcPaid;

            shareToken.safeTransfer(b.buyer, fill); // Phase 0: buyer gets shares directly
            emit BidFilled(q[i], b.buyer, fill, usdcPaid);
        }
    }

    if (usdcToSeller == 0) revert NoFill();

    sharesSold = shares - remaining;
    if (remaining > 0) shareToken.safeTransfer(msg.sender, remaining); // return unsold
    usdc.safeTransfer(msg.sender, usdcToSeller);

    emit Sold(msg.sender, sharesSold, usdcToSeller, remaining);
}
```

- [ ] **Step 4: Run to verify pass**

Run: `forge test --match-test test_Sell_FullFill_5pct -vvv`
Expected: PASS.

- [ ] **Step 5: Add cheapest-first + partial-fill + floor tests**

```solidity
function test_Sell_CheapestFirst() public {
    _placeBid(charlie, 1000, 9_000e6); // 10% bid → 10,000 shares, but should fill LAST
    _placeBid(bob, 500, 4_750e6); // 5% bid → 5,000 shares, fills FIRST

    _sell(alice, 5_000e18, 1000);

    assertEq(vault.balanceOf(bob), 5_000e18); // 5% filled entirely
    assertEq(vault.balanceOf(charlie), 0); // 10% untouched
}

function test_Sell_PartialReturnsUnsold() public {
    _placeBid(bob, 500, 4_750e6); // buys 5,000 shares
    uint256 aliceSharesBefore = vault.balanceOf(alice);

    uint256 sold = _sell(alice, 8_000e18, 1000); // only 5,000 of demand exists

    assertEq(sold, 5_000e18);
    assertEq(vault.balanceOf(alice), aliceSharesBefore - 5_000e18); // 3,000 returned
}

function test_Revert_Sell_NoBidUnderFloor() public {
    _placeBid(bob, 1000, 9_000e6); // only a 10% bid exists
    vm.startPrank(alice);
    vault.approve(address(otc), 1_000e18);
    vm.expectRevert(IOTCMarket.NoFill.selector);
    otc.sell(1_000e18, 500); // floor 5% → 10% bid is too expensive
    vm.stopPrank();
}
```

- [ ] **Step 6: Run to verify pass**

Run: `forge test --match-contract OTCMarketTest -vvv`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add src/otc/OTCMarket.sol test/otc/OTCMarket.t.sol
git commit -m "feat: OTCMarket.sell cheapest-first on-chain matching"
```

---

### Task 0.6: `closeForWindDown` — refund open bids

**Files:**
- Modify: `src/otc/OTCMarket.sol`
- Modify: `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: Write failing test**

```solidity
function test_CloseForWindDown_RefundsOpenBids() public {
    _placeBid(bob, 500, 1_000e6);
    _placeBid(charlie, 1000, 2_000e6);
    uint256 bobBefore = usdc.balanceOf(bob);
    uint256 charlieBefore = usdc.balanceOf(charlie);

    // admin (test contract owns the vault) triggers wind-down, then closes the market
    vault.triggerWindDown();
    otc.closeForWindDown();

    assertEq(usdc.balanceOf(bob), bobBefore + 1_000e6);
    assertEq(usdc.balanceOf(charlie), charlieBefore + 2_000e6);
    assertEq(usdc.balanceOf(address(otc)), 0);
}
```

- [ ] **Step 2: Run to verify failure**

Run: `forge test --match-test test_CloseForWindDown -vvv`
Expected: FAIL (stub reverts).

- [ ] **Step 3: Implement `closeForWindDown`**

```solidity
/// @notice Once the vault leaves EpochBased, refund every resting bid. Permissionless (idempotent).
function closeForWindDown() external nonReentrant {
    if (vault.state() == IVault.State.EpochBased) revert MarketClosed();
    uint256 count;
    for (uint256 i = 0; i < bids.length; i++) {
        Bid storage b = bids[i];
        if (b.status == BidStatus.Resting && b.usdcRemaining > 0) {
            uint256 refund = b.usdcRemaining;
            b.usdcRemaining = 0;
            b.status = BidStatus.Cancelled;
            usdc.safeTransfer(b.buyer, refund);
            count++;
        }
    }
    emit MarketClosedForWindDown(count);
}
```

> `MarketClosed` here means the opposite guard from `marketOpen`: this only runs *after* the vault has left `EpochBased`. The reused error name keeps the surface small; if clarity matters, add `error StillOpen();` and use it instead.

- [ ] **Step 4: Run to verify pass**

Run: `forge test --match-contract OTCMarketTest -vvv`
Expected: all PASS.

- [ ] **Step 5: Run the full suite + format**

Run: `forge test && forge fmt --check`
Expected: green; fmt clean. (Fix formatting with `forge fmt` if needed.)

- [ ] **Step 6: Commit**

```bash
git add src/otc/OTCMarket.sol test/otc/OTCMarket.t.sol
git commit -m "feat: OTCMarket.closeForWindDown refunds open bids"
```

---

### Task 0.7: Acceptance scenarios OTC-1, OTC-2, OTC-6

**Files:**
- Create: `test/otc/scenarios/OTC1_FullFill.t.sol`
- Create: `test/otc/scenarios/OTC2_PartialToQueue.t.sol`
- Create: `test/otc/scenarios/OTC6_Reverts.t.sol`

- [ ] **Step 1: Write OTC-1 (full fill, buyer then redeems via the existing queue)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

/// @notice OTC-1: seller exits at 5% discount; buyer later redeems the shares at full NAV (profit = discount).
contract OTC1_FullFill is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_SellerExitsBuyerRedeemsAtNav() public {
        _placeBid(bob, 500, 9_500e6); // 10,000 shares at 5% off
        uint256 aliceUsdc = usdc.balanceOf(alice);

        _sell(alice, 10_000e18, 1000);
        assertEq(usdc.balanceOf(alice), aliceUsdc + 9_500e6); // fast exit, absorbed the 5%

        // buyer redeems the bought shares through the normal queue at full NAV
        uint256 rid = _requestRedeem(bob, 10_000e18);
        pruv.setPrice(1e18); // NAV unchanged
        vault.processEpoch();
        uint256 bobUsdc = usdc.balanceOf(bob);
        _claim(bob, rid);
        assertEq(usdc.balanceOf(bob), bobUsdc + 10_000e6); // got full NAV → profit = 500 USDC
    }
}
```

- [ ] **Step 2: Write OTC-2 (partial fill → seller routes remainder to the queue)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

/// @notice OTC-2: only part of the lot finds buyers; the rest redeems normally at NAV.
contract OTC2_PartialToQueue is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_UnsoldGoesToQueue() public {
        _placeBid(bob, 500, 4_750e6); // demand for 5,000 shares only
        uint256 sold = _sell(alice, 8_000e18, 1000);
        assertEq(sold, 5_000e18);

        // alice routes the unsold 3,000 shares through the normal redeem queue
        uint256 rid = _requestRedeem(alice, 3_000e18);
        pruv.setPrice(1e18);
        vault.processEpoch();
        uint256 before = usdc.balanceOf(alice);
        _claim(alice, rid);
        assertEq(usdc.balanceOf(alice), before + 3_000e6); // full NAV on the remainder
    }
}
```

- [ ] **Step 3: Write OTC-6 (reverts)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";
import {IOTCMarket} from "../../../src/interfaces/IOTCMarket.sol";

contract OTC6_Reverts is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_Revert_OffLadder() public {
        vm.startPrank(bob);
        usdc.approve(address(otc), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IOTCMarket.OffLadder.selector, uint16(300)));
        otc.placeBid(300, 1_000e6);
        vm.stopPrank();
    }

    function test_Revert_SellNoFillUnderFloor() public {
        _placeBid(bob, 1000, 9_000e6);
        vm.startPrank(alice);
        vault.approve(address(otc), 1_000e18);
        vm.expectRevert(IOTCMarket.NoFill.selector);
        otc.sell(1_000e18, 500);
        vm.stopPrank();
    }

    function test_Revert_PlaceBidAfterWindDown() public {
        vault.triggerWindDown();
        vm.startPrank(bob);
        usdc.approve(address(otc), 1_000e6);
        vm.expectRevert(IOTCMarket.MarketClosed.selector);
        otc.placeBid(500, 1_000e6);
        vm.stopPrank();
    }
}
```

- [ ] **Step 4: Run all OTC scenarios**

Run: `forge test --match-path 'test/otc/*' -vvv`
Expected: all PASS.

- [ ] **Step 5: Format + commit**

```bash
forge fmt
git add test/otc/scenarios
git commit -m "test: OTC-1/2/6 acceptance scenarios for Phase 0"
```

---

### Task 0.8: Invariant test for Phase 0

**Files:**
- Create: `test/otc/OTCInvariant.t.sol`

- [ ] **Step 1: Write the invariant**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";

/// @notice The OTC contract must never hold more USDC than the sum of resting bids' usdcRemaining,
///         i.e. escrow is always fully refundable until matched (no leakage).
contract OTCInvariant is OTCFixture {
    function setUp() public {
        _setUpOTC();
        targetContract(address(otc));
    }

    function invariant_EscrowFullyBacked() public view {
        uint256 owed;
        // bids array length is bounded in tests; iterate defensively
        for (uint256 i = 0; i < 64; i++) {
            try otc.bids(i) returns (address, uint16, uint256 rem, OTCFixtureStatus) {
                owed += rem;
            } catch {
                break;
            }
        }
        assertGe(usdc.balanceOf(address(otc)), owed);
    }
}
```

> If the `try/catch` over the public getter is awkward to type against the enum, simpler: add a view `totalEscrowed()` to `OTCMarket` that sums `usdcRemaining` of resting bids (bounded by `bids.length`, cap 100) and assert `usdc.balanceOf(address(otc)) >= totalEscrowed()`. Prefer the view helper.

- [ ] **Step 2: If using the view helper, add it to OTCMarket**

```solidity
function totalEscrowed() external view returns (uint256 sum) {
    uint256 n = bids.length;
    for (uint256 i = 0; i < n && i < 100; i++) {
        if (bids[i].status == BidStatus.Resting) sum += bids[i].usdcRemaining;
    }
}
```

Then the invariant body is `assertGe(usdc.balanceOf(address(otc)), otc.totalEscrowed());`.

- [ ] **Step 3: Run**

Run: `forge test --match-contract OTCInvariant -vvv`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
forge fmt
git add src/otc/OTCMarket.sol test/otc/OTCInvariant.t.sol
git commit -m "test: OTC escrow-fully-backed invariant"
```

**END OF PHASE 0 — early-exit works end to end (seller exits at a discount; buyer holds/redeems shares).**

---

# PHASE 1 — variant 1a wrapper (BidVault + LP token + auto-redeem)

Goal: instead of transferring shares straight to the buyer, each fill creates a per-bid `BidVault` that (a) holds the shares, (b) issues an LP token to the buyer, (c) `requestRedeem`s the shares through the existing `Vault`, and (d) lets the buyer `redeem` the LP for the NAV USDC after the epoch.

### Task 1.1: IBidVault + BidVault (escrow, LP token, auto-redeem)

**Files:**
- Create: `src/interfaces/IBidVault.sol`
- Create: `src/otc/BidVault.sol`
- Create: `test/otc/BidVault.t.sol`

- [ ] **Step 1: Write `IBidVault`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IBidVault {
    error NotMarket();
    error NothingToClaim();

    event RedemptionClaimed(uint256 usdc);
    event LpRedeemed(address indexed holder, uint256 lp, uint256 usdc);

    function buyer() external view returns (address);
    function shares() external view returns (uint256);
    function claimRedemption() external; // pull settled USDC from the Vault
    function redeem(uint256 lp) external returns (uint256 usdcOut);
}
```

- [ ] **Step 2: Write the failing BidVault test**

`test/otc/BidVault.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {BidVault} from "../../src/otc/BidVault.sol";

contract BidVaultTest is OTCFixture {
    function setUp() public {
        _setUpOTC();
    }

    function test_HoldsSharesMintsLpAndQueuesRedeem() public {
        // simulate the market: move 1,000 shares from alice to a fresh BidVault for bob
        BidVault bv = new BidVault(address(vault), usdc, bob, 1_000e18);
        vm.prank(alice);
        vault.transfer(address(bv), 1_000e18);
        bv.initRedeem(); // requestRedeem(1,000) on behalf of the vault

        assertEq(bv.balanceOf(bob), 1_000e18); // LP minted 1:1
        assertEq(bv.shares(), 1_000e18);

        // settle the epoch at NAV, then claim + redeem LP
        pruv.setPrice(1e18);
        vault.processEpoch();
        bv.claimRedemption();
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        bv.redeem(1_000e18);
        assertEq(usdc.balanceOf(bob), bobBefore + 1_000e6);
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `forge test --match-contract BidVaultTest -vvv`
Expected: FAIL (`BidVault` not found).

- [ ] **Step 4: Implement `BidVault`**

```solidity
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

    address public immutable market;
    IVault public immutable vault;
    IERC20 public immutable usdc;
    address public immutable buyer;
    uint256 public immutable shares;
    uint256 public redeemRequestId;
    bool public redeemInitiated;

    constructor(address vault_, MockUSDC usdc_, address buyer_, uint256 shares_)
        ERC20("OTC BidVault LP", "otcLP")
    {
        market = msg.sender;
        vault = IVault(vault_);
        usdc = IERC20(address(usdc_));
        buyer = buyer_;
        shares = shares_;
        _mint(buyer_, shares_); // LP 1:1 with shares held
    }

    /// @notice Queue the held shares for redemption through the Vault. Callable once by the market.
    function initRedeem() external {
        if (msg.sender != market && redeemInitiated) revert NotMarket();
        require(!redeemInitiated, "init");
        redeemInitiated = true;
        redeemRequestId = vault.requestRedeem(shares);
    }

    function claimRedemption() external nonReentrant {
        vault.claim(redeemRequestId); // pulls USDC into this vault
        emit RedemptionClaimed(usdc.balanceOf(address(this)));
    }

    function redeem(uint256 lp) external nonReentrant returns (uint256 usdcOut) {
        if (lp == 0 || balanceOf(msg.sender) < lp) revert NothingToClaim();
        usdcOut = Math.mulDiv(usdc.balanceOf(address(this)), lp, totalSupply());
        _burn(msg.sender, lp);
        usdc.safeTransfer(msg.sender, usdcOut);
        emit LpRedeemed(msg.sender, lp, usdcOut);
    }
}
```

> **Note for the implementer:** the `initRedeem`/`NotMarket` guard above is intentionally minimal for the unit test. In Task 1.3 the market calls `initRedeem` immediately after deploying+funding the vault, so harden it then: make `initRedeem` strictly `if (msg.sender != market) revert NotMarket();` and drop the `require`. The unit test calls it directly (the test is the deployer = `market`), so it passes either way.

- [ ] **Step 5: Run to verify pass**

Run: `forge test --match-contract BidVaultTest -vvv`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
forge fmt
git add src/interfaces/IBidVault.sol src/otc/BidVault.sol test/otc/BidVault.t.sol
git commit -m "feat: BidVault escrows shares, mints LP, auto-redeems via Vault"
```

---

### Task 1.2: OTCFactory

**Files:**
- Create: `src/otc/OTCFactory.sol`
- Create: `test/otc/OTCFactory.t.sol`

- [ ] **Step 1: Write failing test**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../helpers/OTCFixture.sol";
import {OTCFactory} from "../../src/otc/OTCFactory.sol";
import {BidVault} from "../../src/otc/BidVault.sol";

contract OTCFactoryTest is OTCFixture {
    function test_DeploysBidVault() public {
        _setUpOTC();
        OTCFactory f = new OTCFactory();
        address bv = f.createBidVault(address(vault), usdc, bob, 1_000e18);
        assertEq(BidVault(bv).buyer(), bob);
        assertEq(BidVault(bv).shares(), 1_000e18);
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `forge test --match-contract OTCFactoryTest -vvv`
Expected: FAIL (`OTCFactory` not found).

- [ ] **Step 3: Implement `OTCFactory`**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BidVault} from "./BidVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @notice Deploys one BidVault per OTC fill. Stateless.
contract OTCFactory {
    event BidVaultCreated(address indexed vault, address indexed buyer, uint256 shares);

    function createBidVault(address vault_, MockUSDC usdc_, address buyer_, uint256 shares_)
        external
        returns (address bidVault)
    {
        bidVault = address(new BidVault(vault_, usdc_, buyer_, shares_));
        emit BidVaultCreated(bidVault, buyer_, shares_);
    }
}
```

- [ ] **Step 4: Run to verify pass + commit**

Run: `forge test --match-contract OTCFactoryTest -vvv`
Expected: PASS.

```bash
forge fmt
git add src/otc/OTCFactory.sol test/otc/OTCFactory.t.sol
git commit -m "feat: OTCFactory deploys per-bid BidVaults"
```

---

### Task 1.3: Wire OTCMarket.sell to deploy BidVaults

**Files:**
- Modify: `src/otc/OTCMarket.sol`
- Modify: `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: Write failing test (buyer should get LP, not shares)**

```solidity
function test_Sell_DeploysBidVaultAndMintsLp() public {
    uint256 id = _placeBid(bob, 500, 9_500e6);
    _sell(alice, 10_000e18, 1000);

    address bv = otc.bidVaultOf(id);
    assertTrue(bv != address(0));
    assertEq(vault.balanceOf(bv), 10_000e18); // shares held by the BidVault, not bob
    assertEq(vault.balanceOf(bob), 0);
    // bob holds LP equal to the shares
    assertEq(IERC20(bv).balanceOf(bob), 10_000e18);
}
```

Add the import `import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";` at the top of the test file if not present.

- [ ] **Step 2: Run to verify failure**

Run: `forge test --match-test test_Sell_DeploysBidVault -vvv`
Expected: FAIL (`bidVaultOf` not found; shares still go to buyer).

- [ ] **Step 3: Modify OTCMarket — inject factory, track bidVault, route fills through BidVault**

Add to imports/state:

```solidity
import {OTCFactory} from "./OTCFactory.sol";
import {BidVault} from "./BidVault.sol";
// ...
OTCFactory public immutable factory;
mapping(uint256 => address) public bidVaultOf; // bidId -> last BidVault created for it
```

Constructor gains a factory param: `constructor(address vault_, MockUSDC usdc_, uint16[] memory ladder_, OTCFactory factory_)` and sets `factory = factory_;`. **Update `OTCFixture._setUpOTC` to deploy the factory and pass it.**

In `sell`, replace the direct `shareToken.safeTransfer(b.buyer, fill)` with:

```solidity
address bv = factory.createBidVault(address(vault), MockUSDC(address(usdc)), b.buyer, fill);
shareToken.safeTransfer(bv, fill);
BidVault(bv).initRedeem();
bidVaultOf[q[i]] = bv;
emit BidFilled(q[i], b.buyer, fill, usdcPaid);
```

> Harden `BidVault.initRedeem` now: `function initRedeem() external { if (msg.sender != market) revert NotMarket(); redeemRequestId = vault.requestRedeem(shares); }` (drop the `redeemInitiated` bool and `require`). Update the Task 1.1 unit test to deploy the BidVault from a contract that then calls `initRedeem` as the market, or mark the unit test's vault deployer as `market` (it already is, since the test deploys it).

- [ ] **Step 4: Update OTCFixture to pass the factory**

In `test/helpers/OTCFixture.sol`, change the deploy:

```solidity
import {OTCFactory} from "../../src/otc/OTCFactory.sol";
// ...
OTCFactory factory = new OTCFactory();
otc = new OTCMarket(address(vault), usdc, LADDER, factory);
```

- [ ] **Step 5: Fix Phase-0 tests that asserted shares went to the buyer**

`test_Sell_FullFill_5pct`, `test_Sell_CheapestFirst`, OTC-1, OTC-2 asserted `vault.balanceOf(bob)`. Update them to assert the BidVault holds the shares and the buyer holds LP, then redeem the LP for USDC. For OTC-1, replace the "buyer redeems via queue" block with:

```solidity
address bv = otc.bidVaultOf(id);
pruv.setPrice(1e18);
vault.processEpoch();
BidVault(bv).claimRedemption();
uint256 bobUsdc = usdc.balanceOf(bob);
vm.prank(bob);
BidVault(bv).redeem(10_000e18);
assertEq(usdc.balanceOf(bob), bobUsdc + 10_000e6); // full NAV → profit = the discount
```

- [ ] **Step 6: Run the full OTC suite**

Run: `forge test --match-path 'test/otc/*' -vvv`
Expected: all PASS.

- [ ] **Step 7: Format + commit**

```bash
forge fmt
git add src/otc test/otc test/helpers/OTCFixture.sol
git commit -m "feat: OTCMarket fills via per-bid BidVaults (variant 1a)"
```

---

### Task 1.4: Acceptance scenarios OTC-3, OTC-3b, OTC-4, OTC-5

**Files:**
- Create: `test/otc/scenarios/OTC3_TwoBids.t.sol`, `OTC4_CancelBid.t.sol`, `OTC5_WindDown.t.sol`

- [ ] **Step 1: OTC-3 + OTC-3b (two discounts; non-fungible LP; cheapest-first)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OTCFixture} from "../../helpers/OTCFixture.sol";

contract OTC3_TwoBids is OTCFixture {
    function setUp() public { _setUpOTC(); }

    function test_TwoBidsTwoVaultsCheapestFirst() public {
        uint256 idB = _placeBid(bob, 500, 4_750e6);   // 5,000 shares @5%, fills first
        uint256 idC = _placeBid(charlie, 1000, 9_000e6); // 10,000 shares @10%, fills next

        _sell(alice, 8_000e18, 1000); // fills 5,000 @5% then 3,000 @10%

        address bvB = otc.bidVaultOf(idB);
        address bvC = otc.bidVaultOf(idC);
        assertTrue(bvB != bvC); // distinct vaults, non-fungible LP
        assertEq(vault.balanceOf(bvB), 5_000e18);
        assertEq(vault.balanceOf(bvC), 3_000e18);
    }
}
```

- [ ] **Step 2: OTC-4 (cancel resting bid) and OTC-5 (wind-down refunds)** — reuse the unit-test bodies from Tasks 0.4 and 0.6 as standalone scenario contracts inheriting `OTCFixture` with their own `setUp() { _setUpOTC(); }`.

- [ ] **Step 3: Run + format + commit**

Run: `forge test --match-path 'test/otc/*' -vvv`
Expected: all PASS.

```bash
forge fmt
git add test/otc/scenarios
git commit -m "test: OTC-3/3b/4/5 acceptance scenarios for variant 1a"
```

---

### Task 1.5: Optional Demo script

**Files:**
- Create: `script/DemoOTC.s.sol`

- [ ] **Step 1: Write a parameterised demo mirroring `script/Demo.s.sol`'s style**

A single `run(string scenario)` that deploys the full stack, reaches `EpochBased`, posts bids, runs a `sell`, processes an epoch, and logs balances at each step (`console2.log`). Keep it read-through-the-logs only; no assertions. Mirror the existing `Demo.s.sol` structure for setup. (Refer to `script/Demo.s.sol` for the exact deploy/prank pattern.)

- [ ] **Step 2: Run it**

Run: `forge script script/DemoOTC.s.sol --sig 'run(string)' "OTC1" -vvv`
Expected: prints the lifecycle; no revert.

- [ ] **Step 3: Commit**

```bash
git add script/DemoOTC.s.sol
git commit -m "chore: add OTC demo script"
```

**END OF PHASE 1 — full variant 1a: per-bid BidVaults, LP tokens, auto-redeem.**

---

# PHASE 2 — Optional off-chain matching (deferred, outline only)

Build only if multi-seller allocation or seller-gas becomes a concern. Not required for the core path; keep behind the same on-chain validation.

- **Task 2.1 — `settleBatch(bidIds[], shares[])`:** a keeper-callable entry that fills a precomputed set of (bid, shares) pairs, each still validated on-chain (bid resting, discount on-ladder, shares available, NAV read on-chain). Reverts if any pair violates the rules. Tests: a keeper batch produces the same end state as the equivalent `sell()` sweep.
- **Task 2.2 — EIP-712 signed bids:** let buyers sign bids off-chain (USDC permit/approve) so the book can live off-chain; `settleBatch` pulls USDC at settle. Tests: signature replay protection, expiry, nonce.
- **Task 2.3 — gas benchmark:** compare `sell()` (on-chain sweep) vs `settleBatch()` for N=10/50/100 bids; document the crossover where off-chain matching pays for itself.

Each Phase 2 task is independently shippable and leaves Phase 0/1 behavior unchanged.

---

## Self-Review notes (for the implementer)

- **Spec coverage:** placeBid/cancel/sell/closeForWindDown (breakdown §4.2) → Tasks 0.3–0.6; BidVault+LP+auto-redeem (Phase 1) → Tasks 1.1–1.3; scenarios OTC-1..6 + invariant (breakdown §8) → Tasks 0.7, 0.8, 1.4; on-chain matching/no-keeper (D5, §9) → Task 0.5; ladder/D8 → Task 0.3; buyer-first/D9 → fixture + 0.5; NAV-at-settle/D4 → `sell()` reads `vault.nav()`; one-share-one-place/D3 → shares escrowed at `sell`/held by BidVault, never minted.
- **Decimals:** every cross-decimal multiply uses `Math.mulDiv`; shares 18-dec, USDC 6-dec, `nav ≈ 1e6` at parity. Re-verify the `_sharesForUsdc` formula against S7 numbers before trusting fills.
- **Known sharp edges to watch:** (1) confirm the exact OZ import prefix matches `Vault.sol`; (2) the public-array getter tuple order for `bids(id)` must match the struct; (3) `closeForWindDown` reuses `MarketClosed` for the inverted guard — add `StillOpen` if it reads wrong; (4) `initRedeem` access control hardening in Task 1.3.
```
