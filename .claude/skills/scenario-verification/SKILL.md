---
name: scenario-verification
description: Run and verify the 8 acceptance scenarios (S1-S8) of the retail-access-vault. Use when implementing, debugging, or confirming a scenario test, or when running the Demo script for a scenario.
---

# Scenario Verification

The 8 scenarios in `docs/05-spec.md §9` are the POC's acceptance criteria. Each has a test file and
a Demo branch. Use this skill when working on any S1–S8.

## Commands
```bash
forge test --match-contract S4 -vvv                          # run scenario S4's test, verbose traces
forge script script/Demo.s.sol --sig 'run(string)' "S4" -vvv  # human-readable demo of S4
forge test                                                    # full suite, must be green
```

## The 8 scenarios (one-line each — full numbers in spec §9)
- **S1** Happy path full lifecycle: launchpad → epoch (sub 10k + redeem 5k, matched 5k) → winddown → closed, final supply 0.
- **S2** Launchpad fail (30k < 50k min) → refund restores Alice's USDC, custody empty.
- **S3** Cancel pending sub before `processEpoch` → USDC refunded, epoch is a no-op.
- **S4** Match Sub>Redeem: sub 10k, redeem 4k @ NAV 1.0 → matched 4k; Bob +4k USDC; Alice 10k shares; net 6k buys ~80/20.
- **S5** Match Redeem>Sub: sub 4k, redeem 10k → matched 4k; Alice 4k shares; Bob 4k(match)+6k(liquid)=10k USDC; custody liquid 20k→14k.
- **S6** Illiquid fallback: liquid drained to 2k, redeem 8k → 2k liquid + 6k Pruv redeem → Alice 8k USDC.
- **S7** NAV change: setPrice(1.1e18) → totalAssets 108k, NAV 1.08; redeem 10 shares → 10.8 USDC.
- **S8** Wind-down mid-epoch: refund sub queue, liquidate liquid, settle redeem, liquidate illiquid, → Closed.

## Verifying a scenario
1. Read the exact expected numbers in spec §9 — do **not** approximate S4/S5.
2. Assert post-state: actor balances, `totalSupply`, custody composition (wRWA + liquid + idle USDC),
   `state()`, and queue emptiness.
3. Decimals: USDC 6-dec (`4_000e6`), shares 18-dec (`4_000e18`). Cross-check against `CLAUDE.md` table.
4. If a number is off, suspect a `mulDiv` decimal mismatch first (see `.claude/rules/epoch-math.md`),
   then matching pro-rata rounding, then rebalance-buy split.
5. On a failure, debug with the `superpowers:systematic-debugging` skill — find root cause, don't patch the assert.
