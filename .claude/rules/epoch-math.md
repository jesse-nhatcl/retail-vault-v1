# processEpoch & NAV Math (project)

The settlement core. Implement spec §6.1 / §6.2 **literally**. This file restates the invariants
that must hold so you don't drift.

## NAV
```
navNow = totalAssets() * 1e18 / totalSupply()      // totalAssets is 6-dec USDC, supply 18-dec
redeemValueUSDC = redeemShares * navNow / 1e18      // -> 6-dec USDC
matchedShares  = matchedUSDC * 1e18 / navNow        // -> 18-dec shares
```
`totalAssets() = wRWABalance * pruvPrice / 1e18 + liquidBalance` (both terms in 6-dec USDC).

## Precondition: admin submits the price first
`processEpoch` (and `triggerWindDown`) reads the price for NAV via the `INavSource` seam
(`navSource.pricePerWRWA()`; `MockPruv` implements it). The admin MUST call `MockPruv.setPrice(p)`
in a prior tx each epoch. This is **not enforced in code** (spec decision 5.5,
POC) — forgetting it settles at the stale price. Tests/Demo always do `setPrice` then `processEpoch`.

## Settlement order (one `processEpoch`, atomic)
1. **Snapshot** sub/redeem queues for `currentEpoch` (skip cancelled & fulfilled).
2. **Match**: `matchedUSDC = min(subPending, redeemValueUSDC)`. Allocate matched shares to
   subscribers pro-rata by their USDC; matched USDC to redeemers pro-rata by their shares.
   Burn `matchedShares`.
3. **Net delta** — exactly one branch fires:
   - `netSub > 0`: `computeRebalanceBuy(netSub)` → `custody.subscribeToPruv` +
     `custody.swapUSDCForLiquid`; mint net-sub shares to subscribers pro-rata.
   - `netRedeem > 0`: 3-layer sourcing → liquid buffer first, then Pruv redeem; pay redeemers
     pro-rata, burn their net shares.
   - exact match: no-op asset action (still emit event).
4. Emit `EpochProcessed`, `currentEpoch += 1`. Users then `claim(requestId)`.

## Rebalance-toward-target (§6.2)
Buy the **under-allocated** sleeve to push back toward `illiquidBps / (10000 - illiquidBps)`.
If `buyIlliquid + buyLiquid` overshoots `netSub`, scale both down proportionally; if it undershoots,
excess goes to illiquid.

## Invariants (assert in tests; candidates for `invariant_` fuzz)
- `totalAssets()` ≥ outstanding redemption obligations at every step.
- Matching never mints net new value: subscribers' matched shares come from redeemers' burnt shares.
- After a happy-path full lifecycle, final `totalSupply == 0`.
- No USDC/shares created or destroyed except via mint (sub), burn (redeem), or mock subscribe/redeem.
- Redemption never touches Pruv (Layer 3) while liquid buffer (Layer 2) can cover the need.

## Known simplifications (POC)
- Pruv always fulfills fully (window assumed open). Partial-fill rollover is documented as a
  deferred edge case (S6 note), not implemented.
- Liquid buffer swaps 1:1 with USDC via `MockAMM`.
