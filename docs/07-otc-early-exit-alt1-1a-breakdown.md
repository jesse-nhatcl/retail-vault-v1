# Implementation Breakdown — OTC Early-Exit (Alt-1, variant 1a)

> **Status:** design-level breakdown for turning variant 1a into Solidity contracts + Foundry scripts.
> **Not** a detailed PRD — no final signatures, no exhaustive edge cases. The goal is to fix the shape: what contracts
> exist, how they wire to the existing `Vault` / `Custody`, the core flows, the decisions to lock, and a test/script plan.
> Concept source: `docs/07-otc-early-exit-alt1-1a.md`. This stays **out of the current POC scope** until explicitly pulled in.

---

## 1. Scope & non-goals

**In scope (this build):**
- A **Layer 0** early-exit market over `rACCESS` shares, on the same Anvil chain, no UI.
- Variant 1a mechanics: **one ERC-4626-style BidVault per buyer bid**, each issuing its own LP token.
- Settlement that pays the seller now and routes the bought shares to the existing redemption queue.
- Foundry contracts, a parameterised demo script, and scenario tests — same discipline as the main POC.

**Non-goals (explicitly deferred):**
- Pooled tiers (variant 2) or FIFO orderbook (variant 3).
- Off-chain ROuter infra — matching runs **on-chain inside the seller's tx**; an off-chain ROuter/keeper is an optional Phase 2 (compute off-chain, then settle on-chain-validated).
- Fees (0% per POC), Alt-2 / Balancer path, production hardening, gas optimisation.

---

## 2. Where it sits

`vToken == rACCESS shares` (the existing 18-dec vault share). OTC is a new layer **in front of** redemption:

```
Layer 0  OTC early-exit   ◀ NEW (this build)   — seller exits now at a discount
Layer 1  P2P matching     (exists, processEpoch)
Layer 2  liquid buffer    (exists)
Layer 3  illiquid Pruv    (exists)
```

The OTC layer never mints or burns shares itself. It only **moves ownership** of existing shares (seller → buyer/BidVault)
and then uses the *existing* `Vault.requestRedeem` / `claim` to convert escrowed shares to USDC at NAV. So `totalSupply`
and custody backing are untouched → **no NAV double-count** (see §7, decision D3).

---

## 3. Economic model (what actually happens)

Plain-language settlement for one bid:

1. **Seller** locks `M` shares, willing to sell down to a floor price `p_floor = NAV · (1 − maxDiscount)`.
2. **Buyer** bids: discount `d ≤ maxDiscount`, deposits `USDC_in`. Per-share price `p = NAV · (1 − d)`.
3. **Settle:** buyer's `USDC_in` goes **to the seller** (instant discounted exit). `M_bid = USDC_in / p` shares move into
   a new **BidVault**; buyer receives LP tokens = claim on those shares.
4. **BidVault** queues its shares through the normal redemption path (`Vault.requestRedeem`). At the next epoch they
   settle at **full NAV**; BidVault `claim`s the USDC.
5. **Buyer** redeems LP → receives the NAV USDC. Buyer profit = `(NAV − p) · M_bid` (the discount), earned for taking on
   the wait. Seller's cost = the same discount, paid for immediacy.
6. **Unfilled** shares (no buyer) return to the seller, who may queue them normally or relist.

> The protocol takes nothing by default; the discount is a pure seller→buyer transfer. A fee, if ever added, is a cut on
> top (see `docs/06-fees`).

---

## 4. Contracts

New code under `src/otc/`. Four units:

| Contract | Responsibility | Notes |
|---|---|---|
| `OTCMarket` | Single registry/coordinator. Holds the resting **bid book** + escrowed buyer USDC; the seller's `sell()` reads NAV, matches cheapest-first, and settles atomically on-chain. Gated to `Vault` state. | One instance; `Ownable` for config (ladder); `nonReentrant` on value-moving calls. |
| `OTCFactory` | Deploys one `BidVault` per accepted bid. | Could be folded into `OTCMarket`; kept separate to mirror the sketch's "vault per buyer". |
| `BidVault` | ERC-4626-style escrow for one bid: holds bought shares, issues LP token, drives `requestRedeem`/`claim`, distributes USDC pro-rata to LP holders. | Minimal; the "gives out vault token" part of 1a. |
| Interfaces | `IOTCMarket`, `IBidVault`. | Signatures locked here before implementation. |

