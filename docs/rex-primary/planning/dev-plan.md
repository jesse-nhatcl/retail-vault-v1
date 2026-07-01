# REX Primary — Development Plan

> **For agentic workers:** This is a **phased roadmap**, not a single bite-sized implementation
> plan. REX Primary spans multiple independent subsystems (home-chain contracts, PRUV-chain
> executor, bridge, oracle, off-chain services, frontend). Per `superpowers:writing-plans`, each
> subsystem gets its **own** detailed, task-by-task, TDD implementation plan authored **after Phase
> 0 research** resolves its interface unknowns (writing a bite-sized plan now would be all
> placeholders, which the skill forbids). This document sequences those subsystems, defines the
> gates between them, and pins the walking skeleton.

**Goal:** Ship REX Primary to testnet: permissionless retail group subscription/redemption for
Pruv's private-credit fund, epoch-matched, settled cross-chain, custody-free.

**Architecture:** Home chain (Sepolia) `REXPrimary` + `NavOracleConsumer` + `FeeModule`; PRUV chain
`PruvExecutor` + `NavReporter`; Hyperlane warp routes (USDC + wRWA) and messaging; off-chain keeper,
relay, monitor, indexer; a thin dApp. Async two-phase epoch (initiate → bridge → settle).

**Tech stack:** Solidity 0.8.x (Foundry), Hyperlane warp routes + mailbox, Pruv ERC-4626 on PRUV, a
TypeScript keeper/indexer, and a web dApp.

---

## Principles for this plan

- **Walking skeleton first.** Prove one subscribe request settling across both chains end-to-end
  before adding breadth. Everything else hangs off a working async round-trip.
- **Research before interfaces.** Phase 0 turns every `(confirm T0.x)` in `../specs/spec.md` into a fact.
  Only then are subsystem implementation plans written.
- **TDD, exact-number acceptance, cross-chain integration** per the constitution (Article 11).
- **Gates are binding.** A phase does not start until its predecessors meet their exit criteria.

## Team shape (3 people: 1 FE + 2 Core)

- **Core-1**: home-chain contracts (`REXPrimary`, `FeeModule`) + matching + settlement.
- **Core-2**: `PruvExecutor`, bridge integration, oracle (`NavReporter`/`NavOracleConsumer`),
  off-chain keeper/monitor.
- **FE**: after Phase 1, the indexer/API then the dApp; reviews design docs early to internalize the
  flow.

---

## Phase 0 — Research & Validation `[gate: every (confirm T0.x) in ../specs/spec.md is answered]`

Owner: Core. Output: docs under `references/` **and runnable scripts** proving each platform.

- **T0.1 Pruv Finance**: interface table; live deposit/redeem on PRUV testnet with a whitelisted
  wallet; NAV cadence; `RWAFee` rates; whitelist onboarding process; confirm `d_w`.
- **T0.2 Hyperlane**: warp-route mechanics; USDC round-trip script + latency + failure modes;
  decide reuse-vs-deploy for the **wRWA** route to the home chain.
- **T0.3 Oracle + compliance + decimals**: oracle ADR (default Hyperlane messaging); confirm
  "executor-only KYC, retail permissionless"; on-chain decimal table.

**Exit:** `../specs/spec.md` §16 fully resolved; a whitelisted address exists; USDC bridges round-trip.

## Phase 1 — Architecture & Design `[gate: team can draw the async flow from memory]`

Owner: Core (FE reviews). Output: the diagrams and specs in this folder, finalized against Phase 0
facts.

- **T1.1 Diagrams** (done, in `../architecture/diagrams/`): subscribe, redeem, matching, launchpad, wind-down,
  bridge-failure, oracle. Re-validate against Phase 0.
- **T1.2 State machine + cross-chain message spec** (`../specs/spec.md` §5, §11): finalize in-flight states,
  message shapes, idempotency keys.
- **T1.3 Per-subsystem implementation plans**: author `planning/plans/` bite-sized TDD plans
  for the walking-skeleton subsystems (below), now that interfaces are known.

**Exit:** implementation plans exist for the walking-skeleton contracts with real (not placeholder)
signatures.

## Phase 2 — Walking skeleton `[gate: one subscribe request settles across both chains on testnet]`

The thinnest end-to-end slice. No launchpad, no fees, no UI. Owner: Core-1 + Core-2.

- Minimal `REXPrimary`: `requestDeposit`, `initiateEpoch` (net-sub only, no matching yet),
  `settleEpoch`, `claim`.
- Minimal `PruvExecutor`: `onBridgedUsdc` → `RWAToken.deposit` → bridge wRWA home.
- `IBridge` adapter over the USDC + wRWA warp routes.
- `NavOracleConsumer` + `NavReporter` (fixed NAV path).
- Keeper: initiate → watch bridge → settle.

**Exit:** deposit USDC on the home chain → receive wRWA after the async round-trip → `claim`, logged
on both chains. Value conserved.

## Phase 3 — Matching + redemption `[gate: RS4, RS5, RS6 pass]`

- Matching engine at NAV (`../specs/spec.md` §8), P2P raw-transfer settlement, net-delta both directions.
- `requestRedeem`, redeem settlement, `cancelRequest` (7887).
- Async redemption round-trip (bridge wRWA → Pruv redeem → USDC home).

**Exit:** matching acceptance scenarios pass with exact numbers; cancel works before initiate.

## Phase 4 — Lifecycle breadth `[gate: RS1, RS2, RS9 pass]`

- Launchpad (gather, close success/fail, claim, refund).
- Wind-down.
- `FeeModule` (cancellation + redemption fees; previewable); Pruv fee accounting on the delta only.

**Exit:** full lifecycle from launchpad to wind-down settles with nobody stranded.

## Phase 5 — Hardening the in-flight window `[gate: RS7, RS8 pass; invariants fuzzed]`

- Oracle staleness + sanity bounds wired into settlement (RS7).
- Bridge failure/retry/recovery + `sweep` (RS8).
- Invariant/fuzz: conservation, no stranded funds, no double.

**Exit:** the async window is safe under injected failures; fuzz clean.

## Phase 6 — Off-chain services + Frontend `[gate: a user completes the flow in a browser on testnet]`

- Indexer + API (queued / in-flight / claimable status).
- Bridge monitor + alerting; keeper hardening + key management.
- dApp: subscribe/redeem/claim with NAV/preview/fee and in-flight status; launchpad + wind-down UI.

**Exit:** end-to-end via UI on testnet.

## Phase 7 — Security & Deployment `[gate: audit findings resolved; testnet E2E green]`

- Threat model (cross-chain), static analysis, external audit, fixes.
- Multi-chain deploy scripts + verification; multisig admin; monitoring/dashboards; runbooks.

**Exit:** audited, deployed to testnet with ops in place; mainnet is a separate go/no-go.

---

## Critical path

`T0.2 (bridge feasible?) → T0.1 (Pruv interface) → T1.3 (skeleton plans) → Phase 2 (async
round-trip) → Phase 3 (matching)`. Everything else (launchpad, wind-down, fees, UI) parallelizes
once the skeleton proves the async loop. **Do not** build breadth before the skeleton settles on
testnet.

## Handoff to implementation

Detailed task-by-task TDD plans are authored per subsystem in Phase 1 (T1.3) and executed via
`superpowers:subagent-driven-development` (fresh subagent per task, spec-compliance then
code-quality review) or `superpowers:executing-plans`. The Jira breakdown in `tasks.md` mirrors this
roadmap for ticketing.
