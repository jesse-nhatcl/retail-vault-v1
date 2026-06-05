# 01 — Requirements (Phase R Output)

**Project:** retail-access-vault — Local POC for Alt-1 mechanism
**Author:** Tech-lead research assistant
**Date:** 2026-06-02
**Status:** Draft awaiting Phase I approval

---

## 1. Executive Summary

Build a **local proof-of-concept** demonstrating mechanism feasibility of the Retail Access PRD's **Alternative 1** design (custody self-built + illiquid/liquid mix). The POC will be Solidity contracts executed on a single Anvil chain, driven by a parameterised demo script. The goal is to prove that the **state machine, ERC-7540 queue, peer-to-peer matching, and 3-layer redemption** all wire together coherently — not to ship a product.

---

## 2. Scope & Goals

### 2.1 In scope (L1 — Mechanism logic)

- 5-state vault lifecycle (`Initialized → Launchpad Start → (Launchpad Fail | Epoch-based) → Wind-down`)
- ERC-7540-style async subscription/redemption queue (mechanism only — not full EIP compliance)
- ERC-7887-style cancel for pending subscriptions
- Peer-to-peer matching system (both PRD cases: Sub>Redeem and Redeem>Sub)
- 3-layer redemption fallback (matching → liquid buffer → illiquid asset)
- Custody contract holding both wrapped-RWA and liquid buffer tokens
- Asset mix with **rebalance-toward-target** sourcing rule
- Manual NAV via admin-driven `setPrice()`
- Full Wind-down sequence (refund pending, liquidate liquid, settle redemptions, illiquid window, final stable claim)
- 1 parameterised demo script covering 8 verification scenarios

### 2.2 Out of scope (explicitly deferred)

- Aave reinvest of idle USDC in subscription queue
- Curve-specific swap formula research (POC uses mock AMM at 1:1)
- Cross-chain bridge (Pruv treated as on-chain mock)
- Frontend / UI
- Real Pruv testnet or Hamilton Lane integration
- Role-based access control (single owner suffices)
- Linear NAV accrual / oracle integration
- ERC-4626 standard inheritance (custom vault, not necessarily 4626-compatible)
- Gas optimisation
- Audit-grade security hardening
- Multi-asset support beyond 1 illiquid + 1 liquid

### 2.3 Non-goals

- Not a product. Not deployable to mainnet.
- Not an investment vehicle — uses mocks for all underlying assets.
- Not a stress test of economics or yield — L3 economic viability is deferred.

---

## 3. Stakeholders & Roles

| Role | Who | Permissions |
|---|---|---|
| **Admin / Owner** | Single EOA (deployer) | Deploy vault, configure launchpad, `setPrice()`, `processEpoch()`, `triggerWindDown()`, configure asset |
| **Retail Investor** | Any EOA | `requestDeposit()`, `requestRedeem()`, `cancelRequest()`, `claim()`, `refund()` |
| **Pruv (mock)** | Mock contract on same chain | Receives USDC subscription, mints wrapped RWA token; consumes wRWA on redemption, returns USDC |
| **Liquid Buffer (mock)** | Mock yield-bearing ERC-20 | Holds USDC equivalent, swappable 1:1 with USDC via mock AMM |

---

## 4. Functional Requirements

### 4.1 State Machine

```
                   ┌──────────────┐
                   │ Initialized  │ (deployed, launchpad time not reached)
                   └──────┬───────┘
                          │ launchpadStartTime reached
                          ▼
                   ┌──────────────┐
                   │ LaunchpadStart│ (accepting USDC, awaiting min)
                   └──────┬───────┘
                          │ launchpadEndTime reached
              ┌───────────┴───────────┐
              │                       │
        totalLocked ≥ min        totalLocked < min
              │                       │
              ▼                       ▼
       ┌────────────┐          ┌──────────────┐
       │ EpochBased │          │LaunchpadFail │
       └─────┬──────┘          └──────────────┘
             │                  (refund-only)
             │ admin triggerWindDown()
             ▼
       ┌────────────┐
       │ WindDown   │
       └─────┬──────┘
             │ all redemptions settled, stable distributed
             ▼
       ┌────────────┐
       │   Closed   │ (terminal)
       └────────────┘
```

**Transitions are one-way.** No going back from WindDown to EpochBased.

### 4.2 Launchpad Phase

**Init inputs (immutable after deploy):**
- Vault token name, symbol
- Stablecoin address (mock USDC)
- Launchpad period (start + end timestamps)
- Minimum amount needed (uint USDC)

**Init inputs (editable until LaunchpadStart fires):**
- Asset contract addresses (illiquid wRWA, liquid buffer)
- Default percentages (80% illiquid / 20% liquid default)

