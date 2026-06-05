# 02 — Architecture Options (Phase I Output)

**Project:** retail-access-vault
**Date:** 2026-06-02
**Status:** Awaiting Phase P (decision/ADR) approval

---

## How to read this doc

Three architectural decompositions for the same functional requirements (§4 in `01-requirements.md`). All three use the same external mocks (USDC, Pruv, Liquid Buffer) — they differ in **how internal logic is decomposed across contracts**.

Each option is graded on:
- **Maps to PRD vocabulary** — does naming match PRD language?
- **Mechanism clarity** — how easy to trace a flow end-to-end?
- **Testability** — can scenarios be unit-tested cleanly?
- **Code size** — total lines, ballpark
- **POC fit** — appropriate for L1 mechanism proof?

---

## Option A — Monolithic Vault

### Diagram

```
┌──────────────────────────────────────────────────────┐
│              Vault.sol (single contract)              │
│                                                       │
│  - State machine (5 states)                          │
│  - launchpadDeposits mapping                         │
│  - Subscription queue (array + mapping)              │
│  - Redemption queue (array + mapping)                │
│  - Holds wRWA balance internally                     │
│  - Holds liquid buffer balance internally            │
│  - matching() internal                               │
│  - rebalance() internal                              │
│  - processEpoch() public                             │
│  - ERC-20 share token                                │
└──────────────────┬───────────────────────────────────┘
                   │ external calls
   ┌───────────────┼────────────────┬───────────────┐
   ▼               ▼                ▼               ▼
┌──────┐      ┌────────┐      ┌──────────┐    ┌────────┐
│ USDC │      │  Pruv  │      │ LiquidBuf│    │MockAMM │
│(mock)│      │ (mock) │      │  (mock)  │    │ (mock) │
└──────┘      └────────┘      └──────────┘    └────────┘
```

### Pros
- **Minimum contracts**: 1 production + 4 mocks
- **Simplest reasoning**: single source of truth, all flows in one file
- **Atomic state**: no cross-contract reentrancy paths to defend
- **Smallest deployment overhead** for demo

### Cons
- **Conflates custody and accounting**: PRD explicitly says "asset is locked in a custody" — diverges from terminology
- **Harder to test in isolation**: can't mock custody behavior for unit tests
- **Lots of state in one contract**: ~600-800 lines, tougher to review
- **Less obvious for reviewer**: PRD reader can't point at "this is the custody"

### Code size estimate
- Vault.sol: ~700 lines
- Mocks: ~300 lines combined
- Tests: ~600 lines
- **Total: ~1,600 lines**

### Map to PRD vocabulary
- ⚠️ "Custody" not a distinct entity — PRD readers will ask "where is custody?"
- ✅ Everything else maps directly

### Best for
Teams who value minimum surface area, prefer reading 1 file over jumping between 2+. Maps poorly to PRD's explicit "vault + custody" framing.

---

## Option B — Vault + Custody (PRD-aligned) ⭐ RECOMMENDED

### Diagram

```
┌─────────────────────────────────────┐
│           Vault.sol                 │
│  - State machine                    │
│  - launchpadDeposits mapping        │
│  - Subscription queue               │
│  - Redemption queue                 │
│  - matching() internal              │
│  - rebalance() internal             │
│  - processEpoch() public            │
│  - ERC-20 share token               │
│  - Calls custody for buy/sell/swap  │
└────────────┬────────────────────────┘
             │ controls
             ▼
┌─────────────────────────────────────┐
│           Custody.sol               │
│  - Holds wRWA balance               │
│  - Holds liquid buffer balance      │
│  - subscribeToPruv(usdc)            │
│  - redeemFromPruv(wrwa)             │
│  - swapLiquidForUSDC(amount)        │
│  - swapUSDCForLiquid(amount)        │
│  - totalIlliquidValueUSDC()         │
│  - totalLiquidValueUSDC()           │
│  - onlyVault modifier               │
└────────────┬────────────────────────┘
             │ external calls
  ┌──────────┼──────────┬─────────┐
  ▼          ▼          ▼         ▼
┌──────┐ ┌────────┐ ┌──────────┐ ┌────────┐
│ USDC │ │  Pruv  │ │ LiquidBuf│ │MockAMM │
└──────┘ └────────┘ └──────────┘ └────────┘
```

### Pros
- **Matches PRD vocabulary 1:1**: "Vault" and "Custody" are PRD nouns
- **Clear separation**: Vault = state/queue/accounting; Custody = token holding + DeFi calls
- **Custody mockable for unit tests**: Vault tests can use `MockCustody` to isolate state-machine logic
- **Easy reviewer mental model**: "vault talks to custody, custody talks to outside world"
- **Custody can later be replaced** with Alt-2 Balancer custody — clean swap surface
- **Auditable invariants**: Custody only holds assets; Vault only holds state/shares

### Cons
- One extra cross-contract call per buy/sell
- 2 contracts to deploy (still trivial)
- Slightly more boilerplate (modifier + interface)

