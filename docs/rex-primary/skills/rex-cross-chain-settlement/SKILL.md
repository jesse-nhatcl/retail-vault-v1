---
name: rex-cross-chain-settlement
description: Use when implementing or debugging REX Primary epoch settlement across the home chain and PRUV - initiate/settle phases, the in-flight window, the bridge round-trip, or any situation where cross-chain funds could be stranded, double-settled, or settled on a stale price.
---

# REX Cross-Chain Settlement

## Overview

An REX epoch is a **distributed transaction, not an atomic one**. Because Pruv lives on another
chain, value must cross the bridge and come back before the epoch can finish. Model it as two
home-chain calls with an async gap between them.

## The three phases

1. **initiate** (home, atomic): snapshot the collecting epoch's requests, read `nav()` (reverts if
   stale), run matching, settle the matched portion P2P, bridge the net delta out. Mark the epoch
   `Initiated` (in-flight).
2. **execute** (PRUV, async): `PruvExecutor` receives the bridged token, calls `RWAToken.deposit`
   or `redeem`, bridges the result home. Keyed to `epochId`.
3. **settle** (home): once the return arrives (`returnReceived`), distribute to claimers, advance
   to the next collecting epoch.

## Quick reference

| Guard | Rule |
|---|---|
| Single in-flight | `initiateEpoch` reverts `EpochInFlight` if the prior epoch is not `Settled` |
| Idempotency | every outbound leg carries `epochId`; a replayed inbound return is a no-op |
| Staleness | `initiate` reads `nav()`, which reverts `StalePrice` when NAV is too old |
| Recovery | a stuck leg leaves the epoch `Initiated`; recover by retry (keeper) or `sweep` (admin) |
| Solvency | assigned payouts never exceed assets held or in-flight for that epoch |

## Invariants to hold every step

- Conservation across the full round-trip: tokens in = tokens out + fees.
- No stranded funds: every in-flight amount is delivered or recoverable.
- A request is claimed at most once; a return settles at most once.

## Common mistakes

- **Assuming atomicity.** Do not deposit-and-distribute in one transaction; the Pruv leg is on
  another chain. Split initiate/settle.
- **Settling before the return.** `settleEpoch` must require `returnReceived`; otherwise you
  distribute funds you do not yet hold.
- **No idempotency key.** A re-delivered bridge message must not settle twice. Key on `epochId` +
  a latch.
- **Two epochs in flight.** Never initiate a new epoch before the current settles - solvency
  accounting assumes one.
- **Trusting any inbound caller.** Verify enrolled sender + expected domain on every handler.

## Reference

Spec: `../../specs/spec.md` §5, §7, §11, §14; constitution Articles 4-5. (An earlier single-chain POC used
an atomic `processEpoch`; the async initiate/settle split and the recovery paths here are new.)
