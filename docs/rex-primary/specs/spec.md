# REX Primary — Production Specification

The source of truth for **behavior**. Grounded in the PRD; resolves the PRD's open points via the
ADRs in `../decisions/`. Working assumption throughout: **no vault token, no custody** (retail hold the
bridged wRWA; REX issues claim receipts). Where a value depends on Phase 0 research it is marked
`(confirm T0.x)` - that is a known unknown, not a placeholder to invent.

---

## 1. Scope

In: the 5-state lifecycle, launchpad, permissionless async subscription and redemption with
cancellable receipts, epoch matching at oracle NAV, cross-chain settlement via Hyperlane and a
whitelisted `PruvExecutor`, REX fees, wind-down. Out: any REX-issued share, any home-chain custody
of assets at rest, instant (non-epoch) exit, secondary trading of receipts.

## 2. Actors


| Actor            | Chain     | Trust                                                                        |
| ---------------- | --------- | ---------------------------------------------------------------------------- |
| Retail           | home      | untrusted, permissionless, bounded by queue caps                             |
| Admin (multisig) | both      | trusted for lifecycle transitions and config                                 |
| Keeper           | off-chain | may trigger `initiateEpoch`/`settleEpoch`; **cannot** move funds arbitrarily |
| Relay            | off-chain | drives NAV dispatch; message still verified on-chain                         |
| PruvExecutor     | PRUV      | REX-controlled, sole holder of Pruv `Whitelist` id 1                         |
| Pruv contracts   | PRUV      | trusted external                                                             |


## 3. Contracts and interfaces

### 3.0 Standards (locked - see ADR-006)

| Standard | Applies to | REX relationship |
|---|---|---|
| **ERC-4626** | Pruv `RWAToken` (external, PRUV) | Consumed via `PruvExecutor.deposit/redeem`. REX is **not** a 4626 vault. |
| **ERC-7540** | REX request lifecycle | Borrows the async **request pattern** (`requestDeposit`/`requestRedeem` → claim); **not** compliant, because it issues **no share token**. |
| **ERC-7887** | REX pending requests | Cancellable before the epoch initiates. |
| **ERC-20** | wRWA (Hyperlane `HypERC20` synthetic), USDC | Standard tokens; wRWA is the retail-held asset. |

The **receipt** is a non-transferable claim record (`requestId → owner`), not a share and not a
4626/7540 unit. Making it transferable (ERC-721) is a change requiring an ADR update. REX implements
neither ERC-4626 views nor full ERC-7540 share accounting. See `../decisions/ADR-006-token-standards.md`.

### 3.1 `REXPrimary` (home)

```
// Lifecycle
function startLaunchpad() external onlyAdmin;                 // Initialized -> LaunchpadStart
function closeLaunchpad() external;                           // -> EpochBased or LaunchpadFail
function triggerWindDown() external onlyAdmin;                // EpochBased -> WindDown

// Launchpad
function depositToLaunchpad(uint256 usdc) external returns (uint256 receiptId);
function claimLaunchpad(uint256 receiptId) external;          // after success: pay wRWA
function refundLaunchpad(uint256 receiptId) external;         // after fail: refund USDC

// Epoch-based requests (ERC-7540 request pattern, no shares)
function requestDeposit(uint256 usdc) external returns (uint256 requestId);
function requestRedeem(uint256 wrwa) external returns (uint256 requestId);
function cancelRequest(uint256 requestId) external;           // ERC-7887, before initiate
function claim(uint256 requestId) external;                   // after settle

// Epoch settlement (two-phase, async)
function initiateEpoch() external;                            // keeper/admin
function settleEpoch() external;                              // keeper/admin, after bridge return

// Views
function nav() external view returns (uint256);               // proxies NavOracleConsumer
function state() external view returns (State);
function epochStatus() external view returns (EpochStatus);
function previewSubscribe(uint256 usdc) external view returns (uint256 wrwaOut, uint256 fee);
function previewRedeem(uint256 wrwa) external view returns (uint256 usdcOut, uint256 fee);
```

### 3.2 `PruvExecutor` (PRUV)

```
function onBridgedUsdc(uint256 epochId, uint256 usdc) external onlyBridge;   // -> RWAToken.deposit -> bridge wRWA home
function onBridgedWrwa(uint256 epochId, uint256 wrwa) external onlyBridge;   // -> RWAToken.redeem  -> bridge USDC home
function sweep(address token, address to) external onlyAdmin;                 // recovery only
```

### 3.3 `NavOracleConsumer` (home)

```
function nav() external view returns (uint256);              // reverts StalePrice if too old
function lastUpdated() external view returns (uint64);
function setNav(uint256 value) external onlyReporterViaBridge;  // sanity-bound + staleness stamp
```

### 3.4 `IBridge` (home + PRUV adapters)

