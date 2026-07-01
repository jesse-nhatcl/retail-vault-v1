# REX Primary — Off-chain Services Specification

The behavior of the off-chain services: **Epoch Keeper**, **NAV Relay**, **Bridge Monitor**, and
**Indexer + API**. These make the async cross-chain epoch actually run and give the UI something to
read. Contracts are in `spec.md`; this document is the services layer.

> **Status honesty (answers "is BE documented, or do we need to discuss?"):** the services'
> **responsibilities and behavior are specified below** (derived from the settled architecture). The
> **tech/infra choices are open** and need a short discussion - see "Open questions" first. Nothing
> here is blocked; the open items are how-we-run-it decisions, not what-it-does decisions.

---

## Open questions (need a decision before Phase 6 build)

| # | Question | Options | Default proposal |
|---|---|---|---|
| Q1 | Keeper trigger authority | permissionless (anyone can call initiate/settle) vs keeper-role only | **keeper-role**, with a permissionless fallback after a timeout so the system cannot stall |
| Q2 | Keeper/relay infra | cron VM · serverless · a keeper network (Gelato/Chainlink Automation) | **cron VM** for testnet, revisit for mainnet |
| Q3 | Indexer tech | custom event indexer · a subgraph · a hosted indexer | **custom** (two chains + cross-chain correlation is awkward for a single subgraph) |
| Q4 | API protocol | REST · GraphQL | **REST** (small, well-defined surface) |
| Q5 | Key custody for keeper/relay | env-injected key · KMS · multisig-gated | **KMS** on any hosted env; never a raw key in code (constitution Article 9) |

Resolve Q1-Q5 in a 30-minute session; they do not change the behavior specified below.

---

## 1. Epoch Keeper

**Responsibility:** drive the two-phase epoch. It **coordinates**; it never holds or moves user
funds (constitution Article 9.3).

**Loop (per epoch):**

1. **Preconditions:** state is `EpochBased`; `EpochStatus == Collecting`; NAV is fresh (see NAV
   Relay). If NAV is stale, refresh it first (do not initiate on stale NAV).
2. **Initiate:** call `initiateEpoch()` when the epoch trigger fires (time-based per the configured
   epoch period, or a manual admin trigger). Record the epoch id and the outbound bridge message id.
3. **Watch:** poll the bridge for delivery of the outbound leg to `PruvExecutor`, then for the
   return leg back to the home chain (by message id). Do **not** settle before the return is
   confirmed on-chain.
4. **Settle:** once `returnReceived` is true, call `settleEpoch()`.
5. **Idle:** wait for the next epoch trigger.

**Failure handling:** if a leg does not deliver within the expected window, do **not** settle; raise
an alert (Bridge Monitor), attempt a delivery retry, and escalate to admin `sweep` if unrecoverable
(`spec.md` §11). The keeper is safe to restart at any point: it derives its next action from
on-chain epoch state, holding no critical local state.

## 2. NAV Relay

**Responsibility:** keep the home-chain `NavOracleConsumer` fresh with Pruv's NAV.

**Loop:** on a cadence tied to Pruv's NAV update frequency (from Phase 0 research, T0.1): trigger
`NavReporter` on PRUV to read `RWAConversion.value()` and dispatch it over Hyperlane to
`NavOracleConsumer`. The on-chain consumer enforces the staleness window and sanity bound; the relay
just keeps it current.

**Coupling to the keeper:** the keeper must not initiate an epoch on a stale NAV. In practice the
relay runs slightly ahead of each epoch trigger so NAV is fresh at initiate. (May be folded into the
keeper process; still two logical jobs.)

## 3. Bridge Monitor

**Responsibility:** observe every cross-chain message REX depends on and alert on trouble.

**Watches:** outbound Pruv legs, return legs, and NAV dispatches, keyed by message id. **Alerts on:**
a message undelivered past its expected latency; a relay/ISM error; an epoch stuck `Initiated` beyond
a threshold; NAV staleness approaching the window. **Feeds** the runbooks (`dev-plan` Phase 7 /
`../planning/tasks.md` T7.3) for stuck-bridge and stale-NAV incidents.

## 4. Indexer + API

**Responsibility:** turn on-chain events (both chains) into a queryable view for the UI. Read-only;
never a trusted source for settlement (the chain is).

**Indexes:** `Requested`, `Cancelled`, `EpochInitiated`, `MatchingPerformed`, `NetSubBridged` /
`NetRedeemBridged`, `BridgeReturnReceived`, `EpochSettled`, `Claimed`, `NavUpdated`,
`LaunchpadDeposited`, `LaunchpadClosed`, `Refunded`, `WindDownTriggered`, `Closed` (event list in
`spec.md` §13), plus the correlated bridge message status.

**Derived per-request status** (the key value for the UI):

| Status | Meaning |
|---|---|
| `queued` | request created, its epoch not yet initiated (cancellable) |
| `in-flight` | its epoch is `Initiated`, bridging in progress |
| `claimable` | its epoch is `Settled`, payout ready to `claim` |
| `claimed` | claimed |
| `cancelled` / `refunded` | withdrawn or refunded |

**API surface (REST, indicative):**

```
GET /nav                         -> { value, updatedAt, stale: bool }
GET /epoch/current               -> { epochId, status, navAtInitiate? }
GET /requests/:address           -> [ { requestId, kind, amount, status, payout? } ]
GET /request/:id                 -> full request + bridge message status
GET /preview/subscribe?usdc=     -> { wrwaOut, fee }        // mirrors on-chain previewSubscribe
GET /preview/redeem?wrwa=        -> { usdcOut, fee }        // mirrors on-chain previewRedeem
GET /launchpad                   -> { total, minimum, closesAt, state }
```

Previews must match the on-chain `preview*` functions exactly (constitution Article 8: no hidden
fees; the UI shows what the chain will do).

## 5. Non-goals

The services **coordinate and report**; they are never a source of truth or a custodian. All
authority (funds, settlement, NAV acceptance) is on-chain. A compromised keeper/relay can stall or
misreport, but cannot steal or double-pay - the contracts' guards (idempotency, origin checks,
staleness/sanity, single-in-flight) hold regardless.
