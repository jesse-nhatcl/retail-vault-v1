# OTC Per-Bid BidVault Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to execute task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Change the OTC early-exit layer from **one BidVault per *fill*** to **one BidVault per *bid***, created at `placeBid` time, so it honours the original variant-1a requirement ("for each bid, one contract for the buyer") and makes `BidVault` a first-class object (holds the escrowed USDC, accumulates bought shares across fills, issues a single LP per buyer-bid).

**Architecture (target):** A `BidVault` is deployed when a buyer places a bid. The buyer's USDC is escrowed **inside that vault**. The `OTCMarket` keeps a cheap in-storage bid book (struct mirror of `usdcRemaining`) for cheapest-first matching. On each fill, the market tells the bid's vault to pay the seller, then moves the bought shares into that same vault, which mints LP and auto-redeems through the core `Vault`. One bid → one vault → one LP token, even across multiple partial fills. Core `Vault`/`Custody` remain untouched.

**Tech Stack:** Solidity 0.8.24, Foundry, OZ (`Math.mulDiv`, `SafeERC20`, `ERC20`, `ReentrancyGuard`, `IERC20`). TDD per `.claude/rules`.

**Branch:** create `otc-per-bid` off `main` before starting (do not work on `main`).

---

## Design decision (read first)

This is the **escrow-in-vault** variant of per-bid, chosen because it both (a) matches the requirement that the contract IS the buyer's bid, and (b) fixes the "BidVault is too thin" critique — the vault now owns the full bid lifecycle (escrow → shares → LP → redeem → cancel/wind-down refund).

**Source of truth split (keep these in sync):**
- `OTCMarket.bids[i].usdcRemaining` — the **matching** source of truth (cheap struct math, no external calls during the cheapest-first sweep).
- The **USDC tokens** themselves live in the bid's `BidVault`. Every change to `usdcRemaining` is mirrored by a `payOut`/`refund` token move from the vault. Invariant: `bidVault.usdc.balanceOf == bid.usdcRemaining` **until** the vault starts receiving shares (after which the vault holds shares + any leftover escrow).

**Why escrow stays mirrored in the struct:** the cheapest-first sweep must read each candidate bid's remaining size; doing that from a struct is one SLOAD, doing it from an external `bidVault.remaining()` call is a CALL per bid per sweep. Keep matching cheap; only settlement (`payOut`, share transfer, `onFill`) makes external calls.

**Alternative considered (escrow-in-market):** keep USDC in `OTCMarket`, vault holds only shares. Simpler (no `payOut`/`refund`), but the vault stays "thin" and the bid's money is not in the bid's contract — rejected because it does not address the thinness critique. If gas/complexity becomes a problem, this is the fallback.

**Cost accepted (per-bid):** a vault is deployed for every bid, including bids later cancelled or never filled (wasted deploy). Gas is out of POC scope.

---

## What changes vs the current per-fill code

| Aspect | Current (per-fill) | Target (per-bid) |
|---|---|---|
| Vault created | in `sell()`, per fill | in `placeBid()`, per bid |
| USDC escrow | held by `OTCMarket` | held by the bid's `BidVault` |
| LP per buyer-bid | one **per fill** (fragmented) | **one**, accumulates across fills |
| `bidVaultOf[bidId]` | last fill's vault (overwrites) | the bid's vault (1:1, stable) |
| `BidVault` role | thin (shares + LP) | escrow + shares + LP + redeem + refund |
| `requestRedeem` | once per vault | once **per fill** (vault tracks a list) |
| Matching | struct bid book (unchanged) | struct bid book (unchanged) |

---

## File Structure (files touched)

- Modify `src/interfaces/IBidVault.sol` — new surface (`onFill`, `payOut`, `refund`, drop `shares()`/`initRedeem`).
- Modify `src/otc/BidVault.sol` — escrow + accumulate + per-fill redeem list.
- Modify `src/otc/OTCFactory.sol` — `createBidVault(vault, usdc, buyer, market)` (no `shares`).
- Modify `src/otc/OTCMarket.sol` — `Bid.bidVault`; deploy+escrow in `placeBid`; settle via vault in `sell`; refund via vault in `cancelBid`/`closeForWindDown`.
- Modify tests: `test/otc/BidVault.t.sol`, `test/otc/OTCFactory.t.sol`, `test/otc/OTCMarket.t.sol`, `test/otc/scenarios/*`, `test/otc/OTCInvariant.t.sol`, `test/helpers/OTCFixture.sol`.
- Modify `script/DemoOTC.s.sol` if it reads the old API (it uses `bidVaultOf`, `claimRedemption`, `redeem` — should still work; verify).
- Update docs: `docs/07-otc-early-exit-alt1-1a.md` (+`.en.md`), `docs/07-otc-early-exit-alt1-1a-breakdown.md`, `docs/presentation/feasibility-brief.html`, `README.md`, and re-render `docs/02-architecture/diagrams/otc-architecture.mmd` + `otc-sequence.mmd`.