```
function sendToken(uint32 dstDomain, address token, uint256 amount, bytes calldata payload)
    external payable returns (bytes32 messageId);
// inbound handled by the messaging layer; each handler is idempotent per messageId
```

## 4. Tokens and decimals


| Quantity                      | Decimals                                           |
| ----------------------------- | -------------------------------------------------- |
| USDC                          | 6                                                  |
| wRWA (bridged synthetic)      | `d_w` - **confirm T0.x**; reference bridge shows 6 |
| NAV (`RWAConversion.value()`) | 18, parity = `1e18`                                |


All cross-decimal multiply-then-divide uses `Math.mulDiv`. Worked examples below use `d_w = 6` and
NAV parity `1e18`. Core relations:

```
redeemValueUSDC = mulDiv(wrwa, nav, 1e18)      // wRWA (6) -> USDC (6)
wrwaForUSDC     = mulDiv(usdc, 1e18, nav)       // USDC (6) -> wRWA (6)
```

## 5. State machine

```
Initialized ──startLaunchpad──▶ LaunchpadStart ──closeLaunchpad──┬─(≥min)─▶ EpochBased ──triggerWindDown──▶ WindDown ──▶ Closed
                                                                 └─(<min)─▶ LaunchpadFail (terminal)
```

`EpochBased` has an orthogonal **EpochStatus**: `Collecting → Initiated (in-flight) → Settled`
(then back to `Collecting` for the next epoch). At most **one** epoch is `Initiated` at a time
(constitution Article 5.2): `initiateEpoch()` reverts `EpochInFlight` if the previous epoch has not
settled.

Requests arriving while an epoch is `Initiated` accumulate into the next `Collecting` epoch.

## 6. Data model

```
struct Request {
    address owner;
    RequestKind kind;     // Subscribe | Redeem
    uint256 amount;       // USDC (subscribe) or wRWA (redeem)
    uint64  epochId;      // the epoch that will process it
    bool    cancelled;
    bool    claimed;
    uint256 payout;       // set at settle: wRWA (subscribe) or USDC (redeem)
}

struct Epoch {
    EpochStatus status;
    uint256 navAtInitiate;
    uint256 matchedUSDC;
    uint256 matchedWRWA;
    uint256 netSubUSDC;      // bridged out if > 0
    uint256 netRedeemWRWA;   // bridged out if > 0
    bytes32 outboundMsgId;   // idempotency key for the Pruv leg
    uint256 returnedAmount;  // wRWA or USDC received back
    bool    returnReceived;
}
```

Queue iteration is **capped at 100 requests per epoch** (gas safety). Cancelled requests remain in
the array and are skipped, never deleted or reindexed.

## 7. Flows

### 7.1 Launchpad

1. `depositToLaunchpad(usdc)` in `LaunchpadStart`: transfer USDC in, record a receipt. Cancellable
  until close.
2. After the launchpad window, `closeLaunchpad()`:
  - If total `≥ minimum`: transition to `EpochBased`; bridge the gathered USDC to `PruvExecutor`,
   deposit into Pruv, bridge wRWA home. Depositors `claimLaunchpad` for wRWA pro-rata to receipts.
  - If total `< minimum`: transition to `LaunchpadFail`; depositors `refundLaunchpad` for 100% USDC.

### 7.2 Subscribe (EpochBased)

1. `requestDeposit(usdc)`: transfer USDC into escrow, create a `Subscribe` request stamped with the
  current `Collecting` epoch, return `requestId` (the receipt).
2. Before that epoch initiates, `cancelRequest` refunds USDC minus the cancellation fee (§10).
3. At settle, the request's `payout` (wRWA) is set; `claim(requestId)` transfers it to the owner.

### 7.3 Redeem (EpochBased)

1. `requestRedeem(wrwa)`: transfer wRWA into escrow, create a `Redeem` request stamped with the
  current `Collecting` epoch.
2. Before initiate, `cancelRequest` refunds the wRWA (redeem cancel fee configurable, default 0).
3. At settle, the request's `payout` (USDC, net of redemption fee) is set; `claim` transfers it.

### 7.4 initiateEpoch (home)

Atomic on the home chain:

1. Snapshot the `Collecting` epoch's requests (skip cancelled), read `nav()` (reverts `StalePrice`
  if stale).
2. Compute matching (§8). Settle the **matched** portion peer-to-peer by assigning payouts:
  matched subscribers' `payout +=`  their share of `matchedWRWA`; matched redeemers'
   `payout +=`  their share of `matchedUSDC`. These are backed by the escrowed wRWA/USDC already in
   the contract - a **raw reassignment, no mint/burn**.
