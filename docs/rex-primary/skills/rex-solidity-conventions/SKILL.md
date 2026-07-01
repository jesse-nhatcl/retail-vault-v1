---
name: rex-solidity-conventions
description: Use when writing or reviewing REX Primary Solidity on either chain - error handling, events, reentrancy, token transfers, cross-decimal math, queue iteration limits, or access control for the home contracts and the PRUV executor.
---

# REX Solidity Conventions

## Overview

The binding coding rules for REX Primary contracts (`REXPrimary`, `NavOracleConsumer`, `FeeModule`
on home; `PruvExecutor`, `NavReporter` on PRUV). These operationalize the constitution's security
article for day-to-day code.

## Quick reference

| Area | Rule |
|---|---|
| Errors | Custom errors only, never `require("string")`. Names from `../../specs/spec.md` §12. |
| Events | Every state mutation emits a named event; emit **before** external calls where possible. |
| Reentrancy | `nonReentrant` on `claim`, `refund*`, `settleEpoch`, and all bridge/inbound handlers. |
| Transfers | `SafeERC20` for every token move. Checks-effects-interactions always. |
| Math | `Math.mulDiv` for every pro-rata / cross-decimal `a * b / c`. Never raw. |
| Decimals | USDC 6, wRWA `d_w` (confirm Phase 0), NAV 18 / parity `1e18`. No REX share token. |
| Access | Retail permissionless; admin = multisig; keeper cannot move funds arbitrarily; executor holds the sole Whitelist. |
| Origin | Every cross-chain handler verifies enrolled sender + expected domain before acting. |
| Idempotency | Cross-chain handlers are no-ops on replay (latch by `epochId`/`messageId`). |
| Queues | Cap iteration at 100 requests/epoch; cancelled requests are skipped, never deleted/reindexed. |
| Compiler | Pinned version, no caret. No upgradeable proxy without an ADR naming the upgrade authority. |
| `external` | Prefer `external` over `public`; NatSpec on every external/public function. |

## Common mistakes

- **`require` strings.** Use the custom errors enumerated in the spec so callers can switch on them.
- **Interaction before effect.** Set state (mark claimed/settled) before the external transfer, or
  reentrancy bites.
- **Raw multiply-divide on user amounts.** Always `Math.mulDiv`.
- **Missing origin check on a handler.** A cross-chain entrypoint without sender/domain validation
  is an open door.
- **Deleting cancelled requests.** Reindexing breaks receipt ids; skip in place.
- **No dead code / commented blocks / TODOs** in committed contracts.

## Reference

Spec: `../../specs/spec.md` §12-14; constitution Article 12; `../../decisions/ADR-006-token-standards.md`.
These conventions are self-contained here; do not assume single-chain behavior from any earlier POC.