**During LaunchpadStart:**
- Retail calls `depositToLaunchpad(amount)` → USDC locked, internal mapping `launchpadDeposits[user] += amount` updated
- No vault token minted yet (receipts via mapping, not ERC-20)
- Anyone can call `transitionAfterDeadline()` after `launchpadEndTime`:
  - If `totalLocked ≥ min` → state = EpochBased, vault calls Pruv mock to subscribe with full USDC pool, mints vault token pro-rata to `launchpadDeposits[*]` (claimable via `claim()`)
  - If `totalLocked < min` → state = LaunchpadFail, users call `refund()` to retrieve their USDC

### 4.3 Epoch-based — Subscription

**User actions (anytime during EpochBased):**
- `requestDeposit(amount)` → USDC locked into subscription queue, request ID returned
- `cancelRequest(requestId)` (ERC-7887-style) → if epoch not yet processed, refund USDC, remove from queue
- `claim(requestId)` → after epoch processed, mint vault token to user based on price at epoch time

**Vault settlement (admin calls):**
- `processEpoch()` → see §4.5

### 4.4 Epoch-based — Redemption

**User actions (anytime during EpochBased):**
- `requestRedeem(shares)` → vault token locked into redemption queue, request ID returned
- `cancelRequest(requestId)` → similar to sub cancel
- `claim(requestId)` → after epoch processed, transfer USDC to user

### 4.5 `processEpoch()` — Core Settlement Logic

Atomic operation. Sequence:

```
1. NAV update assumed already done via setPrice() prior to call
2. Snapshot:
     subQueueUSDC    = sum of pending sub amounts
     redeemQueueShares = sum of pending redeem shares
     redeemQueueUSDC = redeemQueueShares × NAV

3. Matching:
     matched = min(subQueueUSDC, redeemQueueUSDC)
     matchedShares = matched / NAV

     # Distribute matched portion:
     For each sub request in queue:
       allocate user's share of `matchedShares` based on user's % of subQueueUSDC
       these shares come from redeemers' burnt shares (internal accounting)
       reduce user's pending sub by matched portion

     For each redeem request in queue:
       allocate user's share of `matched` USDC based on user's % of redeemQueueUSDC
       these USDC come from subscribers' pool
       reduce user's pending redeem by matched portion

4. Settle net delta:
   IF subQueueUSDC > redeemQueueUSDC:
     netSub = subQueueUSDC - redeemQueueUSDC
     custody.buyAssets(netSub) per §4.7 rebalance rule
     mint additional shares to remaining sub queue (pro-rata)

   ELSE IF redeemQueueUSDC > subQueueUSDC:
     netRedeem = redeemQueueUSDC - subQueueUSDC
     custody.sourceUSDC(netRedeem) per §4.6 3-layer rule
     burn additional shares and pay USDC to remaining redeem queue (pro-rata)

   ELSE:
     # exact match, no asset action

5. Mark queue snapshot as processed; new requests start fresh queue for next epoch
```

### 4.6 3-Layer Redemption (when sourcing USDC for net redeem)

```
Required USDC = netRedeem

Layer 1 — Matching (already done in §4.5 step 3)

Layer 2 — Liquid Buffer:
   available = custody.liquidBalance() × buffer_swap_rate (mock 1:1)
   take = min(required, available)
   custody.swapLiquidForUSDC(take)
   required -= take

Layer 3 — Illiquid:
   IF required > 0:
     wRWAToRedeem = required / NAV
     pruvMock.redeem(wRWAToRedeem) → returns USDC
     required -= proceeds
```

If even Layer 3 cannot fulfill (e.g., Pruv redemption window closed or insufficient assets), redemption is **partially settled**; remainder rolls to next epoch. Document this corner case in S6 scenario.

### 4.7 Asset Mix — Rebalance-Toward-Target (when buying for net sub)

Target ratio: 80% illiquid / 20% liquid (configurable per-vault).

```
totalAssetsAfter = totalAssetsBefore + netSubUSDC
targetIlliquidUSDC = totalAssetsAfter × 0.80
targetLiquidUSDC = totalAssetsAfter × 0.20

currentIlliquidUSDC = wRWA holdings × NAV
currentLiquidUSDC = liquid buffer holdings (1:1 mock)

buyIlliquid = max(0, targetIlliquidUSDC - currentIlliquidUSDC)
buyLiquid = max(0, targetLiquidUSDC - currentLiquidUSDC)

# Normalise if total exceeds netSubUSDC (rare with mock 1:1 prices)
scale = netSubUSDC / (buyIlliquid + buyLiquid)
buyIlliquid *= scale
buyLiquid *= scale

pruvMock.subscribe(buyIlliquid)    # produces wRWA at current NAV
mockAMM.swap(USDC → liquid, buyLiquid)
```

### 4.8 Wind-Down Sequence