---

## Task 1: BidVault — escrow, accumulate, per-fill redeem

**Files:** `src/interfaces/IBidVault.sol`, `src/otc/BidVault.sol`

- [ ] **Step 1: Rewrite `IBidVault`**

```solidity
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

    function buyer() external view returns (address);
    function escrow() external view returns (uint256); // USDC still escrowed (unfilled)
    function payOut(address to, uint256 amount) external; // market-only: pay seller on a fill
    function refund(address to, uint256 amount) external; // market-only: cancel / wind-down
    function onFill(uint256 shares) external; // market-only: mint LP + queue redeem for this fill
    function claimRedemption() external; // pull NAV USDC for all settled fills
    function claimWindDown() external; // recover via the vault's wind-down pool
    function redeem(uint256 lp) external returns (uint256 usdcOut);
}
```

- [ ] **Step 2: Rewrite `BidVault`**

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

/// @notice One per OTC bid. Holds the buyer's escrowed USDC, accumulates bought shares across fills,
///         mints a single LP token to the buyer, and redeems the shares through the core Vault.
contract BidVault is IBidVault, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable market;
    IVault public immutable vault;
    IERC20 public immutable usdc;
    address public immutable buyer;

    uint256[] public redeemRequestIds; // one per fill
    mapping(uint256 => bool) public claimed; // requestId -> already claimed

    constructor(address vault_, MockUSDC usdc_, address buyer_, address market_)
        ERC20("OTC BidVault LP", "otcLP")
    {
        vault = IVault(vault_);
        usdc = IERC20(address(usdc_));
        buyer = buyer_;
        market = market_;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert NotMarket();
        _;
    }

    /// @notice USDC still escrowed for the unfilled part of the bid.
    function escrow() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @dev Market deposits the bid's USDC here at placeBid time (market does the transferFrom).
    ///      Kept as a hook only for the event; the token move happens in OTCMarket.placeBid.

    function payOut(address to, uint256 amount) external onlyMarket nonReentrant {
        usdc.safeTransfer(to, amount);
        emit PaidOut(to, amount);
    }

    function refund(address to, uint256 amount) external onlyMarket nonReentrant {
        usdc.safeTransfer(to, amount);
        emit Refunded(to, amount);
    }

    /// @notice Called by the market after it has moved `shares` of rACCESS into this vault.
    ///         Mints LP 1:1 to the buyer and queues a redeem for this fill.
    function onFill(uint256 shares) external onlyMarket {
        _mint(buyer, shares);
        uint256 id = vault.requestRedeem(shares);
        redeemRequestIds.push(id);
        emit Filled(shares, id);
    }

    /// @notice Claim NAV USDC for every fill whose epoch has settled (skips unprocessed / already-claimed).
    function claimRedemption() external nonReentrant {
        uint256 n = redeemRequestIds.length;
        for (uint256 i = 0; i < n; i++) {
            uint256 id = redeemRequestIds[i];
            if (claimed[id]) continue;
            // try/claim: only claimable once the request's epoch has been processed.
            try vault.claim(id) {
                claimed[id] = true;
            } catch {}
        }
        emit RedemptionClaimed(usdc.balanceOf(address(this)));
    }

    /// @notice If wind-down cancelled queued redeems and returned shares here, convert them via the pool.
    function claimWindDown() external nonReentrant {
        vault.claimWindDown();
        emit RedemptionClaimed(usdc.balanceOf(address(this)));
    }

    /// @notice Burn LP for a pro-rata slice of this vault's USDC (escrow + redeemed proceeds).
    function redeem(uint256 lp) external nonReentrant returns (uint256 usdcOut) {
        if (lp == 0 || balanceOf(msg.sender) < lp) revert NothingToClaim();
        usdcOut = Math.mulDiv(usdc.balanceOf(address(this)), lp, totalSupply());
        _burn(msg.sender, lp);
        usdc.safeTransfer(msg.sender, usdcOut);
        emit LpRedeemed(msg.sender, lp, usdcOut);
    }
}
```

> **Note on `claimRedemption` try/catch:** `Vault.claim` reverts `RequestNotClaimable` if the request's epoch is not yet processed OR if it was cancelled by wind-down. The `try/catch` skips those safely. For wind-down-cancelled requests, the shares are back in the vault and recovered via `claimWindDown` instead. Both paths deposit USDC into the vault; `redeem` distributes it.

> **Note on `redeem` accounting:** before any fill settles, the vault's USDC balance is the unfilled escrow — a buyer redeeming LP then would pull escrowed USDC. That is fine: LP only exists for *filled* shares, and a buyer should not be able to `redeem` LP they do not hold. But to avoid a buyer draining the *unfilled escrow* that backs the still-resting part of their own bid: **only count settled USDC.** Simplest robust rule: track `claimedUsdc` explicitly. If this edge matters, in Task 1 add `uint256 public proceeds;` incremented inside `claimRedemption`/`claimWindDown` by the delta received, and make `redeem` divide `proceeds` (not the raw balance) so escrow for the unfilled part is never redeemable. **Implement this guarded version** — see Task 1 Step 3.

- [ ] **Step 3: Guard redeem against unfilled escrow**

Add `uint256 public proceeds;`. In `claimRedemption` and `claimWindDown`, capture `uint256 before = usdc.balanceOf(address(this));` before the calls and `proceeds += usdc.balanceOf(address(this)) - before;` after. Change `redeem` to `usdcOut = Math.mulDiv(proceeds, lp, totalSupply());` then `proceeds -= usdcOut;` and transfer. This makes only *redeemed* USDC distributable, never the live escrow.

- [ ] **Step 4: BidVault unit test** (`test/otc/BidVault.t.sol`, rewrite)

Test the full path with the market simulated by the test contract:
- deploy `BidVault(vault, usdc, buyer, address(this))` (test = market);
- `usdc.mint(address(bv), 9_500e6)` then `bv.escrow()` == 9_500e6;
- `bv.payOut(seller, 9_500e6)` moves USDC to seller;
- give the vault shares: `vm.prank(alice); vault.transfer(address(bv), 10_000e18);` then `bv.onFill(10_000e18)` → buyer LP == 10_000e18, one requestId queued;
- `pruv.setPrice(1e18); vault.processEpoch();` then `bv.claimRedemption()` → `bv.proceeds()` == 10_000e6;
- `vm.prank(buyer); bv.redeem(10_000e18)` → buyer gets 10_000e6.
- Revert tests: `payOut`/`onFill`/`refund` from a non-market caller revert `NotMarket`.

- [ ] **Step 5:** `forge build`, run `forge test --match-contract BidVaultTest -vvv` (red first if written test-first; otherwise verify green), `forge fmt`, commit `feat: per-bid BidVault (escrow + accumulate + per-fill redeem)`.

---

## Task 2: OTCFactory — drop `shares`, pass `market`

**File:** `src/otc/OTCFactory.sol`, `test/otc/OTCFactory.t.sol`

- [ ] **Step 1:** Change signature to `createBidVault(address vault_, MockUSDC usdc_, address buyer_) returns (address)` and deploy `new BidVault(vault_, usdc_, buyer_, msg.sender)` — `msg.sender` is the calling `OTCMarket`, which becomes the vault's `market`. Update the event.
- [ ] **Step 2:** Update `OTCFactoryTest` to the new signature and assert `BidVault(bv).buyer() == bob` and `BidVault(bv).market() == address(this)`.
- [ ] **Step 3:** build, test, fmt, commit `feat: OTCFactory passes market to BidVault`.

---

## Task 3: OTCMarket — deploy+escrow at placeBid, settle via vault

**File:** `src/otc/OTCMarket.sol`, `test/helpers/OTCFixture.sol`, `test/otc/OTCMarket.t.sol`

- [ ] **Step 1: `Bid` struct + `placeBid`.** Add `address bidVault;` to the `Bid` struct (in `IOTCMarket`). In `placeBid`:
  - validate ladder + non-zero (unchanged);
  - `address bv = factory.createBidVault(address(vault), MockUSDC(address(usdc)), msg.sender);`
  - `usdc.safeTransferFrom(msg.sender, bv, usdcIn);` (escrow goes straight into the bid's vault);
  - push `Bid({buyer, discountBps, usdcRemaining: usdcIn, bidVault: bv, status: Resting})`;
  - `bidVaultOf[bidId] = bv;` (set once, never overwritten);
  - `_book[discountBps].push(bidId)`; emit `BidPlaced`.

- [ ] **Step 2: `sell`.** Matching loop unchanged (reads `usdcRemaining` from the struct). Replace the per-fill body (currently: `factory.createBidVault` + `safeTransfer` + `initRedeem`) with:
  ```solidity
  BidVault bv = BidVault(b.bidVault);
  bv.payOut(msg.sender, usdcPaid);            // seller paid from the bid's own escrow
  shareToken.safeTransfer(address(bv), fill); // bought shares into the bid's vault
  bv.onFill(fill);                            // mint LP + queue redeem for this fill
  emit BidFilled(q[i], b.buyer, fill, usdcPaid);
  ```
  Keep `usdcRemaining -= usdcPaid`, status flip to `Matched` when fully filled, the `remaining` accounting, the `NoFill` revert, the cheapest-first sweep, the `MAX_SCAN` cap, and `return unsold shares to seller`. (`shareToken.safeTransferFrom(msg.sender, address(this), shares)` at the top stays; unsold are returned from the market as today.)

- [ ] **Step 3: `cancelBid`.** Refund the unfilled escrow from the bid's vault: `BidVault(b.bidVault).refund(b.buyer, b.usdcRemaining);` then zero `usdcRemaining`, set `Cancelled`, emit. (No USDC sits in the market anymore.)

- [ ] **Step 4: `closeForWindDown`.** For each resting bid with `usdcRemaining > 0`: `BidVault(b.bidVault).refund(b.buyer, b.usdcRemaining);` zero it, mark `Cancelled`, count. (Filled BidVaults recover their shares via `claimWindDown`, driven by the buyer — unchanged.)

- [ ] **Step 5: `totalEscrowed`.** It can no longer read the market's USDC balance (the market holds none). Redefine the invariant target as: for each resting bid, `BidVault(bidVault).escrow() == bid.usdcRemaining`. Provide a view `escrowMatches() returns (bool)` that loops resting bids and checks equality, OR drop `totalEscrowed` and rewrite the invariant (Task 5) to assert each resting bid's vault escrow equals its `usdcRemaining`.

- [ ] **Step 6: `OTCFixture`.** No change to deploy (factory still passed to `OTCMarket`). Verify the helpers still compile against the new flow.

- [ ] **Step 7: `OTCMarket.t.sol`.** Update assertions for the new reality:
  - after `placeBid`: `otc.bidVaultOf(id) != address(0)` immediately (vault exists at bid time); `BidVault(bv).escrow() == usdcIn`; the market holds 0 USDC.
  - after `sell` full fill: seller paid; `BidVault(bv)` LP to buyer == fill; `bv.escrow()` == 0 (fully filled); bid `Matched`.
  - cheapest-first, partial (bid stays `Resting`, `bv.escrow()` == leftover), floor-skip, `NoFill`, off-ladder, unsorted-ladder ctor — keep, adjusting balances (no market USDC).
  - cancel: `bv.escrow()` returned to buyer.

- [ ] **Step 8:** build, full `forge test`, fmt, commit `feat: OTCMarket per-bid vaults (deploy+escrow at placeBid)`.

---

## Task 4: Scenarios OTC-1..6 + MULTI

**Files:** `test/otc/scenarios/*`

Update each to the per-bid reality (the economics are identical; only *where* state lives changes):
- [ ] **OTC-1:** buyer redeems the **same** vault that was created at `placeBid`; `bidVaultOf(id)` is stable. Full-NAV payout unchanged.
- [ ] **OTC-2:** unsold returns to seller (market-side, unchanged).
- [ ] **OTC-3 / 3b:** two bids → two vaults created at `placeBid`; a partial fill accumulates into the **same** vault and adds LP (assert LP grows, one vault per bid).
- [ ] **OTC-4:** cancel refunds escrow **from the bid's vault**.
- [ ] **OTC-5:** wind-down refunds resting escrow from each vault; a filled vault recovers via `claimWindDown` (unchanged).
- [ ] **OTC-MULTI:** the 6-buyer book now deploys 6 vaults at bid time (one cancelled-vault left empty after refund). After the sweep, assert: bid #4's vault has LP for the 5,000 filled and `escrow()` for the unfilled 5,000; bid #5 vault untouched with full escrow; bid #1 vault refunded (escrow 0). Re-verify the 29,150 USDC / 2.83% aggregate.
- [ ] build, `forge test`, fmt, commit `test: per-bid OTC scenarios`.

---

## Task 5: Invariant

**File:** `test/otc/OTCInvariant.t.sol`

- [ ] Rewrite `invariant_EscrowFullyBacked` to: **for every resting bid, its `BidVault.escrow()` equals `bid.usdcRemaining`** (escrow is never under-backed and never double-counted). Keep the handler (funded actors driving `placeBid`/`cancelBid`). Add a second invariant if cheap: the market contract itself holds 0 USDC at all times. build, test, fmt, commit `test: per-bid escrow invariant`.

---

## Task 6: Demo script

**File:** `script/DemoOTC.s.sol`

- [ ] Run all three scenarios (`OTC1`, `COMBINED`, `MULTI`). The narration references `bidVaultOf`, `claimRedemption`, `redeem` — all still valid. Update any line that asserted a vault was created *during* `sell` to note it now exists from `placeBid`. Re-capture output; fix any number that shifts (should not — economics unchanged). fmt, commit `chore: DemoOTC under per-bid`.

---

## Task 7: Docs, brief, diagrams

- [ ] **Diagrams:** edit `docs/02-architecture/diagrams/otc-architecture.mmd` so step 1 (`placeBid`) now also deploys the BidVault and escrows USDC into it (the deploy/escrow arrow moves to the placeBid step); `sell` no longer deploys, it pays out + moves shares + onFill. Re-render both PNGs (`mmdc -i <f>.mmd -o <f>.png -t dark -b '#0b0e14' --scale 3 --width 1900`). Edit `otc-sequence.mmd` so `placeBid` creates the BidVault and the `loop` only pays out + moves shares + onFill. Re-render.
- [ ] **`docs/07-otc-early-exit-alt1-1a.md` (+ `.en.md`):** update §4 (decision: per-bid, escrow in vault), §6/§7 (one vault per bid, one LP, created at placeBid), and the architecture/flow text. Note the trade-off (deploy per bid incl. cancelled).
- [ ] **`docs/07-otc-early-exit-alt1-1a-breakdown.md`:** update D1 (escrow location = BidVault), the contract table, the data model (Bid.bidVault; vault created at placeBid), the `placeBid`/`sell`/`cancel` function notes, the sequence, and Phase wording.
- [ ] **`docs/presentation/feasibility-brief.html`:** in the `#otc` section, update: the architecture figure (re-embed new base64), the sequence figure (re-embed), the "How it works" lanes (BidVault created at placeBid), the token-flow table (USDC escrow now in the BidVault), the bid-lifecycle (the vault exists from Resting), the Under-the-hood data model + matcher pseudocode (deploy at placeBid; sell does payOut+onFill), and the contract table. Keep 0 em-dashes; re-verify `<div>` balance.
- [ ] **`README.md`:** update the OTC extension section (one vault per bid, created at placeBid, one LP per buyer).
- [ ] build, `forge test` (still 64), fmt, commit `docs: per-bid OTC across brief, docs, diagrams`.

---

## Risks & edge cases (must be covered by tests)

1. **Cross-epoch fills.** A bid partially filled in epoch N then more in N+1 accumulates two redeem requests with different epochs. `claimRedemption` must claim each only once its epoch is processed (the `try/catch` + `claimed` map handles this). **Test:** fill a bid across two `processEpoch`s, then `claimRedemption`, assert proceeds == sum of both fills at NAV.
2. **Cancel after partial fill.** Only the *unfilled* `usdcRemaining` is refundable; the filled shares/LP stay with the buyer. **Test:** partial fill, then `cancelBid`, assert only the leftover escrow refunded and LP intact.
3. **redeem vs live escrow.** `redeem` must pay from `proceeds` (settled USDC) only, never the unfilled escrow (Task 1 Step 3). **Test:** place a bid, partially fill, `claimRedemption`, then try `redeem` — buyer gets the filled value, not the escrow; the leftover escrow remains refundable.
4. **Empty vault on cancel/never-fill.** A bid cancelled before any fill leaves an empty BidVault (0 LP, 0 escrow after refund). Harmless; assert no funds stranded.
5. **Access control.** `payOut`/`refund`/`onFill` are `onlyMarket` (market = the OTCMarket, set via the factory passing `msg.sender`). **Test:** direct EOA calls revert `NotMarket`.
6. **NAV staleness across fills.** Each fill prices at the NAV read in *that* `sell` tx; different sells may price at different NAVs. This is intended (price at fill time). Document; no fix.

## Done criteria
- `forge test` green (≥ 64; new per-bid tests added), `forge fmt --check` clean.
- One BidVault per bid, created at `placeBid`; one LP per buyer-bid accumulating across fills; escrow lives in the bid's vault; `bidVaultOf` stable.
- Brief + README + design docs + both diagrams updated and consistent.
- A final adversarial review (solidity-reviewer) over the whole refactor before merge, same as the original build.
