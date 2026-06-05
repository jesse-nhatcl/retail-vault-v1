# 03 — Tech Stack (Phase P)

**Project:** retail-access-vault
**Date:** 2026-06-02
**Architecture:** ADR 001 — Vault + Custody

---

## 1. Language & Compiler

| Item | Choice | Rationale |
|---|---|---|
| Language | **Solidity 0.8.24** | Latest stable; PUSH0, transient storage available if needed |
| EVM target | **Cancun** | Default in Foundry 2026 |
| Optimizer | **enabled, runs=200** | Standard for non-mainnet POC |
| `viaIR` | **off** by default | Faster compile during iteration; enable only if stack-too-deep occurs |

## 2. Toolchain

| Tool | Version (or floor) | Use |
|---|---|---|
| **Foundry** | latest (`foundryup`) | `forge` build/test, `anvil` local chain, `cast` rpc client |
| **forge-std** | 1.9+ | `Test`, `Script`, `console2`, cheatcodes |
| **OpenZeppelin Contracts** | 5.0+ | ERC20, Ownable, SafeERC20, ReentrancyGuard, Math |
| **slither** (optional) | latest | Static analysis pass before completion |
| **forge fmt** | built-in | Code formatting |

### Why Foundry over Hardhat
- POC is contract-and-test heavy; Foundry tests run 10-50× faster
- `vm.warp()` and time-travel cheatcodes are essential for epoch testing
- `forge script` natively supports the parameterised demo we want
- No JavaScript dependency tree to manage

## 3. Project Layout

```
projects/2026-06-retail-access-vault/
├── 00-brief.md
├── 01-requirements.md
├── 02-architecture/
│   ├── options.md
│   ├── decision.md          ← ADR
│   └── diagrams/            ← Mermaid sources + PNGs
├── 03-tech-stack.md
├── 04-estimation.md
├── 05-spec.md               ← final consolidated spec
├── project.json
└── code/                    ← Foundry project lives here
    ├── foundry.toml
    ├── remappings.txt
    ├── lib/                 ← forge-std, OZ via forge install
    ├── src/
    │   ├── Vault.sol
    │   ├── Custody.sol
    │   ├── interfaces/
    │   │   ├── IVault.sol
    │   │   └── ICustody.sol
    │   └── mocks/
    │       ├── MockUSDC.sol
    │       ├── MockPruv.sol
    │       ├── MockLiquidBuffer.sol
    │       └── MockAMM.sol
    ├── test/
    │   ├── Vault.t.sol             ← unit-style state machine tests
    │   ├── Custody.t.sol           ← custody operations
    │   ├── scenarios/
    │   │   ├── S1_HappyPath.t.sol
    │   │   ├── S2_LaunchpadFail.t.sol
    │   │   ├── S3_CancelPending.t.sol
    │   │   ├── S4_MatchSubGtRedeem.t.sol
    │   │   ├── S5_MatchRedeemGtSub.t.sol
    │   │   ├── S6_IlliquidFallback.t.sol
    │   │   ├── S7_NavChange.t.sol
    │   │   └── S8_WindDownMidEpoch.t.sol
    │   └── helpers/
    │       └── Fixture.sol          ← shared deploy + actors
    └── script/
        └── Demo.s.sol               ← parameterised demo (--scenario flag)
```

## 4. Dependencies

| Package | Why | Where used |
|---|---|---|
| `forge-std` | Test framework | All tests + script |
| `@openzeppelin/contracts` | ERC20, Ownable, ReentrancyGuard, SafeERC20, Math | Vault, Custody |

Install:
```
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts
```

## 5. Foundry Config (`foundry.toml`)

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.24"
optimizer = true
optimizer_runs = 200
remappings = [
  "forge-std/=lib/forge-std/src/",
  "@openzeppelin/=lib/openzeppelin-contracts/",
]
fuzz = { runs = 100 }      # POC is scenario-driven; fuzz is bonus
verbosity = 2

[profile.ci]
fuzz = { runs = 1000 }
```

## 6. Code Conventions

| Aspect | Rule |
|---|---|
| Naming | `PascalCase` for contracts/structs, `camelCase` for fns/vars, `UPPER_SNAKE` for constants |
| Error handling | Custom errors (`error InvalidState();`), no `require` with strings |
| Events | Every state mutation emits an event |
| NatSpec | All `external` and `public` functions have `///` docstrings |
| Reentrancy | `nonReentrant` on `claim()`, `refund()`, `withdrawUSDC()` |
| Math | OpenZeppelin `Math.mulDiv` for pro-rata calcs |
| Visibility | `external` over `public` where not called internally |
| Pragma | Fixed `pragma solidity 0.8.24;` (no `^`) |

## 7. Testing Approach

| Layer | What | Tooling |
|---|---|---|
| **Unit** | Each contract function in isolation | `Vault.t.sol`, `Custody.t.sol` |
| **Scenario** | Multi-step end-to-end flows (S1-S8) | `test/scenarios/*.t.sol` |
| **Property** (optional) | Invariants (e.g., `totalAssets ≥ totalShares × NAV`) | `forge test --match-test invariant_` |
| **Demo** | Parameterised script with colored output | `forge script Demo --sig 'run(string)' "S1"` |

### Time travel
Use `vm.warp(block.timestamp + delta)` for launchpad timing and epoch transitions.

### Test fixture
A `Fixture.sol` helper sets up:
- 3 named actors: `alice`, `bob`, `charlie` (via `makeAddr`)
- Deployed mocks with funded balances
- Deployed Vault + Custody
- Configured launchpad parameters

Each scenario inherits `Fixture` and writes assertions against the post-condition state.

## 8. Demo Script Design

Single `Demo.s.sol` with `--sig 'run(string)'`:

```bash
forge script Demo --sig 'run(string)' "S1" -vvv
forge script Demo --sig 'run(string)' "S4" -vvv
```

Each scenario branch in `run(scenarioId)`:
1. Deploys the fixture
2. Executes the scenario steps
3. Prints colored state diff using `console2.log` with ANSI escapes
4. Asserts invariants (deferred to test files; demo just shows)

Sample output target:

```
┌─ Scenario S4: Matching Sub > Redemption ─┐
│ Epoch 0:                                 │
│   Sub queue:    10,000 USDC              │
│   Redeem queue: 4,000 shares (= 4,000$)  │
│ Calling processEpoch()...                │
│   ✓ Matched 4,000 (P2P)                  │
│   ✓ Net sub 6,000 → custody buys 80/20   │
│   ✓ wRWA bought: 4,800$                  │
│   ✓ Liquid bought: 1,200$                │
│ Post-state:                              │
│   Alice shares: 9,803 (4k matched + …)   │
│   Bob: redeemed 4,000 USDC ✓             │
└──────────────────────────────────────────┘
```

## 9. Linting / Static Analysis

| Stage | Tool | When |
|---|---|---|
| Format | `forge fmt` | pre-commit |
| Lint | `solhint` (optional) | pre-commit |
| Static | `slither .` | end of Phase E |

## 10. CI

**Not required for POC.** If user wants, a single `forge test --gas-report` GitHub Action can be added in Phase E.

## 11. Open Tooling Questions

| # | Item | Default |
|---|---|---|
| T1 | Coverage tool? | `forge coverage` if requested |
| T2 | Gas snapshot tracking? | Skipped; not relevant to POC goal |
| T3 | Multiple Solidity versions? | No; pin to 0.8.24 |
| T4 | Deployment to testnet? | No; local only per scope §2.2 |