Triggered by admin once during EpochBased.

```
1. Set state = WindDown
2. Disable new requestDeposit() and new requestRedeem()
3. Refund all pending sub requests (return USDC, clear queue)
4. Swap all liquid buffer in custody → USDC immediately
5. Use accumulated USDC to settle redeem queue:
   For each redeem request:
     payout = min(remainingUSDC, request.shares × NAV)
     transfer payout to user
     burn request.shares
6. After liquid USDC exhausted, redeem all illiquid from Pruv mock
   (POC: assume window open immediately; production needs scheduling)
7. Use illiquid proceeds to settle remaining redeem queue
8. Any leftover vault token holders → can call `claim()` to receive
   pro-rata share of remaining USDC pool, until time limit
9. After time limit: state = Closed (terminal). Any leftover dust kept by admin or burnt.
```

### 4.9 NAV (Net Asset Value) Mechanics

NAV = totalAssetsUSDC / totalSupplyShares.

For POC, NAV recalculated **on demand** when admin calls `setPrice(newWRWAPrice)`. The price determines how `totalAssets()` computes the illiquid portion. Liquid buffer is 1:1 USDC for simplicity.

```solidity
function totalAssets() public view returns (uint) {
  return wRWAHeld * wrwaPriceInUSDC / 1e18 + liquidHeld;
}
function nav() public view returns (uint) {
  return totalAssets() * 1e18 / totalSupply();  // before launchpad: 1e18 (1:1)
}
```

`setPrice()` is admin-only and required before each `processEpoch()` to reflect updated underlying value.

---

## 5. Non-Functional Requirements

| NFR | Target |
|---|---|
| **Determinism** | Same inputs → same outputs across runs (no randomness, no oracles) |
| **Observability** | Every state transition + queue mutation emits an event |
| **Test execution time** | All 8 scenarios run via `forge test` in < 30 seconds |
| **Demo script clarity** | Demo script prints state diff with colored output (red/green/yellow) per scenario |
| **Documentation** | Every public function has a NatSpec comment explaining purpose |
| **Code size** | Target < 1,500 lines Solidity total across all contracts |

---

## 6. Design Decisions Summary (with rationale)

| Decision | Choice | Rationale |
|---|---|---|
| Chain model | Single Anvil chain, Pruv as mock contract | Bridge logic doesn't change core mechanism; saves ~3-5 days |
| Asset mix sourcing | Rebalance toward target (Option B) | More realistic; PRD Alt-2 mentions rebalance, applying same to Alt-1 |
| Receipt token | Internal mapping, non-transferable | Simpler; transferable receipts add no POC value |
| Epoch trigger | Single `processEpoch()` for both queues | Matches PRD ("end of epoch we net out…"); preserves matching benefit |
| NAV model | Manual admin `setPrice()` | Lets us test any price scenario explicitly; oracle is production concern |
| Permission model | Single owner (Ownable) | POC; role-based is over-engineering here |
| Liquid swap mock | Fixed 1:1 mock AMM | PRD's Curve research is "Required to Work" — defer formula choice |
| Cross-chain | Skip; single chain only | Bridge is integration realism (L2), not mechanism (L1) |
| Stablecoin | Mock USDC, 6 decimals | Match real USDC for realism |
| Vault token | 18 decimals, ERC-20-compatible (not full ERC-4626) | Keep code minimal; ERC-4626 isn't required to prove mechanism |

---

## 7. Test Scenarios (8 to cover)

### S1 — Happy Path Full Lifecycle
**Setup:** 3 users (Alice, Bob, Charlie) deposit during launchpad. Min = 50k USDC, totals 100k. Launchpad succeeds.
**Actions:**
1. Launchpad transitions to EpochBased; vault buys assets (80k wRWA + 20k liquid).
2. Alice `requestDeposit(10k)`; Bob `requestRedeem(5k shares)`.
3. Admin `setPrice` (NAV unchanged 1.0); `processEpoch()`.
4. Both Alice and Bob `claim()`.
5. Admin triggers WindDown; remaining users redeem.
**Pass:** All shares burnt or claimable, all USDC accounted for (within rounding tolerance).

### S2 — Launchpad Fail + Refund
**Setup:** Min = 50k USDC. Total locked = 30k. Time expires.
**Actions:**
1. `transitionAfterDeadline()` triggers, state → LaunchpadFail.
2. Each depositor calls `refund()`.
**Pass:** All users receive original USDC; vault holdings = 0.

### S3 — ERC-7887 Cancel Pending Sub
**Setup:** Vault in EpochBased. Alice `requestDeposit(10k)`. Before epoch processed, Alice calls `cancelRequest(requestId)`.
**Pass:** Alice receives back 10k USDC; subQueue empty.

