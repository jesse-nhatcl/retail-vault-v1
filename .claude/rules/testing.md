# Testing Conventions (project)

From `docs/03-tech-stack.md §7` and spec §9. All 8 scenarios must pass in `forge test` < 30s.

## TDD (binding)
Write the failing test first, watch it fail for the right reason, then implement. See the
`superpowers:test-driven-development` skill. Applies to mocks, Custody, Vault, and each scenario.

## Layout
- `test/Vault.t.sol`, `test/Custody.t.sol` — unit / state-machine tests.
- `test/scenarios/S<n>_*.t.sol` — one file per scenario S1–S8, each inherits `Fixture`.
- `test/helpers/Fixture.sol` — shared setup: actors `alice`/`bob`/`charlie` via `makeAddr`,
  deployed + funded mocks, deployed Vault + Custody, configured launchpad params.

## Style
- Name tests `test_<behavior>` and `test_Revert_<reason>` / use `vm.expectRevert(Err.selector)`.
- Use `vm.warp(block.timestamp + delta)` for launchpad timing and epoch transitions.
- Assert **exact** numbers for S4/S5 (the matching contract) — these are acceptance criteria,
  not approximate. Use the precise values in spec §9.
- `vm.prank` / `startPrank` for actor calls; admin calls from the owner address.
- Assert post-state: balances, `totalSupply`, custody composition, `state()`, queue contents.
- Add at least one `invariant_` test for `totalAssets ≥ obligations` if time permits.

## Decimals in tests
Helper constants: `1e6` per USDC unit, `1e18` per share. e.g. `30_000e6` USDC,
`30_000e18` shares. Cross-check every expected value against the decimal table in `CLAUDE.md`.

## Before claiming "done"
Run the real command and read the output (see `superpowers:verification-before-completion`).
`forge test` green + `forge fmt --check` clean. Never assert success from inference.