### Code size estimate
- Vault.sol: ~500 lines
- Custody.sol: ~250 lines
- Mocks: ~300 lines combined
- Tests: ~700 lines
- **Total: ~1,750 lines**

### Map to PRD vocabulary
- ✅ "Custody" is a real contract — points directly to PRD diagram
- ✅ Vault token, queues, matching all in Vault — clean
- ✅ Alt-2 Balancer migration becomes "swap Custody implementation"

### Best for
**Standard recommended approach.** Matches PRD framing, separates concerns enough for testability without over-engineering. Reviewer can read PRD then code without context-switching vocab.

---

## Option C — Vault + Custody + StrategyManager (modular)

### Diagram

```
┌─────────────────────────────────────┐
│           Vault.sol                 │
│  - State machine                    │
│  - Queues                           │
│  - Shares ERC-20                    │
│  - processEpoch() orchestrator      │
└──┬────────────────┬─────────────────┘
   │ controls       │ delegates to
   ▼                ▼
┌──────────┐  ┌──────────────────────┐
│Custody   │  │ StrategyManager.sol  │
│.sol      │  │ - rebalanceCalc()    │
│- holds   │  │ - matchingCalc()     │
│  tokens  │  │ - 3-layer redeem     │
│- ERC-20  │  │   plan generator     │
│  ops     │  │ - pure functions     │
└──┬───────┘  │   for testability    │
   │          └──────────────────────┘
   │ external
   ▼
[mocks: USDC, Pruv, LiquidBuf, MockAMM]
```

### Pros
- **Pure-function strategy logic**: rebalance + matching as stateless functions → easy unit tests
- **Swap-able strategy**: future "rebalance v2" without touching Vault
- **Best separation of concerns**: state ≠ storage ≠ algorithm
- **Production-ready shape**: closer to how real production protocols (Yearn, Morpho) decompose

### Cons
- **Over-engineering for POC**: PRD has 1 strategy (rebalance to 80/20); abstraction has no payoff yet
- **More contracts**: 3 production + 4 mocks → 7 contracts to deploy + test
- **Indirection cost**: a reader chasing a flow now hops Vault → Strategy → Custody → External
- **Test boilerplate**: 3-layer mocking complicates scenario tests
- **Misaligned with "L1 only" goal**: this shape pays off when you have N strategies; we have 1

### Code size estimate
- Vault.sol: ~400 lines
- Custody.sol: ~250 lines
- StrategyManager.sol: ~300 lines
- Mocks: ~300 lines
- Tests: ~900 lines
- **Total: ~2,150 lines**

### Map to PRD vocabulary
- ✅ "Vault", "Custody" map
- ⚠️ "StrategyManager" is not a PRD term — extra concept for reader

### Best for
Teams who want to demonstrate **extensibility shape** in addition to mechanism. Suitable if L1 POC is intended as foundation for production hand-off; over-engineered if POC is purely mechanism proof.

---

## Comparison Table

| Criterion | A — Monolithic | B — Vault+Custody ⭐ | C — Modular |
|---|---|---|---|
| Contracts (prod) | 1 | 2 | 3 |
| Total code (LOC) | ~1,600 | ~1,750 | ~2,150 |
| Map to PRD vocab | ⚠️ partial | ✅ direct | ✅ + extra terms |
| Mechanism clarity | ✅ single file | ✅ 2 clear roles | ⚠️ 3 hops |
| Unit testability | ⚠️ harder | ✅ good | ✅ best |
| Reviewer onboarding | medium | easy | medium |
| Estimated dev time | 5-6 days | 6-7 days | 9-10 days |
| Alt-2 (Balancer) migration | rewrite | swap Custody impl | swap Custody impl |
| Over-engineering risk | low | low | medium |

---

## Recommendation

**Option B — Vault + Custody.**

### Why
1. **Closest PRD alignment** — Vault and Custody are both PRD nouns; reviewer never needs vocab translation.
2. **Right level of decomposition** — separates state (Vault) from token-holding (Custody), which is the exact line PRD draws.
3. **Future-proofs Alt-2** — switching to Balancer-backed custody becomes "swap Custody implementation" without touching Vault state machine.
4. **Unit-testable** — Vault state machine tests can use a mock Custody; Custody integration tests can use mock Pruv/Liquid.
5. **Avoids over-engineering** — no premature abstraction (Option C's StrategyManager has no second strategy to abstract).
6. **Time-fit** — 6-7 days estimated for full L1 POC matches "show mechanism" budget.

### Risk hedges if user prefers A or C
- If user prefers **A (monolithic)**: acceptable for ultra-lean POC; just note that PRD vocabulary will not appear in code structure.
- If user prefers **C (modular)**: acceptable if POC is also intended as production skeleton; expect ~50% longer dev time.

---

## Phase I — Approval Gate

To proceed to **Phase P** (write ADR + tech-stack + estimation), confirm:

- [ ] Which option to commit to (A / B / C)
- [ ] Any modifications to the chosen option
- [ ] Any deal-breakers in the rejected options I should record as lessons

Reply with selection.