Reused as-is: `Vault` (shares + redeem queue), `Custody`, `MockUSDC`, `INavSource` (read NAV at settle time).

### 4.1 Data model (sketch)

```solidity
// Buy side: resting bids, grouped by ladder rung (the on-chain bid book).
struct Bid {
    address buyer;
    uint16  discountBps;     // must be on the fixed ladder (D8)
    uint256 usdcIn;          // 6-dec, escrowed in OTCMarket
    address bidVault;        // 0 until matched
    Status  status;          // Resting | Matched | Cancelled
}
mapping(uint16 => Bid[]) bidBook;   // rung (discountBps) -> FIFO queue of bids

// Sell side has no resting struct: the seller's `sell()` escrows shares and matches
// the bid book in the same tx. A resting sell-listing is deferred (not needed for the core).
```

### 4.2 Function surface (sketch, not final)

`OTCMarket`
- `placeBid(uint16 discountBps, uint256 usdcIn) → bidId` — buyer escrows USDC up front into the bid book; reverts if `discountBps` is off-ladder. Bids rest until a seller fills (buyer-first, D9).
- `sell(uint256 shares, uint16 maxDiscountBps) → filled` — **the matching entry point, fully on-chain (D5, §9).** Seller escrows shares, reads NAV on-chain, sweeps resting bids cheapest-first up to the floor (cap N bids/tx); each match atomically pays the seller, deploys a BidVault with the shares, and mints LP to the buyer. Unsold shares return to the seller.
- `cancelBid(bidId)` — buyer withdraws a resting bid; USDC refunded.
- `closeForWindDown()` — admin/`Vault`-driven; refund all open bids when the vault winds down.

`BidVault` (per bid)
- `constructor(vault, usdc, shares, buyer)` — receives shares, mints LP to buyer, calls `Vault.requestRedeem(shares)`.
- `claimRedemption()` — after the epoch, pulls USDC via `Vault.claim(requestId)`.
- `redeem(uint256 lp)` — buyer burns LP → pro-rata USDC out.

---

## 5. Core flow (sequence)

```mermaid
sequenceDiagram
    participant S as Seller
    participant M as OTCMarket
    participant B as Buyer
    participant F as OTCFactory
    participant BV as BidVault
    participant V as Vault (existing)

    B->>M: placeBid(d, USDC_in)
    Note over M: USDC escrowed, d on ladder; bid rests
    S->>M: sell(M shares, floor) — read NAV, sweep bids cheapest-first
    Note over M: per matched bid, atomically:
    M->>S: pay USDC (discounted exit)
    M->>F: deploy BidVault
    F-->>BV: new vault
    M->>BV: transfer matched shares
    BV->>B: mint LP tokens
    BV->>V: requestRedeem(matched)
    Note over V: next epoch settles at NAV
    BV->>V: claim(requestId) → USDC
    B->>BV: redeem(LP) → NAV USDC
```

Unfilled tail: `sell()` returns the unmatched shares to the seller, who can route them to the redemption queue.

---

## 6. Integration points with existing code

| Touch point | Detail | Risk to check |
|---|---|---|
| `rACCESS` shares (ERC-20) | `approve`/`transferFrom` for seller→market→BidVault | standard |
| `Vault.requestRedeem(shares)` | called by `BidVault` (a contract, not EOA) | confirm Vault accepts contract callers; `requestId` returned & stored |
| `Vault.claim(requestId)` | BidVault pulls settled USDC | reentrancy guard already on `claim` |
| `INavSource.pricePerWRWA()` / `Vault.nav()` | price the bid at settle time | NAV staleness — read at `settle`, not `placeBid` |
| State machine | OTC opens only in `EpochBased`; `closeForWindDown` on `WindDown` | one-way state; refund escrow on close |
| Decimals | shares 18-dec, USDC 6-dec, NAV per `epoch-math.md` (`usdc = shares · nav / 1e18`) | use `Math.mulDiv`, mirror redeem formula exactly |

---

## 7. Decisions (locked)