3. Compute the net delta. Exactly one branch:
  - `netSubUSDC > 0`: `bridge.sendToken(PRUV, USDC, netSubUSDC, epochId)` → record `outboundMsgId`.
  - `netRedeemWRWA > 0`: `bridge.sendToken(PRUV, wRWA, netRedeemWRWA, epochId)`.
  - exact match: no Pruv leg; the epoch can settle immediately (still emits events).
4. Set `EpochStatus = Initiated`. Emit `EpochInitiated`, `MatchingPerformed`, and the relevant
  `NetSubBridged`/`NetRedeemBridged`.

### 7.5 Execute (PRUV, async)

- `onBridgedUsdc(epochId, usdc)`: `RWAToken.deposit(usdc, executor)` → wRWA shares → bridge wRWA home
keyed to `epochId`.
- `onBridgedWrwa(epochId, wrwa)`: `RWAToken.redeem(wrwa, executor, executor)` → USDC → bridge USDC
home keyed to `epochId`.
- Both are `onlyBridge`, verify enrolled sender + expected domain, and are idempotent per `epochId`
(a replayed inbound message is a no-op).

### 7.6 settleEpoch (home)

1. Require `returnReceived == true` for the in-flight epoch (else revert `EpochNotInFlight`).
2. Distribute the returned amount to net subscribers (wRWA) or net redeemers (USDC) pro-rata,
  setting each request's `payout`.
3. Set `EpochStatus = Settled`, advance to the next `Collecting` epoch. Emit `EpochSettled`.
4. Users call `claim(requestId)` to withdraw their `payout`.

### 7.7 Wind-down

`triggerWindDown()` (admin, from `EpochBased`):

1. Disable new subscription requests.
2. Refund all pending (not-yet-initiated) subscription requests (USDC back).
3. Settle the pending redemption queue via the normal bridge → Pruv redeem → distribute path (a
  final epoch).
4. Retail-held wRWA is **untouched** (no custody to unwind); holders retain it and may redeem
  directly at Pruv, or through a final redemption window if one is configured.
5. Transition to `Closed` once the final redemption epoch settles.

## 8. Matching math (no vault token)

At `initiateEpoch`, with `nav` from the oracle:

```
subTotalUSDC     = Σ subscribe.amount           // 6-dec USDC
redeemTotalWRWA  = Σ redeem.amount              // d_w wRWA
redeemValueUSDC  = mulDiv(redeemTotalWRWA, nav, 1e18)

matchedUSDC = min(subTotalUSDC, redeemValueUSDC)
matchedWRWA = mulDiv(matchedUSDC, 1e18, nav)

// P2P settlement (raw transfer, no mint/burn):
//   each matched subscriber gets matchedWRWA * (their usdc / subTotalUSDC)
//   each matched redeemer  gets matchedUSDC * (their wrwa / redeemTotalWRWA-in-value)

netSubUSDC    = subTotalUSDC   - matchedUSDC          // > 0 when subs win
netRedeemWRWA = redeemTotalWRWA - matchedWRWA         // > 0 when redeems win
```

### Worked example RS4 - subscriptions win (PRD 10k / 4k, NAV = 1.0)

```
subTotalUSDC = 10,000 ; redeemTotalWRWA = 4,000 (worth 4,000 USDC @ 1.0)
matchedUSDC = 4,000 ; matchedWRWA = 4,000
P2P: redeemers -> subscribers 4,000 wRWA ; subscribers -> redeemers 4,000 USDC
netSubUSDC = 6,000 -> bridge to Pruv -> deposit -> ~6,000 wRWA back (less Pruv entry fee) -> subscribers
Outcome: subscribers ~10,000 wRWA total ; redeemers 4,000 USDC ; only 6,000 touched the fund
```

### Worked example RS5 - redemptions win (4k / 10k, NAV = 1.0)

```
subTotalUSDC = 4,000 ; redeemTotalWRWA = 10,000
matchedUSDC = 4,000 ; matchedWRWA = 4,000
P2P: 4,000 wRWA -> subscribers ; 4,000 USDC -> redeemers
netRedeemWRWA = 6,000 -> bridge to Pruv -> redeem -> ~6,000 USDC back (less Pruv exit fee) -> redeemers
```

## 9. NAV and oracle

- `nav()` returns the last relayed `RWAConversion.value()`.
- **Staleness**: `nav()` reverts `StalePrice` if `now - lastUpdated > STALENESS_WINDOW` (value
`confirm T0.x` from Pruv NAV cadence). `initiateEpoch` therefore cannot settle on a stale price.
- **Sanity bound**: `setNav` reverts `NavSanityBound` if the new value differs from the last accepted
value by more than `MAX_NAV_MOVE_BPS` (config), defending against a corrupted/spoofed relay.
- `setNav` accepts messages only from the enrolled `NavReporter` on the expected domain.

## 10. Fees (PRD §Fees)


