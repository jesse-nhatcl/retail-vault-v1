# REX Primary — Jira Task List (Epic / Task / Sub-task)

> Ready-to-create Jira issues. Hierarchy: **Epic → Task (2–4 per epic) → Sub-task**. Source: `docs/09-rex-primary-production-plan.md`.
> Assumed project key: `REX`.
>
> ⚠️ **Pending David's confirmation** on Matching (do retail hold real wRWA, or does REX mint its own vault token?).
> Sub-tasks depending on that decision are marked **TBD** + 🔒. Sub-tasks awaiting research are **TBD** + ⏳.
> **Legend:** ⭐ do first · 🔒 blocked on David · ⏳ blocked on research.

---

## EPIC E0 — Research & Platform Validation
*Validate Pruv + Hyperlane + oracle with docs and runnable scripts before design.*

- **T0.1 — Research Pruv Finance**
  - Sub: extract `RWAToken`/`RWAConversion`/`RWAFee`/`Whitelist` interfaces + function table → `docs/research/pruv-interface.md`
  - Sub: test deposit/redeem on PRUV Testnet (whitelisted wallet), log txs, reconcile against `previewDeposit/Redeem`
  - Sub: Whitelist onboarding process for the Executor (+ one test address granted token ID 1)
  - Sub: NAV — who calls `setValue`, cadence, proposed staleness threshold
  - Sub: Fee — script reading live `feeOnRaw/feeOnTotal` + bps/recipient/timing
- **T0.2 — Research Hyperlane Bridge**
  - Sub: collateral↔synthetic mechanics, `transferRemote`, fee quoting, ISM
  - Sub: USDC round-trip bridge script on testnet + latency measurement + failure modes/recovery
  - Sub: wRWA warp route to Sepolia — reuse or deploy? (conclusion)
- **T0.3 — Research Oracle + Compliance + Decimals**
  - Sub: compare oracle options (self-signed relay / Hyperlane message / Chainlink) → ADR (default: Hyperlane message) + threat note
  - Sub: light compliance — confirm "Executor KYC, retail no-KYC" model + legal red flags
  - Sub: decimal reconciliation — read on-chain `decimals()`, build canonical table

## EPIC E1 — Architecture & Design (produces docs)
*Understand the async cross-chain flow before coding.*

- **T1.1 — Diagrams (sequence + architecture)** ⭐
  - Sub: sequence — subscribe / redeem / matching / launchpad / wind-down
  - Sub: sequence — bridge failure + retry, oracle NAV update
  - Sub: multi-chain architecture diagram (Sepolia ↔ Hyperlane ↔ PRUV) + trust boundaries
  - Sub: render `.mmd` → `.png`, team review
- **T1.2 — State machine + message spec**
  - Sub: extended state machine (in-flight/settling) + transition table + double-process/timeout guards
  - Sub: cross-chain message spec (sub/redeem-delta, return-wRWA/USDC) + idempotency/ordering/replay/versioning
  - Sub: list invariants held while in-flight
- **T1.3 — Production spec + PRD reconciliation**
  - Sub: write `docs/spec/rex-primary.md` grounded in PRD (receipt 7540/7887, distribution)
  - Sub: "Assumptions & PRD reconciliation" section (settle §Matching)
  - Sub: 🔒 matching math (share vs raw token) *(blocked on David)*

## EPIC E2 — Home-chain Contracts (Sepolia)
*⚠️ Several tasks depend on David's matching decision.*

- **T2.1 — Core: state machine + queues + receipt/cancel**
  - Sub: 5 states + transitions + unit tests
  - Sub: subscription queue + redemption queue
  - Sub: `requestDeposit`/`requestRedeem` issue receipt (7540)
  - Sub: `cancelRequest` before window + refund assets/USDC + cancel-fee hook
- **T2.2 — Matching + distribution** 🔒
  - Sub: net USDC-sub vs wRWA-redeem at NAV; test the 10k/4k numbers per PRD
  - Sub: 🔒 matched-settlement mechanism (raw token transfer vs mint/burn share) *(blocked on David)*
  - Sub: 🔒 subscriber distribution (wRWA vs share) *(blocked on David)*
  - Sub: redeemer USDC distribution at NAV
- **T2.3 — Async epoch + bridge adapters**
  - Sub: `initiateEpoch` (compute delta + send bridge) / `settleEpoch` (receive + distribute)
  - Sub: prevent double-settle + assert `assets ≥ obligations` throughout in-flight
  - Sub: `IBridge` adapter (USDC + wRWA, out/in) idempotent by message id + fee handling
- **T2.4 — Launchpad + wind-down + fee + access control**
  - Sub: Launchpad (gather USDC to min ticket; success→subscribe&distribute; fail→100% refund)
  - Sub: Wind-down (disable subs, refund pending, redeem wRWA at Pruv); 🔒 force-redeem retail-held wRWA or not *(blocked on David)*
  - Sub: FeeModule (cancel + redeem, configurable bps, recipient, preview no-hidden-fee)
  - Sub: access control + pausable + `nonReentrant` (claim/refund/settle)

