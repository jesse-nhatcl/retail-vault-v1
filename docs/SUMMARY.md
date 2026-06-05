# Executive Summary — Retail Access Vault POC

> Audience: Manager, Tech Lead, Product. Reading time ~8 minutes. Deeper than a one-pager so a decision-maker can sign off without reading the full spec.

---

## TL;DR

A **local proof-of-concept** for the Retail Access PRD's **Alternative 1** design: an ERC-7540-style async vault wrapping a private credit fund (Hamilton Lane, simulated as `MockPruv`) plus a ~20% liquid buffer. Solidity contracts on a single Anvil chain, no production deployment, no UI. The goal is to prove the **mechanism** — state machine, queue, matching, 3-layer redemption — works coherently. **Estimate: 7 days most-likely, 9.5 days P90** for one senior Solidity engineer.

---

## 1. What we're building

A **retail access wrapper** around an illiquid private credit fund. Retail users deposit USDC anytime; the protocol pools deposits, hits the fund's minimum ticket size, and holds the wrapped position. A liquid buffer absorbs typical redemption pressure; only when the buffer is exhausted does the protocol redeem from the illiquid underlying.

- **Form**: Solidity smart contracts + Foundry tests + a parameterised demo script (`forge script Demo --sig 'run(string)' "S<n>"`)
- **Network**: single local Anvil chain — no bridge, no testnet
- **Mocks**: `MockUSDC`, `MockPruv`, `MockLiquidBuffer`, `MockAMM`
- **Production**: 2 contracts — `Vault.sol` (state, queues, shares, matching) + `Custody.sol` (token holder + DeFi interactions)
- **NOT a product**: no UI, no audit hardening, no real Pruv integration, no mainnet
- **NOT economics validation**: APY math is mechanical, not stress-tested across market regimes

---

## 2. Why Alt-1 over Alt-2

The PRD describes two design alternatives for how subscription assets are held:

| Aspect | **Alt-1 (chosen)** | Alt-2 |
|---|---|---|
| Asset holder | Custody contract we build | Balancer pool (3rd-party) |
| Share issuance | Vault mints directly | Balancer ETF token → Vault wraps |
| `totalAssets()` | NAV oracle on our custody | Balancer ETF price |
| Dependency | None external | Balancer protocol |
| POC traceability | Direct, end-to-end auditable | Wrapped behind a 3rd-party |
| Future Alt-2 swap | Swap the Custody implementation | Already Balancer |

**Alt-1 is the cleaner POC subject** because every component is something we own and can reason about. Alt-2 obscures the mechanism behind Balancer's pool math.

---

## 3. Why L1 verification depth (not L2 or L3)

"Prove feasibility" can mean three different things. We picked the lightest layer that still answers the question.

| Layer | What it proves | POC scope at this layer |
|---|---|---|
| **L1 — Mechanism logic** | State transitions, queue math, matching arithmetic, 3-layer redemption all work | Solidity contracts + Foundry scenario tests (chosen) |
| L2 — Integration shape | All component wiring is correct end-to-end with realistic external dependencies | + fork mainnet, mock Aave + Curve, multi-chain |
| L3 — Economic viability | Blended APY actually materialises, fee model sustains, edge-case losses bounded | + simulation runner across hundreds of epochs, P&L per investor archetype |

L1 is sufficient to confirm "the mechanism described in the PRD is implementable and behaves as described". L2/L3 are deferred to post-POC phases.

---

## 4. Architecture

```
┌────────────────────────────────────────┐
│            Vault.sol                   │
│  ───────────────────────────────       │
│  - State machine (5 states)            │
│  - Subscription queue (ERC-7540)       │
│  - Redemption queue (ERC-7540)         │
│  - Matching engine (P2P netting)       │
│  - processEpoch() orchestrator         │
│  - ERC-20 share token                  │
└────────────────┬───────────────────────┘
                 │ owns / controls
                 ▼
┌────────────────────────────────────────┐
│            Custody.sol                 │
│  ───────────────────────────────       │
│  - Holds wRWA balance                  │
│  - Holds liquid buffer balance         │
│  - Holds idle USDC                     │
│  - subscribe/redeem Pruv               │
│  - swap liquid ↔ USDC                  │
│  - onlyVault gate                      │
└────────────────┬───────────────────────┘
                 │ external calls
   ┌─────────────┼─────────────┬──────────┐
   ▼             ▼             ▼          ▼
[MockUSDC]  [MockPruv]  [MockLiquidBuffer] [MockAMM]
```

