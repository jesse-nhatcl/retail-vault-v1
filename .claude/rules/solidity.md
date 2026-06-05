# Solidity Conventions (project)

Derived from `docs/03-tech-stack.md §6` and `docs/02-architecture/decision.md`. These are binding.

## Compiler
- `pragma solidity 0.8.24;` — fixed, no caret.
- EVM target Cancun. Optimizer on, runs=200. `via_ir` stays **off** unless a real stack-too-deep
  appears (then enable in `foundry.toml`, don't refactor blindly).

## Naming
- `PascalCase` contracts/structs/enums, `camelCase` functions/vars, `UPPER_SNAKE` constants.
- Interfaces prefixed `I` (`IVault`, `ICustody`).

## Errors & events
- Custom errors only: `error InvalidState(State current);` — never `require(cond, "string")`.
- Every state mutation emits an event. Prefer emitting **before** external calls for debuggability.
- Named, specific events: `MatchingPerformed(uint256 matchedUSDC, uint256 matchedShares)`,
  `NetSubSettled(...)`, `NetRedeemSettled(...)`, `EpochProcessed(...)`.

## Safety
- `nonReentrant` (OZ `ReentrancyGuard`) on `claim`, `refund*`, `withdrawUSDC`, `processEpoch`,
  `depositToLaunchpad`, `requestDeposit`, `requestRedeem`.
- `SafeERC20` for all token transfers.
- `Ownable` (OZ v5: constructor takes `initialOwner`) for the single admin. No roles.
- Custody functions are `onlyVault`. Custody never trusts an EOA.
- Validate at boundaries (user input, state preconditions); trust internal calls.

## Math
- `Math.mulDiv` from OZ for every pro-rata or cross-decimal `a * b / c`. Never raw `*` then `/`
  on user-scaled values.
- Mind the decimal table in `CLAUDE.md`. USDC=6, shares=18, price/wRWA=18.

## Structure
- `external` over `public` unless called internally.
- NatSpec (`///`) on every `external`/`public` function: `@notice`, `@param`, `@return`.
- No dead code, no commented-out blocks, no TODO left in committed code.
- Cap per-epoch queue iteration at 100 (gas safety). Cancelled requests stay in the array, skipped
  during iteration — never deleted/reindexed.

## Out of scope — do not add
See `CLAUDE.md` guardrails. No fees, no oracle, no roles, no bridge, no ERC-4626 inheritance.