## EPIC E3 — Pruv-chain Contract (PruvExecutor)

- **T3.1 — Executor deposit/redeem + whitelist + fee**
  - Sub: receive bridged USDC → `RWAToken.deposit` → bridge wRWA back
  - Sub: receive bridged wRWA → `RWAToken.redeem` → bridge USDC back; only accept valid bridge messages
  - Sub: hold Whitelist token ID 1 + revert when not/no-longer whitelisted
  - Sub: account for Pruv fee (`RWAFee`) — returned amounts match real preview
- **T3.2 — Recovery/sweep on bridge failure**
  - Sub: admin recover stuck funds
  - Sub: relay-fail test

## EPIC E4 — Bridge Integration (Hyperlane)

- **T4.1 — Warp routes (USDC + wRWA)**
  - Sub: USDC route Sepolia↔PRUV — config/deploy + bidirectional enroll + round-trip test
  - Sub: ⏳ wRWA route PRUV↔Sepolia — reuse/deploy per T0.2 conclusion + synthetic-mint test
- **T4.2 — Fee/monitoring + failure recovery**
  - Sub: fee quoting before send + delivery tracking by message id
  - Sub: message-fail → retry + stuck recovery (no double-mint/double-pay)

## EPIC E5 — Oracle & Off-chain Services
*Merges Oracle NAV + Keeper + Backend/Indexer/API + Monitoring.*

- **T5.1 — Oracle NAV (contracts + relay + integration)**
  - Sub: `NavOracleConsumer` (Sepolia) — store NAV+timestamp, staleness guard, sanity bound
  - Sub: `NavReporter` (PRUV) reads `value()` + dispatches via Hyperlane; consumer only accepts valid sender/domain + replay protection
  - Sub: integrate NAV into matching/settle; test NAV +10% → redeemer receives 10% more
- **T5.2 — Epoch Keeper**
  - Sub: initiate epoch → track bridge delivery → trigger settle
  - Sub: full async epoch end-to-end test on testnet
- **T5.3 — Backend: Indexer + API**
  - Sub: indexer for request/receipt/epoch + cross-chain status (queued/in-flight/claimable)
  - Sub: API for UI — NAV/preview/fee + history + launchpad status
- **T5.4 — Monitoring + ops/keys**
  - Sub: bridge/relay monitor + alerting (delayed/stuck messages)
  - Sub: relay/keeper key management (no hardcoding) + rotation

## EPIC E6 — Frontend / dApp

- **T6.1 — Subscribe/Redeem/Claim UI**
  - Sub: subscribe/redeem form + NAV/preview/fee display
  - Sub: in-flight status (bridging) + full flow test on testnet
- **T6.2 — Launchpad + Wind-down UI**
  - Sub: Launchpad (countdown, min ticket, refund on fail)
  - Sub: Wind-down (settling obligations) + transaction history + claim

## EPIC E7 — Testing & QA

- **T7.1 — Unit + integration tests**
  - Sub: unit tests for contracts (Sepolia + PRUV) hitting coverage target
  - Sub: cross-chain integration (mock bridge + mock Pruv) — async subscribe/redeem, matching 10k/4k exact
- **T7.2 — Testnet E2E + invariant/fuzz**
  - Sub: E2E script — deposit USDC on Sepolia → receive wRWA (real bridge+Pruv) → redeem → USDC, log txs on both chains
  - Sub: invariant/fuzz — value conservation, no stranded cross-chain funds, no double-distribute

## EPIC E8 — Security & Audit

- **T8.1 — Threat model + internal review**
  - Sub: cross-chain threat model (bridge trust/replay/reorg/NAV manipulation/ordering) + mitigations
  - Sub: static analysis (slither on both chains) + review checklist
- **T8.2 — External audit**
  - Sub: select auditor + scope
  - Sub: fix findings

## EPIC E9 — Deployment & Ops

- **T9.1 — Deploy + admin/upgradeability**
  - Sub: deploy scripts Sepolia + PRUV + explorer verification
  - Sub: admin key/multisig + proxy/upgradeability model
- **T9.2 — Monitoring + runbooks**
  - Sub: dashboard epoch/bridge/NAV/TVL/in-flight + alerts
  - Sub: runbooks (stuck bridge / stale NAV / wind-down / grant-revoke Executor whitelist)

---

## TBD Summary (blockers to clear)

| Task | TBD sub-task | Blocked by |
|---|---|---|
| 🔒 T1.3 | matching math (share vs token) | David — Matching |
| 🔒 T2.2 | matched-settlement mechanism + subscriber distribution | David — Matching |
| 🔒 T2.4 | wind-down force-redeem retail wRWA or not | David / D-phase |
| ⏳ T0.2 / T4.1 | reuse/deploy wRWA warp route | research T0.2 conclusion |

**Total:** 9 epics · 26 tasks · detailed sub-tasks. 2–4 tasks per epic.
