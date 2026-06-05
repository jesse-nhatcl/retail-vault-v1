---
name: processepoch-walkthrough
description: Step-by-step arithmetic reference for the Vault.processEpoch() matching, rebalance-buy, and 3-layer redemption math. Use when implementing or debugging processEpoch, matching, NAV, or redemption sourcing.
---

# processEpoch Walkthrough

Concrete arithmetic for the settlement core. Pairs with `.claude/rules/epoch-math.md` and spec §6.
All USDC values 6-dec, shares 18-dec, prices/NAV scaled 1e18 (see `CLAUDE.md` table).

## Worked example — S4 (Sub > Redeem), NAV = 1.0
State in: custody 80k wRWA + 20k liquid, supply 100k, pruvPrice 1e18.
- `totalAssets = 80_000e6 * 1e18/1e18 + 20_000e6 = 100_000e6`.
- `navNow = 100_000e6 * 1e18 / 100_000e18 = 1e6`.
- subPending `= 10_000e6`; redeemShares `= 4_000e18`; `redeemValueUSDC = 4_000e18 * 1e6/1e18 = 4_000e6`.
- `matchedUSDC = min(10_000e6, 4_000e6) = 4_000e6`; `matchedShares = 4_000e6 * 1e18/1e6 = 4_000e18`.
- Bob (only redeemer): +4_000e6 USDC, his 4_000e18 shares burnt. Alice: +4_000e18 matched shares.
- `netSub = 10_000e6 - 4_000e6 = 6_000e6`. Rebalance buy toward 80/20 on totalAssetsAfter=106k →
  buy ≈ 4_800e6 illiquid + 1_200e6 liquid. Mint `6_000e6 * 1e18/1e6 = 6_000e18` net-sub shares to Alice.
- Alice total = 4_000 + 6_000 = **10_000e18** shares. Bob = 0 shares, +4_000e6 USDC. ✓

## Worked example — S5 (Redeem > Sub), NAV = 1.0
- subPending 4_000e6; redeemShares 10_000e18 → redeemValue 10_000e6. matched 4_000e6 / 4_000e18 shares.
- Alice +4_000e18 shares. Bob +4_000e6 (match). `netRedeem = 6_000e6`.
- Layer 2: liquid 20_000e6 ≥ 6_000e6 → swap 6_000 liquid→USDC, Bob +6_000e6 (total 10_000e6).
  Bob's remaining 6_000e18 shares burnt. Custody liquid 20k→14k. No Layer 3. ✓

## Matching pro-rata (multiple users)
```
userMatchedUSDC   = mulDiv(req.amount, matchedUSDC, subPending)        // per subscriber
userMatchedShares = mulDiv(req.amount, matchedShares, redeemShares)    // per redeemer
```

## computeRebalanceBuy(netSub)
```
totalAfter   = totalAssets() + netSub
targetIll    = mulDiv(totalAfter, illiquidBps, 10000)
targetLiq    = totalAfter - targetIll
curIll       = mulDiv(wRWABalance, pruvPrice, 1e18)
curLiq       = liquidBalance
buyIll = curIll < targetIll ? targetIll - curIll : 0
buyLiq = curLiq < targetLiq ? targetLiq - curLiq : 0
total = buyIll + buyLiq
if total > netSub:  scale both down by netSub/total (mulDiv)
elif total < netSub: buyIll += (netSub - total)
```

## 3-layer redemption (net redeem)
1. Matching (done above).
2. Liquid: `take = min(remaining, liquidBalance)`; `swapLiquidForUSDC(take)`; `remaining -= take`.
3. Illiquid: if `remaining > 0`, `wrwa = remaining * 1e18 / pruvPrice`; `redeemFromPruv(wrwa)`;
   POC assumes full fill → `remaining = 0`.

## Failure triage
Wrong by a factor of ~1e12 → decimal mismatch (mixing 6-dec USDC with 18-dec shares without mulDiv
scaling). Off by 1–2 wei → rounding; ensure consistent floor via `mulDiv`. Wrong sleeve bought →
check under-allocation comparison direction.
