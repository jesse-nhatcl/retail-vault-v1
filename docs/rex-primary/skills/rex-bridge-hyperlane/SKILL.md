---
name: rex-bridge-hyperlane
description: Use when integrating or debugging the Hyperlane warp routes for REX Primary - transferRemote, quoting the interchain fee, message-id idempotency, enrolled-sender/domain checks, or diagnosing a stuck or failed cross-chain transfer.
---

# REX Bridge (Hyperlane Warp Routes)

## Overview

REX moves two tokens across two chains with Hyperlane **warp routes**: **USDC** (home ↔ PRUV) and
**wRWA** (PRUV ↔ home). A warp route locks the real token via `HypERC20Collateral` on one side and
mints a `HypERC20` synthetic on the other. `transferRemote(dstDomain, recipient, amount)` moves
value; the message is delivered and verified by Hyperlane's ISM.

## Quick reference

| Concern | Rule |
|---|---|
| Domains | home chain domain vs PRUV `7336`; never hard-code the wrong side |
| Fee | quote the interchain gas payment **before** `transferRemote`; underpaying leaves the message undelivered |
| Idempotency | key every REX action on `epochId` (or `messageId`); a re-delivered message must be a no-op |
| Origin check | inbound handlers act only on an **enrolled sender** from the **expected domain** |
| Failure | undelivered/stuck message → do not settle; retry delivery or `sweep` on the destination |

## Sending

1. Quote the interchain fee for `dstDomain`.
2. Approve/lock the token to the warp route.
3. `transferRemote(dstDomain, recipient, amount)` with the fee attached; capture the `messageId`.
4. Record `messageId`/`epochId`; mark the epoch in-flight.

## Receiving

Inbound handlers (`onBridgedUsdc`, `onBridgedWrwa`, the return handler, `setNav`):

- verify sender is the enrolled remote router/reporter and origin domain is expected (else revert
  `UnauthorizedSender`);
- are idempotent per `messageId`/`epochId` (a replay is a no-op, guarded by a latch and
  `BridgeMessageReplay`).

## Common mistakes

- **Not quoting the fee.** The message silently never arrives; the epoch hangs in-flight. Always
  quote and attach.
- **Acting on any caller.** Without the enrolled-sender + domain check, a forged message can drain
  or mis-settle. Check origin first.
- **No idempotency.** Hyperlane can re-deliver; without a latch you double-mint or double-pay.
- **Assuming synchronous delivery.** Delivery takes relay time; never block a transaction waiting
  for it - use the keeper to observe and then settle.
- **Reusing the PRUV↔Kaia route for Sepolia.** That route does not reach the home chain; confirm
  reuse-vs-deploy in Phase 0 (T0.2).

## Reference

Pruv bridge reference (addresses, domains, route types): `../../references/pruv-interface.md`.
Spec: `../../specs/spec.md` §11; ADR: `../../decisions/ADR-001-cross-chain-pa2.md`.
