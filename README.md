# Retail Access Vault — Mechanism POC

A **local proof-of-concept** proving that the Retail Access PRD's **Alternative 1** design works as
described: an ERC-7540-style async vault that pools retail USDC, wraps an illiquid private credit
fund (Hamilton Lane Evergreen, simulated as `MockPruv`), holds a ~20% liquid buffer, and serves
permissionless subscriptions/redemptions through a **queue + P2P matching + 3-layer redemption**
protocol.

> This is **not a product**: no UI, no mainnet, no bridge, no real fund integration, no audit
> hardening, no fees (all 0%). The goal is to prove the *mechanism logic* is implementable and
> behaves exactly as specified. Full spec: [`docs/05-spec.md`](docs/05-spec.md); decision-grade
> overview: [`docs/SUMMARY.md`](docs/SUMMARY.md).

---

## What this POC demonstrates

Eight verification scenarios, each mapped to an automated test **and** a human-readable demo branch.
Together they prove every moving part of the mechanism:

| # | Scenario | What it proves |
|---|----------|----------------|
| **S1** | Happy path full lifecycle | Money flows launchpad → epoch → wind-down with nothing lost |
| **S2** | Launchpad fail + refund | Below minimum, every depositor is refunded 100% |
| **S3** | Cancel pending subscription | A user can withdraw a queued request before it's processed (ERC-7887) |
| **S4** | Matching: sub > redeem | Subscriptions/redemptions net off peer-to-peer; only the surplus hits the fund |
| **S5** | Matching: redeem > sub | Excess redemptions are paid from the liquid buffer, not the illiquid fund |
| **S6** | Illiquid fallback | When the buffer is exhausted, redemption falls through to the fund |
| **S7** | NAV change | When the underlying appreciates, redeemers are paid the higher NAV |
| **S8** | Wind-down mid-epoch | Wind-down cleanly settles all in-flight obligations; no user stranded |

---

## Demoing to stakeholders

The fastest way to *show* the mechanism working. No deployment, no setup beyond installing Foundry —
it runs entirely on a simulated chain and prints a narrated, verified walkthrough.

**Run all eight scenarios with an acceptance summary:**

```bash
forge script script/Demo.s.sol --sig 'run(string)' "ALL" -vvv
```

**Run a single scenario** (great for walking through one mechanism live):

```bash
forge script script/Demo.s.sol --sig 'run(string)' "S4" -vvv
```

Each scenario prints numbers in plain units (USDC, shares, NAV — not raw token base units), states
**what it proves**, and ends with a `RESULT: PASS`. The PASS is not cosmetic: each demo asserts its
key numbers with on-chain `require`s, so if the mechanism were wrong the run would abort.

Sample output (S4):

```
==================================================
  S4: Matching - Subscription > Redemption
==================================================
  WHAT THIS PROVES: Subscriptions and redemptions net off P2P; only the surplus hits the fund.

      Portfolio: 80,000.00 USDC illiquid + 20,000.00 USDC liquid | supply 100,000 shares | NAV 1.00
  > Alice subscribes 10,000; Bob redeems 4,000 shares (NAV 1.00).
      [ok] Matched 4,000 P2P (no fund interaction). Net subscription 6,000.
      [ok] Rebalance buy: 4,800 illiquid + 1,200 liquid (toward 80/20).
      Portfolio: 84,800.00 USDC illiquid + 21,200.00 USDC liquid | supply 106,000 shares | NAV 1.00
      [ok] Alice received 10,000 shares; Bob received 4,000 USDC.

  RESULT: PASS - P2P netting saved a 4,000 USDC fund round-trip.
```

The `ALL` run finishes with:

```
##################################################
#            ACCEPTANCE SUMMARY                  #
##################################################
  [PASS] S1  Happy path full lifecycle
  [PASS] S2  Launchpad fail + full refund
  ...
  8 / 8 mechanism scenarios verified.
```

