# REX Primary — Architecture

Cross-chain, asynchronous, custody-free. This document is the shape of the system; `../specs/spec.md` is the
exact behavior.

---

## 1. Topology

```
        HOME CHAIN (Sepolia, EVM)                     FUND CHAIN (PRUV, domain 7336)
   ┌───────────────────────────────┐            ┌───────────────────────────────────┐
   │  Retail (USDC in / wRWA held)  │            │  Pruv Finance (external, given):   │
   │            │                   │            │    RWAToken (ERC-4626)             │
   │            ▼                   │            │    RWAConversion (NAV)             │
   │      REXPrimary                │            │    RWAFee (entry/exit)             │
   │   state machine, queues,       │            │    Whitelist (ERC-1155, id 1)     │
   │   matching, receipts,          │            │            ▲                      │
   │   initiate/settle, distribute  │            │            │ deposit / redeem     │
   │      │            ▲            │            │      PruvExecutor  (KYC'd)        │
   │      │            │ nav()      │            │      (holds Whitelist id 1)       │
   │      ▼        NavOracleConsumer│            │            ▲                      │
   │  FeeModule    (staleness+sanity)            │       NavReporter (reads value()) │
   └──────┬───────────────▲────────┘            └──────┬──────────────────┬─────────┘
          │  USDC/wRWA     │  NAV msg                   │ USDC/wRWA        │ NAV msg
          ▼                │                            ▼                  │
   ┌──────────────────────┴────────────────────────────────────────────────┴────────┐
   │                          HYPERLANE (warp routes + messaging)                     │
   │   USDC warp route (home ↔ PRUV)   ·   wRWA warp route (PRUV ↔ home)   ·   ISM     │
   └──────────────────────────────────────────────────────────────────────────────────┘

   OFF-CHAIN:  Epoch Keeper (initiate → watch bridge → settle)  ·  Bridge Monitor  ·  Indexer/API
```

## 2. Components

### Home chain (Sepolia)

| Component | Responsibility | Notes |
|---|---|---|
| **REXPrimary** | The 5-state lifecycle, subscription + redemption queues, receipt issuance/cancel (7540/7887), matching at NAV, `initiateEpoch`/`settleEpoch`, distribution to claimers. | Holds no assets at rest; only in-flight during settlement. |
| **NavOracleConsumer** | Stores the latest relayed NAV with a timestamp; enforces staleness + sanity bounds; serves `nav()`. | Reverts `StalePrice` if too old. |
| **FeeModule** | Computes REX cancellation and redemption fees; holds recipient config. | All fees previewable. |
| **BridgeAdapter (IBridge)** | Sends USDC/wRWA out and receives the return; idempotent per message id. | Thin wrapper over Hyperlane warp routes. |

### Fund chain (PRUV)

| Component | Responsibility | Notes |
|---|---|---|
| **PruvExecutor** | The only KYC'd actor. Receives bridged USDC → `RWAToken.deposit`; receives bridged wRWA → `RWAToken.redeem`; bridges the result home. Recovery/sweep on failure. | Holds `Whitelist` token id 1. Accepts only enrolled-sender messages. |
| **NavReporter** | Reads `RWAConversion.value()` and dispatches it over Hyperlane to `NavOracleConsumer`. | Runs on a cadence driven by the keeper/relay. |

### External on PRUV (given by Pruv Finance)

`RWAToken` (ERC-4626: `deposit`/`redeem`/`preview*`/`convert*`/`asset`/`maxRedeem`), `RWAConversion`
(`value()`/`setValue()`, 18-dec), `RWAFee` (`feeOnRaw`/`feeOnTotal`, timing enum), `Whitelist`
(ERC-1155, `balanceOf(user, 1)`).

### Off-chain

| Service | Responsibility |
|---|---|
| **Epoch Keeper** | Triggers `initiateEpoch`, tracks bridge delivery by message id, triggers `settleEpoch`. Never settles before the return is confirmed. |
| **NAV relay** | Drives `NavReporter` dispatch on cadence (may be folded into the keeper). |
| **Bridge Monitor** | Watches for delayed/stuck messages; alerts; assists recovery. |
| **Indexer + API** | Serves request/receipt/epoch state and cross-chain status (queued / in-flight / claimable) to the UI. |

## 3. The bridge (Hyperlane warp routes)

Two tokens cross, both directions:

- **USDC**: home → PRUV (fund a subscription) and PRUV → home (return redemption proceeds).
- **wRWA**: PRUV → home (deliver subscribed units) and home → PRUV (send units to be redeemed).

A warp route locks the real token via `HypERC20Collateral` on one side and mints a `HypERC20`
synthetic on the other; `transferRemote(domain, recipient, amount)` moves value. The real wRWA lives
on PRUV; the home chain holds its synthetic. Whether an existing wRWA route reaches the home chain or
must be deployed is a Phase 0 research item.

**Trust root:** inbound messages are only acted on when the sender is enrolled and the origin domain
is expected, verified by Hyperlane's ISM. This applies to bridged tokens, settlement callbacks, and
NAV updates alike (Article 4).

## 4. NAV path (oracle)

NAV originates on PRUV (`RWAConversion.value()`). `NavReporter` dispatches it over Hyperlane to
`NavOracleConsumer` on the home chain, which stores value + timestamp and enforces:

- **Staleness**: reject/`revert StalePrice` if older than the configured window.
- **Sanity bound**: reject an update that moved more than the configured max since the last accepted
  value.

Default mechanism is **Hyperlane messaging** (reuse the bridge's security model, no second trust
vendor). Alternatives (self-signed relay, Chainlink/CCIP) are compared in
`../decisions/ADR-004-oracle-nav-hyperlane.md`.

## 5. The epoch as a distributed transaction

Because Pruv is on another chain, an epoch is a **two-phase, non-atomic** flow:

1. **initiate** (home): snapshot queues → matching at NAV → settle matched P2P → bridge the net
   delta out. Mark epoch **in-flight**.
2. **execute** (PRUV, async): `PruvExecutor` deposits/redeems at Pruv, bridges the result home.
3. **settle** (home): on arrival, distribute wRWA/USDC to claimers, advance the epoch.

The in-flight window is where all the cross-chain risk lives. The invariants in the constitution
(Articles 4, 5, 10) exist to make it safe: idempotency by message id, no double-settle, no stranded
funds, conservation across the bridge. Full state machine and callbacks are in `../specs/spec.md`; every flow
has a sequence diagram in `diagrams/`.

## 6. Trust boundaries

| Boundary | What is trusted | Guard |
|---|---|---|
| Retail → REXPrimary | Nothing | Validate inputs; permissionless but bounded (queue caps) |
| Bridge → REXPrimary / PruvExecutor | Only enrolled sender + expected domain | ISM + origin check + message-id idempotency |
| NavReporter → NavOracleConsumer | Only the enrolled reporter | Origin check + staleness + sanity bound |
| Admin/Keeper | Least privilege, multisig on mainnet | Role separation; keeper cannot move funds arbitrarily |
| Pruv contracts | Trusted external (audited third party) | Executor holds the only credential; failures have recovery paths |