### S4 — Matching: Sub > Redemption (PRD Case 1)
**Setup:** Sub queue 10k USDC. Redeem queue value 4k (4k shares at NAV 1.0).
**Actions:** `processEpoch()`.
**Pass:**
- 4k USDC redistributed: redeemers get 4k USDC, subscribers get 4k shares (P2P).
- Remaining 6k USDC used to buy assets (rebalance).
- Subscribers' additional shares minted at NAV 1.0 → 6k shares.

### S5 — Matching: Redemption > Sub (PRD Case 2)
**Setup:** Sub queue 4k USDC. Redeem queue value 10k.
**Actions:** `processEpoch()`. Custody has 20k liquid buffer.
**Pass:**
- 4k matched (subscribers get 4k shares from redeemers).
- 6k delta: liquid buffer 6k → swapped to USDC → paid to redeemers.
- 6k worth of shares burnt.

### S6 — Redemption Needs Illiquid Fallback
**Setup:** Liquid buffer drained to 2k. Net redemption need 6k.
**Actions:** `processEpoch()`.
**Pass:**
- Liquid 2k consumed.
- Remaining 4k sourced from wRWA redemption (Pruv mock).
- Total 6k USDC paid out.

### S7 — NAV Change Affects Calcs
**Setup:** Vault has 100k shares, custody worth 100k. Admin `setPrice(1.1)` → totalAssets now 110k → NAV = 1.10.
**Actions:** Alice `requestRedeem(10 shares)`. `processEpoch()`.
**Pass:** Alice receives 11 USDC (10 × 1.10), not 10.

### S8 — Wind-Down Mid-Epoch
**Setup:** Vault in EpochBased. Sub queue 5k, redeem queue 5 shares. Admin triggers `triggerWindDown()`.
**Pass:**
- 5k USDC in sub queue → refunded immediately.
- Liquid buffer → swapped to USDC.
- Redeem queue settled with USDC.
- Illiquid → redeemed at Pruv → distributed.
- Final state = Closed; all balances reconciled.

---

## 8. Glossary

| Term | Definition |
|---|---|
| **Vault** | Main smart contract retail users interact with; mints shares representing claim on basket of assets |
| **Vault token / Share** | ERC-20 representing pro-rata claim on vault's `totalAssets()` |
| **Custody** | Standalone contract holding wRWA + liquid buffer; controlled exclusively by Vault |
| **Pruv (mock)** | Mock contract simulating Hamilton Lane Evergreen fund; receives USDC, mints wRWA; consumes wRWA, returns USDC |
| **wRWA** | Wrapped RWA token issued by Pruv mock; the illiquid asset held in custody |
| **Liquid Buffer** | Mock yield-bearing ERC-20 representing the liquid portion; swappable 1:1 with USDC via mock AMM |
| **Receipt (Launchpad)** | Internal non-transferable accounting of user's USDC locked during launchpad |
| **Epoch** | The processing period; ends when `processEpoch()` is called |
| **Subscription queue** | Pending `requestDeposit` calls waiting for next epoch |
| **Redemption queue** | Pending `requestRedeem` calls waiting for next epoch |
| **Matching** | P2P netting of sub vs redeem queues at epoch processing |
| **NAV** | Net Asset Value per share = totalAssets / totalSupply |
| **ERC-7540** | Async deposit/redeem vault standard (we implement mechanism, not full EIP) |
| **ERC-7887** | Cancel-pending-request standard (we implement basic cancel) |

---

## 9. Open Questions / Items Deferred

| # | Item | Why deferred |
|---|---|---|
| Q1 | Curve swap formula choice | PRD itself notes "Required to Work" — research item, not POC blocker |
| Q2 | Aave reinvest economics | Auxiliary; not essential to prove mechanism |
| Q3 | Cross-chain bridge realism | L2 integration; not part of L1 mechanism scope |
| Q4 | Real Pruv API contract shape | We assume `subscribe(usdc)` and `redeem(wrwa)` — real API may differ |
| Q5 | NAV oracle design | Manual `setPrice()` suffices for L1; oracle is production concern |
| Q6 | Fee model (perf fee, mgmt fee, redemption fee) | PRD silent; assume 0% for POC |
| Q7 | ERC-4626 compatibility | Not required to prove mechanism; may add later |
| Q8 | Partial redemption rollover semantics | S6 scenario hints; full spec deferred to Phase P |

---

## 10. Approval Gate

To proceed to **Phase I — Innovate** (3 architecture options for contract decomposition), confirm:

- [ ] Scope (§2) matches expectation
- [ ] No critical feature missed from in-scope list
- [ ] Design decisions (§6) acceptable
- [ ] Test scenarios (§7) cover what feasibility demands
- [ ] Open questions (§9) acceptable to defer

Reply **"approve R, go to I"** to proceed, or list any items to revise.
