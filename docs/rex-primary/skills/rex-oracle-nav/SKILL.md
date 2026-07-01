---
name: rex-oracle-nav
description: Use when implementing or debugging REX Primary NAV - relaying RWAConversion.value() from PRUV to the home chain, enforcing the staleness guard and sanity bound, or converting between NAV, USDC, and wRWA in matching or settlement.
---

# REX Oracle NAV

## Overview

NAV is read from Pruv's `RWAConversion.value()` on PRUV (18-decimal, parity `1e18`) and **relayed**
to the home chain, where `NavOracleConsumer` stores it with a timestamp. REX never invents a price
and never settles on a stale or wildly-moved one.

## Path

`NavReporter` (PRUV) reads `value()` → dispatches over Hyperlane → `NavOracleConsumer.setNav`
(home). `REXPrimary.nav()` proxies the consumer and is read at `initiateEpoch`.

## Guards (both mandatory)

| Guard | Behavior |
|---|---|
| Staleness | `nav()` reverts `StalePrice` if `now - lastUpdated > STALENESS_WINDOW`. So `initiateEpoch` cannot settle on an old price. |
| Sanity bound | `setNav` reverts `NavSanityBound` if the new value moved more than `MAX_NAV_MOVE_BPS` from the last accepted value. Defends against a corrupted/spoofed relay. |
| Origin | `setNav` accepts only the enrolled `NavReporter` on the expected domain. |

`STALENESS_WINDOW` and `MAX_NAV_MOVE_BPS` are set from Phase 0 research (NAV cadence + risk review).

## Decimal conversions

```
redeemValueUSDC = mulDiv(wrwa, nav, 1e18)    // value wRWA in USDC
wrwaForUSDC     = mulDiv(usdc, 1e18, nav)     // value USDC in wRWA
```

NAV is 18-dec; USDC and wRWA are 6-dec (confirm `d_w` in Phase 0). Always `Math.mulDiv`.

## Common mistakes

- **Reading NAV without the staleness check.** Settlement must fail closed on stale NAV, not use the
  last value blindly.
- **No sanity bound.** A single bad relayed value could revalue the whole queue; bound the move.
- **Trusting any setNav caller.** Verify the reporter origin.
- **Confusing 18-dec NAV with 6-dec tokens.** The `/1e18` is NAV scaling, independent of token
  decimals; keep them straight.
- **Caching NAV across the in-flight window.** Use the NAV snapshotted at `initiateEpoch`
  (`epoch.navAtInitiate`) for that epoch's settlement.

## Reference

Pruv NAV reference (`RWAConversion.value()`): `../../references/pruv-interface.md`.
Spec: `../../specs/spec.md` §9; ADR: `../../decisions/ADR-004-oracle-nav-hyperlane.md`.
