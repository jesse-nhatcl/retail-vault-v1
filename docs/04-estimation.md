# 04 — Effort Estimation (Phase P)

**Project:** retail-access-vault
**Date:** 2026-06-02
**Estimation basis:** 1 senior Solidity engineer, full-time, with Foundry expertise

---

## 1. Summary

| Metric | Estimate |
|---|---|
| **Total effort** | **6.5 to 8.5 working days** (≈ 1.5 calendar weeks with buffer) |
| **Most-likely** | **7 days** |
| **Risk-adjusted (90th pct)** | **9.5 days** |
| Total LOC | ~1,750 (production + tests + script) |
| Contracts | 2 production + 4 mocks + 2 interfaces + tests + 1 demo script |

This is a **mechanism-focused POC**. No security audit time, no UI, no production hardening, no testnet deployment. Local Anvil only.

---

## 2. Work Breakdown Structure

### Phase E1 — Foundation (Day 1)

| Task | Hours | Output |
|---|---|---|
| Initialise Foundry project, install deps | 1 | `foundry.toml`, `lib/`, remappings |
| Implement `MockUSDC` | 0.5 | ERC-20 6-decimal mintable |
| Implement `MockPruv` (subscribe/redeem + admin setPrice) | 1.5 | Behaves like Hamilton-Lane-style fund |
| Implement `MockLiquidBuffer` + `MockAMM` (1:1 swap) | 1 | Liquid asset + swap surface |
| Define interfaces (`IVault`, `ICustody`) | 1 | Locked per ADR 001 |
| Write `Fixture.sol` test helper | 2 | Reusable deploy + actor setup |
| **Day 1 subtotal** | **7h** | |

### Phase E2 — Custody contract (Day 2 morning)

| Task | Hours | Output |
|---|---|---|
| `Custody.sol` skeleton + `onlyVault` modifier | 1 | Auth boundary |
| `subscribeToPruv` / `redeemFromPruv` | 1 | Pruv integration |
| `swapLiquidForUSDC` / `swapUSDCForLiquid` | 1 | Liquid swap |
| `depositUSDC` / `withdrawUSDC` | 0.5 | USDC flow into/out |
| Balance views | 0.5 | wRWA, liquid, USDC balances |
| Custody unit tests | 1 | `Custody.t.sol`, ~10 cases |
| **Day 2 morning subtotal** | **5h** | |

### Phase E3 — Vault: state machine + launchpad (Day 2 afternoon + Day 3 morning)

| Task | Hours | Output |
|---|---|---|
| Vault skeleton + `State` enum + transition guards | 1.5 | State machine |
| Constructor + `initLaunchpad` + `configAsset` | 1 | Admin setup |
| `depositToLaunchpad` (with `launchpadDeposits` mapping) | 1 | Internal receipt |
| `transitionAfterDeadline` (success + fail branches) | 1.5 | Pruv subscription on success |
| `claimLaunchpadShares` + `refundLaunchpad` | 1 | Post-launchpad claim |
| Unit tests for launchpad happy + fail paths | 2 | Covers S2 partially |
| **Day 2/3 subtotal** | **8h** | |

### Phase E4 — Vault: sub/redeem queue + cancel (Day 3 afternoon)

| Task | Hours | Output |
|---|---|---|
| `Request` struct + queue arrays + `nextRequestId` | 1 | Queue data structure |
| `requestDeposit` (USDC custody, queue push) | 1 | Sub queue mechanics |
| `requestRedeem` (share lock, queue push) | 1 | Redeem queue mechanics |
| `cancelRequest` (ERC-7887-style) | 1 | Ownership check + refund |
| `claim(requestId)` skeleton (processing flag check) | 1 | Claim flow |
| **Day 3 subtotal** | **5h** | |

### Phase E5 — Vault: `processEpoch` core (Day 4 + Day 5 morning) ⚠️ HIGHEST RISK

| Task | Hours | Output |
|---|---|---|
| NAV computation (`totalAssets`, `nav`) | 1 | Reads custody + Pruv price |
| Queue snapshot + iteration setup | 1.5 | Bounded iteration to avoid OOG |
| Matching algorithm — pro-rata distribution | 3 | Both PRD cases (Sub>R, R>S) |
| Settle net sub: rebalance-toward-target formula | 2 | Custody.subscribeToPruv + swap |
| Settle net redeem: 3-layer (matching → liquid → illiquid) | 2.5 | Custody calls chained |
| Edge case: partial fulfillment (illiquid insufficient) | 1.5 | Rollover to next epoch |
| Events for all mutations | 0.5 | Observability |
| **Day 4/5 subtotal** | **12h** | |

### Phase E6 — Vault: wind-down (Day 5 afternoon)

| Task | Hours | Output |
|---|---|---|
| `triggerWindDown` + state guard | 0.5 | Admin trigger |
| Refund pending subscription queue | 0.5 | |
| Liquidate all liquid buffer | 0.5 | Swap to USDC |
| Settle redemption queue from USDC pool | 1 | Burn shares, pay USDC |
| Illiquid liquidation loop | 1.5 | Pruv redeem all |
| Final stable distribution | 0.5 | Last-mile claims |
| **Day 5 subtotal** | **4.5h** | |

### Phase E7 — Demo script (Day 6 morning)

