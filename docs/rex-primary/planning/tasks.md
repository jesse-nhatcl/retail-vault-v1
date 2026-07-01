# REX Primary — Task Breakdown (Jira-ready)

Epic → Task → Sub-task, aligned 1:1 with the phases in `dev-plan.md`. Assumed project key `REX`.
This supersedes the earlier draft an earlier draft in the repository root for the production effort.

> **Decisions applied:** no vault token, no custody, retail hold wRWA (matching = raw token
> transfer). Only genuinely research-dependent items remain open, marked ⏳. Each build task cites
> the acceptance scenario (RS#) from `../specs/spec.md` §15 that closes it.

**Legend:** ⭐ do first · ⏳ blocked on research · `RS#` acceptance scenario.

---

## EPIC E0 — Research & Validation `(Phase 0)`

- **T0.1 — Research Pruv Finance**
  - Sub: interface table for `RWAToken`/`RWAConversion`/`RWAFee`/`Whitelist` → `references/pruv-interface.md`
  - Sub: live deposit/redeem on PRUV testnet (whitelisted wallet), reconcile `previewDeposit/Redeem`
  - Sub: whitelist onboarding process (+ one test address granted token id 1)
  - Sub: NAV cadence + proposed `STALENESS_WINDOW`; `RWAFee` bps; confirm `d_w`
- **T0.2 — Research Hyperlane Bridge**
  - Sub: warp-route mechanics + fee quoting + ISM
  - Sub: USDC round-trip script (testnet) + latency + failure modes
  - Sub: ⏳ wRWA warp route to home chain — reuse existing or deploy? (conclusion)
- **T0.3 — Oracle + compliance + decimals**
  - Sub: oracle ADR (default Hyperlane messaging) + threat note
  - Sub: confirm "executor-only KYC, retail permissionless"
  - Sub: on-chain decimal table

## EPIC E1 — Architecture & Design `(Phase 1)`

- **T1.1 — Diagrams** ⭐ *(drafted in `../architecture/diagrams/`)*
  - Sub: re-validate subscribe/redeem/matching/launchpad/wind-down/bridge-failure/oracle against Phase 0 facts
- **T1.2 — State machine + message spec**
  - Sub: finalize in-flight states + transitions (`../specs/spec.md` §5)
  - Sub: finalize cross-chain message shapes + idempotency keys (`../specs/spec.md` §11)
- **T1.3 — Per-subsystem implementation plans**
  - Sub: author bite-sized TDD plans in `planning/plans/` for the walking-skeleton contracts (real signatures from Phase 0)

## EPIC E2 — Walking Skeleton `(Phase 2)` ⭐

- **T2.1 — Minimal `REXPrimary`**
  - Sub: `requestDeposit` (escrow USDC, receipt)
  - Sub: `initiateEpoch` (net-sub only, no matching yet) → bridge USDC
  - Sub: `settleEpoch` (distribute returned wRWA) + `claim`
- **T2.2 — Minimal `PruvExecutor`**
  - Sub: `onBridgedUsdc` → `RWAToken.deposit` → bridge wRWA home
  - Sub: hold `Whitelist` id 1 + reject unauthorized senders
- **T2.3 — Bridge adapter + oracle + keeper (skeleton)**
  - Sub: `IBridge` over USDC + wRWA warp routes (idempotent by message id)
  - Sub: `NavOracleConsumer` + `NavReporter` (fixed NAV path)
  - Sub: keeper: initiate → watch bridge → settle
  - *Exit:* deposit USDC home → receive wRWA after round-trip → claim, logged on both chains

## EPIC E3 — Matching + Redemption `(Phase 3)`

- **T3.1 — Matching engine** `RS4, RS5`
  - Sub: net USDC-sub vs wRWA-redeem at NAV (`../specs/spec.md` §8)
  - Sub: P2P matched settlement = **raw token transfer** (no mint/burn)
  - Sub: net-delta both directions; assert exact 10k/4k numbers
- **T3.2 — Redemption path**
  - Sub: `requestRedeem` (escrow wRWA, receipt)
  - Sub: async redeem round-trip (bridge wRWA → Pruv redeem → USDC home → distribute)
- **T3.3 — Cancel (ERC-7887)** `RS3, RS6`
  - Sub: `cancelRequest` before initiate (refund USDC less cancel fee / wRWA)
  - Sub: async settlement across the in-flight window; no second epoch initiates meanwhile

## EPIC E4 — Lifecycle Breadth `(Phase 4)`

- **T4.1 — Launchpad** `RS1, RS2`
  - Sub: `depositToLaunchpad` + receipt
  - Sub: `closeLaunchpad` success → subscribe & distribute wRWA
  - Sub: fail → `refundLaunchpad` 100%
- **T4.2 — Wind-down** `RS9`
  - Sub: disable subs + refund pending
  - Sub: settle redemption queue via Pruv; retail-held wRWA untouched → `Closed`
- **T4.3 — FeeModule**
  - Sub: cancellation + redemption fees, configurable, previewable
  - Sub: Pruv entry/exit fee borne only by the net delta

## EPIC E5 — Hardening the In-flight Window `(Phase 5)`

- **T5.1 — Oracle guards** `RS7`
  - Sub: staleness guard blocks settlement on stale NAV
  - Sub: sanity bound rejects abnormal NAV moves; NAV +10% → redeemers paid 10% more
- **T5.2 — Bridge failure/recovery** `RS8`
  - Sub: stuck leg does not settle; retry recovers
  - Sub: `PruvExecutor.sweep`; no double-mint/double-pay
- **T5.3 — Invariant/fuzz**
  - Sub: conservation, no stranded cross-chain funds, no double

## EPIC E6 — Off-chain Services + Frontend `(Phase 6)`

- **T6.1 — Indexer + API**
  - Sub: request/receipt/epoch + cross-chain status (queued/in-flight/claimable)
  - Sub: API for NAV/preview/fee + history + launchpad status
- **T6.2 — Monitoring + keeper hardening**
  - Sub: bridge/relay monitor + alerting
  - Sub: keeper/relay key management + rotation
- **T6.3 — dApp**
  - Sub: subscribe/redeem/claim with NAV/preview/fee + in-flight status
  - Sub: launchpad + wind-down UI; end-to-end via browser on testnet

## EPIC E7 — Security & Deployment `(Phase 7)`

- **T7.1 — Threat model + review**
  - Sub: cross-chain threat model (bridge trust/replay/reorg/NAV manipulation/ordering) + mitigations
  - Sub: static analysis (both chains) + review checklist
- **T7.2 — External audit**
  - Sub: select auditor + scope; fix findings
- **T7.3 — Deploy + Ops**
  - Sub: multi-chain deploy scripts + verification; multisig admin
  - Sub: dashboards + runbooks (stuck bridge / stale NAV / wind-down / whitelist ops)

---

## Open (research-dependent)

| Task | Item | Blocked by |
|---|---|---|
| ⏳ T0.2 / T2.3 | reuse vs deploy the wRWA warp route to the home chain | research T0.2 |
| ⏳ T0.1 | `d_w`, `STALENESS_WINDOW`, `MAX_NAV_MOVE_BPS`, `RWAFee` bps | Pruv testnet research |

**Total:** 8 epics (= 8 phases) · 24 tasks · sub-tasks aligned to `../specs/spec.md` acceptance scenarios.
