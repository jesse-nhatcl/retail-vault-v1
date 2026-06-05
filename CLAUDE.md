# retail-access-vault — Project Memory

Local **proof-of-concept** for the Retail Access PRD **Alternative 1**: an ERC-7540-style async
vault wrapping an illiquid private credit fund (`MockPruv`) plus a ~20% liquid buffer. Solidity +
Foundry, single Anvil chain, no UI, no deployment. Goal is to prove the **mechanism** — state
machine, queue, P2P matching, 3-layer redemption — not to ship a product.

**The spec is the source of truth: `docs/05-spec.md`.** It is self-contained. `docs/SUMMARY.md` is the
decision-grade overview; `docs/01-requirements.md` and `docs/02-architecture/decision.md` hold the
"why". Read the spec before touching any `.sol` file. If implementation contradicts the spec, the
spec wins unless the user says otherwise.

## Commands

```bash
forge build                                   # compile
forge test                                     # run all tests
forge test --match-contract S4 -vvv            # one scenario, verbose
forge test --match-test invariant_ -vvv        # invariants only
forge fmt                                       # format (run before every commit)
forge script script/Demo.s.sol --sig 'run(string)' "S4" -vvv   # parameterised demo
slither . 2>/dev/null || true                  # optional static analysis, end of phase
```

## Architecture (ADR 001 — locked)

Two production contracts. **Vault holds state; Custody holds tokens.**

- `Vault.sol` — state machine, sub/redeem queues, matching, ERC-20 shares, `processEpoch()`.
- `Custody.sol` — holds wRWA + liquid + idle USDC; Pruv subscribe/redeem; liquid↔USDC swaps.
  `onlyVault` gated — never accepts EOA calls.
- Mocks: `MockUSDC` (6 dec), `MockPruv` (admin `setPrice`), `MockLiquidBuffer`, `MockAMM` (1:1).
- Interfaces: `IVault`, `ICustody` (signatures locked in `docs/02-architecture/decision.md`).

## Decimal & NAV convention (READ THIS — main bug source)

| Quantity | Decimals / scale |
|---|---|
| USDC, wRWA, liquid-buffer tokens — all balances & `totalAssets()` | **6** |
| Vault shares / `totalSupply` | **18** |
| `MockPruv.pricePerWRWA` | **1e18-scaled**, parity = `1e18` (1.0). `setPrice(1.1e18)` = +10% |
| `nav()` = `totalAssets() * 1e18 / totalSupply()` | parity ≈ `1e6` (not 1e18 — falls out of 6-dec assets ÷ 18-dec supply; formula is what matters) |

Mock tokens (wRWA, liquid) are deliberately **6-dec** so `mulDiv(bal, price, 1e18)` stays in 6-dec
USDC and `setPrice(x*1e18)` reads as a clean multiplier. Only vault **shares** are 18-dec.

Follow the spec §6.1 formulas **literally** — they are internally consistent across the decimal
mix. Verify with S7: 80k wRWA × 1.1 + 20k liquid = 108k USDC; supply 100k → `nav = 108_000e6 * 1e18
/ 100_000e18 = 1.08e6`; redeem 10 shares → `10e18 * 1.08e6 / 1e18 = 10.8e6` = 10.8 USDC. ✓
Use OpenZeppelin `Math.mulDiv` for every pro-rata / cross-decimal multiply-then-divide.

## Locked mechanism decisions (SUMMARY §5 — do not redesign)

1. Async queue: request → queue → fulfill at epoch (not instant mint/burn).
2. `cancelRequest(id)` allowed before the epoch processes (ERC-7887).
3. Launchpad receipts via `mapping(address => uint256)`, **not** a transferable token.
4. Single `processEpoch()` processes both queues atomically; **matching runs first**.
5. NAV is manual: admin calls `MockPruv.setPrice()` before each epoch. No oracle. See **Admin price
   submission** below.
6. Net subscriptions buy the **under-allocated** sleeve first (rebalance toward 80/20).
7. Redemption sourcing order is strict: **matching → liquid buffer → illiquid Pruv**.
8. Matching/redemption value uses NAV **at epoch time**, not request time.
9. Single `Ownable` admin. No role-based access control.
10. Custody separated from Vault.
11. Pruv is an on-chain mock on the same Anvil chain. No bridge.

## Admin price submission (operational precondition)

NAV is fed manually, not by an oracle. **Before every `processEpoch()` (and before `triggerWindDown`),
the admin MUST submit the current price** via `MockPruv.setPrice(newPrice)` — a separate
owner-gated tx (`src/mocks/MockPruv.sol`). The Vault reads the price on-demand in
`totalAssets()`, `nav()`, `computeRebalanceBuy`, and the illiquid redemption layer — through the
narrow `INavSource { pricePerWRWA() }` seam (`src/interfaces/INavSource.sol`), **not** the concrete
`MockPruv` type. `MockPruv implements INavSource`; the Vault stores it as `navSource`. The seam is
the single injection point: swapping in a real Pruv NAV feed or an oracle later is a drop-in with no
Vault change. It does **not** introduce an oracle — price stays manual per decision 5.

Two-tx flow each epoch:
```
MockPruv.setPrice(p)   // owner; p is 1e18-scaled, 1e18 = parity
Vault.processEpoch()   // settles at that price
```
**This is NOT enforced in code** — by deliberate spec decision 5.5 (POC simplicity / test
controllability). If the admin forgets, `processEpoch` silently settles at the *previous* price.
In production this is replaced by Pruv's real NAV reporting; the Vault interface does not change.
A staleness guard (`StalePrice` revert) was considered and intentionally deferred — adding one is
the first thing to do when this graduates past POC.

## State machine (one-way transitions)

`Initialized → LaunchpadStart → (LaunchpadFail | EpochBased) → WindDown → Closed`

## Acceptance: the 8 scenarios

Each maps to `test/scenarios/S<n>_*.t.sol` and a `Demo` branch. S4/S5 numeric outcomes are the
matching contract — get those exactly right. Definitions and expected numbers live in spec §9.

## Scope guardrails — STOP and ask before doing any of these

UI · cross-chain bridge · Aave reinvest · real Curve formula (mock AMM is 1:1) · real Pruv API ·
role-based access · NAV oracle / Chainlink · full ERC-4626 compliance · gas-opt pass · audit
hardening · mainnet/testnet deploy · any fee model (all fees are 0% in this POC).
Pulling any of these into scope → re-estimate first (SUMMARY §11).

## Conventions

Solidity `0.8.24` pinned (no `^`). Custom errors, not `require` strings. Every state mutation emits
an event. NatSpec on all `external`/`public`. `nonReentrant` on `claim`/`refund`/`withdrawUSDC`/
`processEpoch`. `external` over `public` where possible. Cap queue iteration at 100/epoch.
TDD: write the failing test first. Full conventions in `.claude/rules/`.