### Suggested 5-minute demo flow

1. `... "S1" -vvv` — the full lifecycle end-to-end: everyone deposits, one trading epoch, wind-down,
   everyone is made whole. The big picture.
2. `... "S4" -vvv` — the headline feature: **peer-to-peer matching** saves a fund round-trip.
3. `... "S6" -vvv` — the **3-layer redemption** falling through to the illiquid fund when the buffer
   runs dry.
4. `... "S7" -vvv` — the vault tracks **NAV**: a 10% gain pays redeemers 10% more.
5. `... "ALL"` — the acceptance summary: 8/8 verified.

---

## Running the tests

The automated test suite is the rigorous proof behind the demo (36 tests, exact-number assertions):

```bash
forge test                                  # full suite
forge test --match-path 'test/scenarios/*'  # just the 8 acceptance scenarios
forge test --match-contract S4 -vvv         # one scenario, with traces
forge test --match-contract InvariantTest   # value-conservation fuzz (200 runs)
```

Expected: `36 passed; 0 failed`.

---

## Prerequisites & setup

[Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil, cast):

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

Then, from the project root:

```bash
forge install   # vendors forge-std + OpenZeppelin v5 into lib/ (only needed once)
forge build
```

---

## Architecture

Two production contracts (ADR 001) — **Vault holds state; Custody holds tokens**:

```
        Users / Admin
             │  (public functions only)
             ▼
      ┌──────────────┐     controls (onlyVault)     ┌──────────────┐
      │   Vault.sol  │ ───────────────────────────▶ │  Custody.sol │
      │  state machine, queues,                      │  holds wRWA, │
      │  matching, shares (ERC-20),                  │  liquid, USDC│
      │  processEpoch, wind-down                     │              │
      └──────────────┘                               └──────┬───────┘
                                                            │ external calls
                                  ┌──────────────┬──────────┼───────────┐
                                  ▼              ▼          ▼           ▼
                              MockUSDC       MockPruv  MockLiquidBuffer MockAMM
                              (stable)       (fund)    (liquid sleeve)  (1:1 swap)
```

| Path | Contents |
|------|----------|
| `src/Vault.sol` | Lifecycle state machine, sub/redeem queues, P2P matching, 3-layer redemption, wind-down, ERC-20 shares |
| `src/Custody.sol` | Token holder + fund/AMM interactions; `onlyVault`-gated |
| `src/interfaces/` | `IVault`, `ICustody` |
| `src/mocks/` | `MockUSDC`, `MockPruv`, `MockLiquidBuffer`, `MockAMM` |
| `test/` | Unit tests (`Vault.t.sol`, `Custody.t.sol`, `Mocks.t.sol`), `Invariant.t.sol`, and `scenarios/S1..S8` |
| `script/Demo.s.sol` | The parameterised, manager-facing demo |
| `docs/` | Requirements, architecture (ADR + diagrams), tech stack, spec, estimation |

**State machine** (transitions are one-way):

```
Initialized → LaunchpadStart → ┬→ EpochBased → WindDown → Closed
                               └→ LaunchpadFail
```

### A note on units

Internally: USDC / wRWA / liquid are **6-decimal**; vault shares are **18-decimal**; price and NAV
are `1e18`-scaled. The demo and tests present everything in plain units (USDC, shares, `1.08` NAV).
Details and the rationale are in [`CLAUDE.md`](CLAUDE.md).

---

## Scope (locked)

**In:** 5-state lifecycle · async queues · ERC-7887 cancel · P2P matching (both cases) · 3-layer
redemption · rebalance-toward-target asset mix · manual NAV · full wind-down · 8 scenarios.

**Out (deferred, re-estimate before pulling in):** UI · cross-chain bridge · Aave reinvest · real
Curve formula · real Pruv API · role-based access · NAV oracle · full ERC-4626 · gas optimisation ·
audit · mainnet/testnet deploy · fee model.