| Task | Hours | Output |
|---|---|---|
| `Demo.s.sol` skeleton with `--sig 'run(string)'` | 1 | Entry point |
| Wire each S1-S8 branch | 3 | 8 scenarios |
| Colored output helpers (ANSI in console2) | 1 | Pretty diffs |
| Smoke-run all scenarios | 1 | Catch obvious bugs |
| **Day 6 morning subtotal** | **6h** | |

### Phase E8 — Scenario tests (Day 6 afternoon + Day 7)

| Task | Hours | Output |
|---|---|---|
| S1 happy path test | 1 | Full lifecycle |
| S2 launchpad fail test | 0.5 | |
| S3 cancel pending test | 0.5 | |
| S4 matching Sub>R test | 1.5 | Exact PRD numbers |
| S5 matching R>S test | 1.5 | Exact PRD numbers |
| S6 illiquid fallback test | 1 | Buffer drain → Pruv |
| S7 NAV change test | 1 | Price 1.0 → 1.1 → 0.9 |
| S8 wind-down mid-epoch test | 1.5 | Full close cycle |
| Invariant test (optional) | 1 | `totalAssets ≥ obligations` |
| **Day 6/7 subtotal** | **9.5h** | |

### Phase E9 — Polish + docs (Day 8)

| Task | Hours | Output |
|---|---|---|
| NatSpec for all external functions | 1.5 | Documentation |
| `forge fmt` + clean warnings | 0.5 | |
| Run `slither` and address P0/P1 only | 1 | Static analysis sanity |
| README in `code/` with how-to-run | 1 | Onboarding |
| Gas-report snapshot (non-critical) | 0.5 | `forge test --gas-report > gas.txt` |
| Update `05-spec.md` cross-references | 1 | Phase E ↔ spec linking |
| **Day 8 subtotal** | **5.5h** | |

---

## 3. Aggregate

| Day | Hours | Cumulative |
|---|---|---|
| Day 1 | 7h | 7h |
| Day 2 | 8h (5 custody + 3 vault start) | 15h |
| Day 3 | 8h (vault launchpad + queue) | 23h |
| Day 4 | 7h (processEpoch part 1) | 30h |
| Day 5 | 8h (processEpoch finish + wind-down) | 38h |
| Day 6 | 8h (demo script + scenarios start) | 46h |
| Day 7 | 7.5h (scenarios continue) | 53.5h |
| Day 8 | 5.5h (polish) | 59h |
| **Total** | **~59 hours ≈ 7.4 working days** | |

Rounding to **7 days most-likely**.

---

## 4. Risks & Buffers

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | `processEpoch` matching math has subtle bugs (pro-rata, rounding) | High | +1 day | Heavy unit tests on matching cases; use OZ Math.mulDiv |
| R2 | Rebalance-toward-target formula edge cases (overshooting, zero divides) | Medium | +0.5 day | Property test: post-state ratio close to target |
| R3 | Wind-down with partial illiquid windows | Medium | +0.5 day | POC simplifies: assume Pruv window always open |
| R4 | Stack-too-deep in Vault.sol | Medium | +0.5 day | Enable `viaIR` if needed; or split into internal helpers |
| R5 | OpenZeppelin v5 API surprise (vs v4 patterns) | Low | +0.25 day | Check `ERC20`, `Ownable`, `ReentrancyGuard` API early |
| R6 | Demo script ANSI colors not rendering | Low | +0.25 day | Plain-text fallback if `vm.envBool("PLAIN")` set |
| R7 | Scenario S6 (illiquid fallback) reveals rollover edge cases | Medium | +1 day | Document as deferred if blocking; satisfy on next epoch |

**Most-likely path:** 7 days
**With R1 + R2 + R7 occurring:** 9.5 days (90th percentile)
**P50 → P90 range:** 7 → 9.5 days

---

## 5. Out-of-Scope (will NOT add to estimate)

- Frontend / UI
- Cross-chain bridge implementation
- Aave reinvest integration
- Curve formula research
- Mainnet/testnet deployment
- Security audit
- Gas optimisation pass
- Role-based access control
- ERC-4626 full compliance
- Real NAV oracle

If any of these get pulled in mid-execution, **stop and re-estimate**.

---

## 6. Calendar Mapping (illustrative)

Assuming start Mon 2026-06-08:

| Day | Date | Phase | Output |
|---|---|---|---|
| 1 | Mon 06-08 | Foundation | Foundry project + 4 mocks + fixture |
| 2 | Tue 06-09 | Custody + Vault start | Custody.sol + state machine |
| 3 | Wed 06-10 | Vault launchpad + queue | Subscribe/redeem queue mechanics |
| 4 | Thu 06-11 | processEpoch part 1 | NAV + matching |
| 5 | Fri 06-12 | processEpoch finish + wind-down | Settle delta + close |
| — | Sat/Sun | — | — |
| 6 | Mon 06-15 | Demo script + scenarios start | Demo.s.sol + S1-S4 tests |
| 7 | Tue 06-16 | Scenarios finish | S5-S8 tests + invariants |
| 8 | Wed 06-17 | Polish + docs | NatSpec + slither + README |

**Delivery target:** Wed 2026-06-17 (most-likely).

---

## 7. Approval Gate Items (Phase P → E)

To proceed to Phase E (implementation), confirm:

- [ ] Estimate range (7-9.5 days) acceptable
- [ ] Foundry tech stack acceptable
- [ ] Code conventions acceptable
- [ ] Risk register acknowledged
- [ ] Calendar workable (or different start date)