**Why two contracts (not one):** "Custody" is a PRD noun — a reviewer reading the PRD expects to point at "the custody contract". Putting it in its own file:
- Mirrors PRD vocabulary 1:1
- Makes the trust boundary explicit (Custody only accepts calls from Vault)
- Lets us unit-test the Vault state machine with a mock Custody
- Future Alt-2 migration becomes "swap Custody implementation, leave Vault untouched"

**Why not three contracts (Vault + Custody + StrategyManager):** there's only one rebalance strategy. Abstracting it into a manager is premature — YAGNI.

Full architecture: `02-architecture/diagrams/system-arch.png`.

---

## 5. Mechanism design decisions (with rationale)

Each decision below answers a "why this and not the alternative" question that came up during requirements analysis. These are **locked** — implementation must follow.

### 5.1 ERC-7540 async queue (not synchronous mint)
**Decision:** Subscription and redemption are **request → queue → fulfill at epoch**, not instant mint/burn.
**Rationale:** The underlying fund (Hamilton Lane) only opens subscription/redemption windows periodically. We can't synchronously call Pruv on every user deposit. Queueing also lets us aggregate small deposits to hit Pruv's minimum ticket size.

### 5.2 ERC-7887 cancel pending subscription
**Decision:** Users can call `cancelRequest(requestId)` to withdraw a queued subscription before it's processed.
**Rationale:** Funds sitting in a queue for up to one epoch is a UX concern. Cancel costs nothing extra (we just don't include the request in iteration) and gives user agency.

### 5.3 Internal mapping for launchpad receipts (not separate ERC-20)
**Decision:** During the launchpad phase, USDC deposits are tracked via `mapping(address => uint256) launchpadDeposits;`. No transferable receipt token is minted.
**Rationale:** The PRD says "receipts but not tokens". A separate transferable receipt would mean another ERC-20 contract + claim flow + corner cases (transfer during launchpad? cancel after transfer?) for no POC value. Internal mapping is simpler and unambiguous.

### 5.4 Single `processEpoch()` (not separate sub/redeem processors)
**Decision:** One admin-gated function processes both the subscription queue and the redemption queue atomically, with matching running first.
**Rationale:** The matching system requires comparing the two queues at the same point in time. Splitting into `processSubscriptions()` + `processRedemptions()` would either lose matching entirely or re-introduce a synchronization barrier. PRD §"Matching System" describes the netting at "the end of an epoch" — single trigger matches PRD semantics.

### 5.5 Admin manually calls `MockPruv.setPrice()` before each epoch (not oracle)
**Decision:** The illiquid asset's price is set manually by the admin via `MockPruv.setPrice(newWRWAPriceInUSDC)`. Vault reads this price to compute NAV.
**Rationale:**
- **POC simplicity**: an oracle adds infrastructure complexity (Chainlink, push/pull, staleness checks) without changing mechanism.
- **Test controllability**: manual price lets us script any NAV scenario (price up, down, flat) for exact-number assertions in tests.
- **Production concern, not POC concern**: in production, this would be replaced by Pruv's actual NAV reporting (or an oracle wrapping it). The Vault interface doesn't change.

### 5.6 Rebalance-toward-target asset sourcing (not fixed split)
**Decision:** When the vault buys assets for net subscriptions, it computes target allocations and buys the **under-allocated sleeve preferentially** to push back toward 80/20.
**Rationale:**
- **Fixed split (80/20 every time)**: simpler but lets the ratio drift (e.g., if liquid was drained earlier, fixed split won't refill).
- **Rebalance-toward-target**: maintains the strategy invariant. Closer to how a real fund manager operates.
- The PRD explicitly mentions "adjust the purchase to balance the custody back to strategy" in Alt-2's description; we apply the same principle to Alt-1.

### 5.7 3-layer redemption order: matching → liquid → illiquid
**Decision:** When fulfilling redemptions, source USDC in this strict order: (1) match against subscribers in the same epoch, (2) drain the liquid buffer, (3) redeem from the illiquid Pruv position.
**Rationale:** This is the PRD's prescribed order, and it minimises cost:
- **Layer 1 (matching)**: P2P netting costs nothing — no Pruv interaction, no liquid swap fees.
- **Layer 2 (liquid buffer)**: cheap swap, doesn't trigger Pruv's subscription/redemption window dependency.
- **Layer 3 (illiquid)**: expensive — requires Pruv redemption window, may move underlying price.

Going in any other order would burn money or block redemptions unnecessarily.

### 5.8 Matching uses NAV at epoch time (not request time)
**Decision:** When a user `requestRedeem(shares)`, the USDC value is **not fixed** at request time. It's computed at epoch time using the NAV that's current then.
**Rationale:** Users are exposed to NAV movement during the queue period — same as a real-world redemption window. Fixing the redemption value at request time would create an arbitrage (request at high NAV, queue, NAV drops, claim at old high value). ERC-7540 standard practice handles this the same way.

### 5.9 Single owner admin (not role-based)
**Decision:** One EOA (the deployer) holds all admin powers: `initLaunchpad`, `configAsset`, `processEpoch`, `triggerWindDown`, `setPrice` (on the Pruv mock).
**Rationale:** Multi-role (PRICE_ORACLE, KEEPER, ADMIN) is production-grade access control. For a POC, it's noise — adds boilerplate without changing mechanism. We use OpenZeppelin `Ownable` and call it done.

### 5.10 Custody separated from Vault (not monolithic)
**Decision:** Two production contracts. Vault holds state; Custody holds tokens.
**Rationale:** see §4 above — PRD vocabulary alignment + future Alt-2 swap point + unit-test isolation.

### 5.11 Single Anvil chain, Pruv as on-chain mock (not cross-chain)
**Decision:** Pruv is a contract deployed on the same Anvil chain as the Vault. No bridge.
**Rationale:** A real cross-chain bridge implementation would consume 3-5 days for no L1 mechanism payoff. The mechanism is identical whether the asset lives on the same chain or another chain — only the wire format differs. Bridge realism is L2 scope, deferred.

---

## 6. State machine

```
[*] → Initialized → LaunchpadStart → ┬→ EpochBased → WindDown → Closed
                                     │
                                     └→ LaunchpadFail
```

| State | Entered when | Allowed operations |
|---|---|---|
| `Initialized` | `constructor` | Admin: `initLaunchpad`, `configAsset` |
| `LaunchpadStart` | launchpad start time reached | Users: `depositToLaunchpad`. Anyone: `transitionAfterDeadline` |
| `LaunchpadFail` | end time reached, min not met | Users: `refundLaunchpad` (terminal except for refunds) |
| `EpochBased` | end time reached, min met | Users: `requestDeposit`, `requestRedeem`, `cancelRequest`, `claim`. Admin: `processEpoch`, `setPrice` (on Pruv) |
| `WindDown` | admin triggered | Users: `claim` only. Admin: continue settlement |
| `Closed` | all redemptions settled | None (terminal) |

State transitions are **one-way**. Full diagram: `02-architecture/diagrams/state-machine.png`.

---

## 7. The 8 verification flows

These 8 scenarios are the acceptance criteria for the POC. Each one corresponds to a test file (`test/scenarios/S<n>_*.t.sol`) and a branch in the demo script (`forge script Demo --sig 'run(string)' "S<n>"`).

### S1 — Happy Path Full Lifecycle

**Setup:** 3 users (Alice, Bob, Charlie) with funded MockUSDC balances. Vault configured: min = 50,000 USDC, target ratio 80/20.

**Steps:**
1. Deploy Vault + Custody + Mocks. State = `Initialized`.
2. `vm.warp` to launchpad start time. State → `LaunchpadStart`.
3. Alice `depositToLaunchpad(30,000)`, Bob `depositToLaunchpad(30,000)`, Charlie `depositToLaunchpad(40,000)`. Total locked = 100,000.
4. `vm.warp` past launchpad end time. Anyone calls `transitionAfterDeadline()`.
5. Since 100,000 ≥ 50,000 min → state → `EpochBased`. Custody now holds 80,000 USDC worth of wRWA + 20,000 liquid. Total share supply = 100,000.
6. Each user calls `claimLaunchpadShares()` → receives shares pro-rata to their deposit.
7. Alice `requestDeposit(10,000)`. Bob `requestRedeem(5,000 shares)`.
8. Admin: `MockPruv.setPrice(1e18)` (NAV unchanged), then `processEpoch()`.
9. Matched = 5,000 USDC. Alice gets 5,000 matched shares + 5,000 net-sub shares. Bob gets 5,000 USDC.
10. Alice and Bob `claim(requestId)`.
11. Admin `triggerWindDown()`. State → `WindDown`. Settlement loops execute.
12. After settlement, state → `Closed`.

**What it proves:** End-to-end lifecycle works; no balance is lost in transitions.

---

### S2 — Launchpad Fail + Refund

**Setup:** Min = 50,000 USDC. Only Alice deposits.

**Steps:**
1. Reach `LaunchpadStart`.
2. Alice `depositToLaunchpad(30,000)`. Total locked = 30,000 < min.
3. `vm.warp` past launchpad end time. Anyone calls `transitionAfterDeadline()`.
4. 30,000 < 50,000 → state → `LaunchpadFail`.
5. Alice calls `refundLaunchpad()`.

**Expected:** Alice's USDC balance restored to original. Vault holds zero. State remains `LaunchpadFail` (terminal except for refunds).

**What it proves:** Failure path is safe; no user funds are stuck.

---

### S3 — ERC-7887 Cancel Pending Subscription

**Setup:** Vault in `EpochBased` state.

**Steps:**
1. Alice `requestDeposit(10,000)`. USDC pulled into Vault. SubQueue has 1 entry.
2. Before admin calls `processEpoch`, Alice calls `cancelRequest(requestId)`.
3. Admin calls `processEpoch()`.

**Expected:** Alice's USDC returned. SubQueue contains a cancelled entry (skipped during iteration). Epoch processes as a no-op (no sub, no redeem).

**What it proves:** Users have agency to withdraw pending requests. Cancelled entries don't break iteration.

---

### S4 — Matching: Subscription > Redemption (PRD Case 1)

**Setup:** Vault has 80,000 USDC worth of wRWA + 20,000 liquid buffer. Total share supply = 100,000. NAV = 1.00.

**Steps:**
1. Alice `requestDeposit(10,000 USDC)`.
2. Bob `requestRedeem(4,000 shares)`. At NAV 1.00, his redemption is worth 4,000 USDC.
3. Admin `processEpoch()`.

**Expected:**
- Matching: `matched = min(10,000, 4,000) = 4,000`.
- Bob receives **4,000 USDC** (sourced from Alice's pool, not from custody).
- Alice receives **4,000 matched shares** (sourced from Bob's burnt shares, not newly minted).
- Net subscription = 10,000 − 4,000 = 6,000 USDC.
- Custody buys assets per rebalance-toward-target (with mocks at 1:1, the split is approximately 80/20 = 4,800 wRWA + 1,200 liquid).
- Alice receives **6,000 net-sub shares** (freshly minted at NAV 1.00).
- Alice's total shares = 4,000 (matched) + 6,000 (net) = **10,000**.

**What it proves:** Matching netting works for the "more subs than redemptions" case. Vault saves a Pruv interaction worth 4,000 USDC.

---

### S5 — Matching: Redemption > Subscription (PRD Case 2)

**Setup:** Same as S4. Custody = 80,000 wRWA + 20,000 liquid; supply = 100,000; NAV = 1.00.

**Steps:**
1. Alice `requestDeposit(4,000 USDC)`.
2. Bob `requestRedeem(10,000 shares)`. Worth 10,000 USDC at NAV 1.00.
3. Admin `processEpoch()`.

**Expected:**
- Matching: `matched = min(4,000, 10,000) = 4,000`.
- Alice receives **4,000 matched shares**.
- Bob receives **4,000 USDC** from the match.
- Net redemption = 10,000 − 4,000 = 6,000 USDC.
- **Layer 2 (liquid buffer)**: Custody has 20,000 liquid; 6,000 ≤ 20,000 → swap 6,000 liquid for 6,000 USDC.
- Bob receives an **additional 6,000 USDC** from the liquid layer.
- Bob's 10,000 shares are burnt.
- Custody now holds: 80,000 wRWA + 14,000 liquid.

**What it proves:** Matching + Layer 2 redemption work for the "more redemptions than subs" case. No illiquid touch needed when buffer suffices.

---

### S6 — Redemption Needs Illiquid Fallback

**Setup:** Liquid buffer has been drained to 2,000 USDC (from earlier activity). Custody = 90,000 wRWA + 2,000 liquid. Supply = 100,000. NAV = 1.00.

**Steps:**
1. Alice `requestRedeem(8,000 shares)`.
2. Admin `processEpoch()`.

**Expected:**
- No subscriptions in queue → matching produces zero.
- Net redemption = 8,000 USDC.
- **Layer 2 (liquid)**: 2,000 available → 2,000 used. Remaining need = 6,000.
- **Layer 3 (illiquid)**: redeem 6,000 USDC worth of wRWA from Pruv. Custody now holds 84,000 wRWA + 0 liquid.
- Alice receives **8,000 USDC**.

**What it proves:** The 3-layer redemption falls through correctly. Layer 3 only triggers when Layer 2 is insufficient.

---

### S7 — NAV Change Affects Calculations

**Setup:** Vault supply = 100,000. Custody = 80,000 wRWA + 20,000 liquid. Initial NAV = 1.00.

**Steps:**
1. Admin calls `MockPruv.setPrice(1.1e18)` — wRWA appreciates 10%.
2. Now `totalAssets()` = 80,000 × 1.1 + 20,000 = 108,000. NAV = 1.08.
3. Alice `requestRedeem(10 shares)`.
4. Admin `processEpoch()`.

**Expected:** Alice receives **10.8 USDC** (10 × 1.08), not 10 USDC. This is sourced from the liquid buffer (Layer 2).

**What it proves:** NAV is computed at epoch time, and redemption value reflects updated price. Asymmetric value bookkeeping works.

---

### S8 — Wind-Down Mid-Epoch

**Setup:** Vault in `EpochBased` with active queues: sub queue holds 5,000 USDC; redeem queue holds 5,000 shares. Custody = 80,000 wRWA + 20,000 liquid. NAV = 1.00.

**Steps:**
1. Admin calls `triggerWindDown()`.

**Expected sequence inside `triggerWindDown`:**
- State → `WindDown`.
- All pending sub requests refunded — Vault returns 5,000 USDC to the subscriber.
- All liquid buffer swapped to USDC — Custody gets 20,000 USDC, 0 liquid.
- Settle redeem queue from accumulated USDC: 5,000 shares × NAV 1.00 = 5,000 USDC paid. 5,000 shares burnt.
- Custody now: 80,000 wRWA + 15,000 USDC (unused, since redeem queue is settled).
- If supply remains, illiquid liquidation begins: redeem all wRWA from Pruv → 80,000 USDC.
- Final pool of USDC available for remaining vault token holders to `claim()` pro-rata over 30 days.
- After 30 days, state → `Closed` (terminal).

**What it proves:** Wind-down handles all in-flight obligations cleanly. No user is stranded.

---

## 8. Tech stack (concrete)

| Item | Choice | Why |
|---|---|---|
| Language | Solidity 0.8.24 | Latest stable, supports transient storage, PUSH0 |
| Toolchain | Foundry (forge, anvil, cast) | 10-50× faster than Hardhat; `vm.warp` for epoch testing; `forge script` for parameterised demo |
| Libraries | OpenZeppelin Contracts 5.0+ | `ERC20`, `Ownable`, `ReentrancyGuard`, `Math.mulDiv`, `SafeERC20` |
| Test framework | forge-std 1.9+ | `Test`, `Script`, `console2`, cheatcodes |
| Lint/format | `forge fmt` | Built-in |
| Static analysis | `slither` (end of phase) | Sanity check |

**Code organisation** (under `code/` inside the project):
```
src/
  Vault.sol
  Custody.sol
  interfaces/  IVault.sol, ICustody.sol
  mocks/       MockUSDC, MockPruv, MockLiquidBuffer, MockAMM
test/
  Vault.t.sol         unit tests
  Custody.t.sol       unit tests
  scenarios/          S1..S8 scenario tests
  helpers/Fixture.sol shared test setup
script/Demo.s.sol     parameterised demo with --sig 'run(string)' "S<n>"
```

Full details: `03-tech-stack.md`.

---

## 9. Cost & timeline

| Metric | P50 (most likely) | P90 (risk-adjusted) |
|---|---|---|
| **Effort** | **7 working days** | **9.5 working days** |
| Calendar | ~1.5 weeks | ~2 weeks |
| LOC (production + tests) | ~1,750 | — |
| Engineer profile | 1 senior Solidity engineer with Foundry experience | — |

### Work breakdown (P50, in working hours)

| Day | Sub-phase | Hours |
|---|---|---|
| 1 | Foundation — Foundry setup + 4 mocks + Fixture | 7 |
| 2 | Custody contract + Vault state machine start | 8 |
| 3 | Vault: launchpad + sub/redeem queue | 8 |
| 4 | `processEpoch` part 1 — NAV + matching | 7 |
| 5 | `processEpoch` finish + wind-down | 8 |
| 6 | Demo script + first 4 scenario tests | 8 |
| 7 | Remaining 4 scenario tests + invariants | 7.5 |
| 8 | Polish — NatSpec, slither, README, gas report | 5.5 |
| **Total** | | **~59 hours** |

Full WBS: `04-estimation.md`.

---

## 10. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | `processEpoch` matching math bugs (pro-rata, rounding) | High | +1 day | Heavy unit tests, OpenZeppelin `Math.mulDiv` |
| R2 | Rebalance formula edge cases (overshoot, zero divide) | Medium | +0.5 day | Property test: post-state ratio close to target |
| R3 | Wind-down with partial illiquid windows | Medium | +0.5 day | POC simplifies: assume Pruv window always open |
| R4 | Stack-too-deep in `Vault.sol` | Medium | +0.5 day | Enable `viaIR`; split into internal helpers |
| R5 | OpenZeppelin v5 API differences vs v4 | Low | +0.25 day | Check `ERC20`/`Ownable`/`ReentrancyGuard` early |
| R6 | Demo script ANSI colour rendering | Low | +0.25 day | Plain-text fallback via env var |
| R7 | Scenario S6 (illiquid fallback) reveals rollover edge cases | Medium | +1 day | Document rollover; satisfy in subsequent epoch |

P50 → P90 buffer = +2.5 days.

---

## 11. Out of scope (will NOT be implemented)

Any item below pulled into scope → **stop and re-estimate**.

- ❌ Frontend / UI
- ❌ Cross-chain bridge (real Pruv chain)
- ❌ Aave reinvest of idle USDC in subscription queue
- ❌ Curve swap formula (mock AMM at 1:1 substitutes)
- ❌ Real Pruv API integration (interface assumed in mocks)
- ❌ Role-based access control (single owner only)
- ❌ Linear NAV oracle / Chainlink (manual `setPrice` only)
- ❌ ERC-4626 full compliance (custom share token instead)
- ❌ Gas optimisation pass
- ❌ Security audit / formal verification
- ❌ Mainnet or testnet deployment
- ❌ Fee model (perf / mgmt / redemption fees — all 0% in POC)

---

## 12. Deferred questions (revisit post-POC)

| Q | Item | When to revisit |
|---|---|---|
| Q1 | Curve swap formula choice | Phase 2 — real liquidity layer |
| Q2 | Aave reinvest economics | Phase 2 — yield optimisation |
| Q3 | Cross-chain bridge realism | When integrating real Pruv |
| Q4 | Real Pruv API contract shape | When Pruv testnet is available |
| Q5 | NAV oracle design | Production-only |
| Q6 | Fee model (perf / mgmt / redemption) | After mechanism validated |
| Q7 | ERC-4626 full compatibility | If ecosystem integration is needed |
| Q8 | Partial redemption rollover semantics | Edge case for production |
| Q9 | Wind-down "time limit" (POC defaults to 30 days) | Product review |

---

## 13. Documents — who reads what

| File | Primary audience | Use |
|---|---|---|
| `SUMMARY.md` (this file) | Manager, Product, Tech Lead | Decision-grade overview |
| `05-spec.md` | Engineer | **The implementation reference** — self-contained |
| `04-estimation.md` | PM, Tech Lead | WBS with day-by-day breakdown |
| `03-tech-stack.md` | Engineer | Toolchain, conventions, project layout |
| `02-architecture/decision.md` | Tech Lead | ADR 001 — Vault + Custody rationale |
| `02-architecture/options.md` | Tech Lead | 3 architecture alternatives evaluated |
| `01-requirements.md` | PM, Engineer | Functional requirements in detail |
| `02-architecture/diagrams/*.png` | All | Visual references |
| `00-brief.md` | Audit trail | Original PRD content (Alt-1 context) |
| `project.json` | Tooling | Project metadata |

---

## 14. Sign-off items

Manager / Tech Lead approval needed on:

1. **Go / no-go for POC** — is 7-9.5 days of senior engineering time acceptable?
2. **Engineer assignment** — one senior Solidity engineer with Foundry experience, full-time
3. **Scope lock** — any scope expansion (Aave, bridge, UI, real Pruv) triggers re-estimation
4. **Phase E checkpoint** — code review + all 8 scenario outputs verified before sign-off as "POC complete"
5. **Decision lock** — all 11 mechanism design decisions in §5 are accepted as-is (or flag specific ones to revisit)

Reply with approval or specific items to revise.