- **D1 — Escrow location.** Shares + USDC sit in `OTCMarket` until settle. Market-escrow keeps cancel/refund simple.
- **D2 — Auto-queue.** `BidVault` auto-`requestRedeem`s its shares so the buyer gets USDC at the next epoch. (Hold-as-investor is a later option.)
- **D3 — NAV accounting.** OTC only moves share ownership; shares stay in `totalSupply` → backed, **no double-count**.
- **D4 — Pricing time.** NAV is read **at `settle`**, on-chain. A stale NAV between bid and settle is the parties' risk.
- **D5 — On-chain matching, no keeper.** Matching runs **inside the seller's `sell()` tx**: read NAV on-chain, sweep the bid book cheapest-first (≤ floor, cap N/tx), settle atomically. No off-chain matcher in the core path; consistent with `processEpoch`. A keeper / off-chain optimizer (compute then `settle` on-chain-validated) is an **optional Phase 2**. (EIP-712 signed bids deferred.)
- **D6 — Cancel semantics.** Resting bids cancellable any time before they match. On `WindDown`, force-refund all open bids; settled BidVaults flow on at NAV. OTC opens **only in `EpochBased`**.
- **D7 — Fees.** 0% for the POC. One hook point left for a future cut.
- **D8 — Discount ladder (not free).** Buyers pick a discount from a **small fixed ladder** (e.g. {1% / 2.5% / 5% / 10%}, governance-set), not a continuous value. Concentrates liquidity at Schelling points while staying 1a (own vault + own LP per bid, no pooling — pooling would be variant 2). See `07-otc-early-exit-alt1-1a.md` §6.
- **D9 — Buyer-first, resting bids.** Buyers post bids with **USDC escrowed up front** and rest until a seller arrives; the seller is the taker and fills **cheapest-first** up to their floor. Seller-first would defeat the "fast exit" goal.

---

## 8. Scripts & tests (Foundry)

**Layout** (mirrors the main POC):
- `src/otc/{OTCMarket,OTCFactory,BidVault}.sol`, `src/interfaces/{IOTCMarket,IBidVault}.sol`.
- `test/otc/` — unit per contract + scenario files; each inherits the existing `Fixture` (reuse alice/bob/charlie, funded mocks, deployed Vault+Custody at `EpochBased`).
- `script/DemoOTC.s.sol` — parameterised: `run(string) "OTC-1"` etc., same style as `Demo.s.sol`.

**Scenario tests (acceptance):**

| ID | Scenario | Asserts |
|---|---|---|
| OTC-1 | Single full fill | seller paid discounted USDC; buyer LP = bought shares; after epoch buyer redeems NAV USDC; profit = discount |
| OTC-2 | Partial fill → queue fallback | unsold shares returned to seller; seller can `requestRedeem` the remainder normally |
| OTC-3 | Two bids, different discounts (5% / 10%) | two BidVaults deployed; each buyer settled at their own price; LP tokens non-fungible |
| OTC-4 | Cancel a resting bid | full USDC refund; bid removed from the book |
| OTC-5 | WindDown with open bids | `closeForWindDown` refunds all resting bids; settled BidVaults still claimable |
| OTC-3b | Cheapest-first ordering | seller's `sell()` fills the 5% bids before the 10% bids; stops at the floor |
| OTC-6 | Reverts | bid discount off-ladder; `sell()` finds no bid ≤ floor; OTC action outside `EpochBased` |

**Invariants (candidates for `invariant_`):**
- OTC never changes `Vault.totalSupply` except through the existing redeem burn.
- Sum of escrowed USDC + shares is always refundable until settle (no leakage).
- A BidVault's LP totalSupply maps 1:1 to its claimable share/USDC balance.

TDD per `.claude/rules/testing.md`: write the failing scenario first, watch it fail, then implement.

---

## 9. Phasing

- **Phase 0 — P2P discounted swap (cheapest early-exit).** `OTCMarket` only: buyers `placeBid` (resting), seller `sell()` does the on-chain cheapest-first sweep + atomic shares↔USDC swap at the discounted price. No BidVault, no LP token. This already delivers early-exit and is the low-cost core.
- **Phase 1 — variant 1a wrapper.** Add `OTCFactory` + `BidVault` + LP token + auto-`requestRedeem`/`claim`. This is the "vault per buyer" part — and the expensive part (one ERC-4626 + LP per bid), exactly the cost flagged in the concept doc.
- **Phase 2 — off-chain matching (optional).** Off-chain optimizer/keeper (compute then settle on-chain-validated) to cut seller gas and improve multi-seller allocation, optional EIP-712 signed orders. The core path does not depend on it.

> Phase 0 alone is a defensible MVP of early-exit. Phases 1–2 buy tradability and price discovery at rising complexity —
> revisit against the pooled/FIFO variants before committing to the per-bid-vault cost.
