---
name: rex-epoch-matching
description: Use when implementing or verifying REX Primary matching - netting subscription USDC against redemption wRWA at NAV, computing the net delta bridged to Pruv, settling the matched portion peer-to-peer, or checking the 10k/4k acceptance numbers.
---

# REX Epoch Matching

## Overview

Matching nets subscriptions against redemptions at NAV so **only the delta touches Pruv**. In REX
Primary there is **no vault token**: the matched portion settles by **raw token transfer** (wRWA and
USDC move directly between the two sides), never by minting or burning a share.

## The math (6-dec USDC, 6-dec wRWA example, NAV parity 1e18)

```
subTotalUSDC    = Σ subscribe.amount
redeemTotalWRWA = Σ redeem.amount
redeemValueUSDC = mulDiv(redeemTotalWRWA, nav, 1e18)

matchedUSDC = min(subTotalUSDC, redeemValueUSDC)
matchedWRWA = mulDiv(matchedUSDC, 1e18, nav)

netSubUSDC    = subTotalUSDC   - matchedUSDC       // > 0 -> bridge USDC to Pruv deposit
netRedeemWRWA = redeemTotalWRWA - matchedWRWA      // > 0 -> bridge wRWA to Pruv redeem
```

Matched settlement is pro-rata and P2P: subscribers split `matchedWRWA` by their USDC share;
redeemers split `matchedUSDC` by their wRWA share. Use `Math.mulDiv` for every pro-rata step.

## Worked examples (the acceptance contract)

| Scenario | subs | redeems | matched | net to Pruv |
|---|---|---|---|---|
| RS4 subs win | 10,000 USDC | 4,000 wRWA | 4,000 | 6,000 USDC deposited |
| RS5 redeems win | 4,000 USDC | 10,000 wRWA | 4,000 | 6,000 wRWA redeemed |

RS4 outcome: subscribers end with ~10,000 wRWA (4,000 matched + ~6,000 from Pruv, less Pruv entry
fee); redeemers get 4,000 USDC. Assert these **exactly** in tests.

## Common mistakes

- **Minting a share for matched flow.** There is no REX share. Move the actual escrowed tokens.
- **Charging Pruv fees on the matched portion.** Only the net delta round-trips Pruv, so only it
  bears `RWAFee` (ADR-005). Matched flow pays no Pruv fee.
- **Raw `a * b / c`.** Cross-decimal math must use `Math.mulDiv` or you lose precision / overflow.
- **Valuing redemptions at request-time NAV.** Value at the NAV read at `initiateEpoch`, not when
  the request was made.
- **Both branches firing.** Exactly one of `netSubUSDC` / `netRedeemWRWA` is positive (or neither on
  an exact match).

## Reference

Spec: `../../specs/spec.md` §8; ADR: `../../decisions/ADR-002-no-vault-token.md`. (An earlier POC matched
share-based, minting/burning a vault share; here matching is raw token transfer - no share exists.)