| Fee                       | When                           | Basis                | Default      |
| ------------------------- | ------------------------------ | -------------------- | ------------ |
| Subscription cancellation | `cancelRequest` on a subscribe | bps of escrowed USDC | configurable |
| Redemption                | at redeem settle/claim         | bps of USDC proceeds | configurable |


- All fees are **previewable** (`previewSubscribe`/`previewRedeem`) before signing.
- **Pruv's own fees** (`RWAFee` entry/exit) are borne only by the **net delta** that actually
deposits/redeems at Pruv; the matched P2P portion pays no Pruv fee (constitution Article 7.2).

## 11. Cross-chain messaging and idempotency

- Every outbound Pruv leg carries `epochId`; the return is keyed to the same `epochId`.
- `settleEpoch` requires the matching return; a replayed return is a no-op (`returnReceived`
latch + `BridgeMessageReplay` guard).
- Inbound handlers (`onBridgedUsdc`, `onBridgedWrwa`, `setNav`, return handler) validate sender and
domain; unauthorized origin reverts `UnauthorizedSender`.
- Failure of a leg leaves the epoch `Initiated`; recovery is retry (keeper) or `PruvExecutor.sweep`
(admin) - never a silent double.

## 12. Errors

`InvalidState`, `EpochInFlight`, `EpochNotInFlight`, `NothingToSettle`, `RequestNotClaimable`,
`NotRequestOwner`, `ZeroAmount`, `QueueCapExceeded`, `BelowMinTicket`, `LaunchpadNotClosed`,
`StalePrice`, `NavSanityBound`, `UnauthorizedSender`, `BridgeMessageReplay`, `NotWhitelisted`
(executor).

## 13. Events

`LaunchpadDeposited`, `LaunchpadClosed(success)`, `Refunded`, `Requested`, `Cancelled`,
`EpochInitiated`, `MatchingPerformed(matchedUSDC, matchedWRWA)`, `NetSubBridged(usdc, msgId)`,
`NetRedeemBridged(wrwa, msgId)`, `BridgeReturnReceived(epochId, amount)`, `EpochSettled(epochId)`,
`Claimed(requestId, amount)`, `NavUpdated(value, timestamp)`, `WindDownTriggered`, `Closed`.

## 14. Invariants (assert in tests; fuzz the starred)

- ★ **Conservation**: over a full epoch including bridge legs, tokens in = tokens out + fees.
- ★ **No stranded funds**: every in-flight amount is either delivered or recoverable.
- **No double**: a request is claimed at most once; a bridge return settles at most once.
- **Single in-flight**: never two `Initiated` epochs.
- **Matching creates no value**: matched wRWA to subscribers equals matched wRWA from redeemers;
matched USDC likewise.
- **Solvency while in-flight**: assigned payouts ≤ assets held or in-flight for that epoch.

## 15. Acceptance scenarios (exact numbers where numeric)


| #       | Scenario                                     | Proves                                                                                                 |
| ------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **RS1** | Launchpad success end-to-end                 | gather ≥ min → subscribe at Pruv → distribute wRWA; depositors made whole                              |
| **RS2** | Launchpad fail refund                        | below min → 100% USDC refunded                                                                         |
| **RS3** | Cancel pending request (7887)                | queued request withdrawn before initiate; USDC/wRWA returned (less cancel fee if subscribe)            |
| **RS4** | Matching subs win (10k/4k)                   | matched 4,000 P2P, only 6,000 USDC bridged to Pruv; exact numbers per §8                               |
| **RS5** | Matching redeems win (4k/10k)                | matched 4,000 P2P, 6,000 wRWA bridged to Pruv redeem                                                   |
| **RS6** | Async settlement across the in-flight window | initiate epoch N, settle only after bridge return; claims correct; no second epoch initiates meanwhile |
| **RS7** | NAV change via oracle                        | NAV +10% → redeemers paid 10% more; stale NAV blocks settlement                                        |
| **RS8** | Bridge failure + retry                       | stuck leg does not settle; retry recovers; no double-mint/double-pay                                   |
| **RS9** | Wind-down                                    | pending subs refunded, redemption queue settled via Pruv, retail-held wRWA retained; ends Closed       |


## 16. Research-dependent values (resolve in Phase 0)


| Symbol                       | Meaning                         | Task               |
| ---------------------------- | ------------------------------- | ------------------ |
| `d_w`                        | wRWA decimals on the home chain | T0.1 / T0.3        |
| `STALENESS_WINDOW`           | max NAV age                     | T0.1 (NAV cadence) |
| `MAX_NAV_MOVE_BPS`           | sanity bound                    | T0.1 + risk review |
| wRWA warp route              | reuse existing or deploy        | T0.2               |
| Pruv `RWAFee` bps            | entry/exit rates                | T0.1               |
| minimum ticket, epoch period | admin launch inputs             | product            |


