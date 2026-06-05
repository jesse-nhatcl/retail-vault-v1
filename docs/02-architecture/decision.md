# ADR 001 — Vault + Custody Decomposition

**Status:** Accepted
**Date:** 2026-06-02
**Deciders:** User (tech lead) + research assistant
**Project:** retail-access-vault (local POC, Alt-1)

---

## Context

The Retail Access PRD describes a vault holding a mix of illiquid Pruv tokens (80-90%) and a liquid buffer (10-20%), accessed through ERC-7540-style async subscription/redemption queues with a matching layer. The PRD explicitly says assets are "locked in a custody". We need to decide how to decompose this into Solidity contracts for the local POC.

Three candidate decompositions were evaluated (see `options.md`):
- **A** — Monolithic single `Vault.sol`
- **B** — Two-contract split: `Vault.sol` (state) + `Custody.sol` (token holding)
- **C** — Three-contract modular: `Vault.sol` + `Custody.sol` + `StrategyManager.sol`

## Decision

**Adopt Option B — Vault + Custody decomposition.**

```
Vault.sol           Custody.sol
─────────           ───────────
State machine      Holds wRWA balance
Queues (sub/redeem) Holds liquid buffer balance
Matching algorithm Holds idle USDC
ERC-20 shares      Pruv subscribe/redeem
processEpoch()     Liquid buf swap
                   onlyVault gated
```

External mocks: `MockUSDC`, `MockPruv`, `MockLiquidBuffer`, `MockAMM`.

## Rationale

| Driver | Why this option wins |
|---|---|
| **PRD vocabulary fidelity** | "Vault" and "Custody" are PRD nouns; reviewers can point at code from PRD without vocab translation. |
| **Separation of concerns** | Vault owns state + accounting; Custody owns tokens + DeFi interactions. Mirrors real-world auditing patterns. |
| **Test isolation** | Vault state-machine tests can use `MockCustody`; Custody integration tests can mock Pruv/Liquid independently. |
| **Future-proof Alt-2** | Switching to Balancer-backed custody becomes "replace Custody implementation" — Vault untouched. |
| **No premature abstraction** | Option C's StrategyManager has only one strategy (rebalance to 80/20). YAGNI applies. |
| **Time fit** | ~6-7 day dev estimate matches the "local POC, prove mechanism" budget. |

## Alternatives considered

### Option A — Monolithic
**Rejected because:** Custody as a distinct concept disappears from code structure, even though PRD reader expects to see it. Saves only ~150 LOC.

### Option C — Vault + Custody + StrategyManager
**Rejected because:** With only one rebalance strategy required, the StrategyManager abstraction has no payoff. Adds ~400 LOC, ~2-3 days dev time, and an extra cross-contract hop in every flow. Reconsider if POC scope expands to L3 or production hand-off.

## Consequences

### Positive
- Clear PRD-to-code mapping for reviewers
- Easier unit tests for state-machine edge cases
- Custody contract becomes the natural replacement point for Alt-2 (Balancer) migration
- Auditable invariant: only Custody holds external tokens

### Negative
- One cross-contract call per buy/sell/swap (negligible gas cost in POC context)
- Slightly more deployment boilerplate (interface + modifier)

### Neutral
- Custody mock is a single-purpose object — tests must spin it up; counterbalanced by easier mocking

## Contract Inventory

| Contract | Type | Purpose | LOC est. |
|---|---|---|---|
| `Vault.sol` | Production | State machine, queues, matching, shares | ~500 |
| `Custody.sol` | Production | Token holding, Pruv/swap calls | ~250 |
| `MockUSDC.sol` | Mock | ERC-20 stablecoin (6 decimals) | ~30 |
| `MockPruv.sol` | Mock | Subscribe/redeem with admin-set price | ~80 |
| `MockLiquidBuffer.sol` | Mock | Yield-bearing ERC-20 (no actual yield in POC) | ~50 |
| `MockAMM.sol` | Mock | 1:1 swap between liquid buffer and USDC | ~60 |
| `IVault.sol` | Interface | Public API | ~50 |
| `ICustody.sol` | Interface | Vault → Custody surface | ~40 |
| **Total production code** | | | **~1,060** |

## Interfaces (locked at this ADR)

### `ICustody`

```solidity
interface ICustody {
  // Asset acquisition (Vault → Pruv via Custody)
  function subscribeToPruv(uint256 usdcAmount) external returns (uint256 wRWAReceived);
  function redeemFromPruv(uint256 wRWAAmount) external returns (uint256 usdcReceived);

  // Liquid buffer swap (1:1 in POC)
  function swapLiquidForUSDC(uint256 liquidAmount) external returns (uint256 usdcReceived);
  function swapUSDCForLiquid(uint256 usdcAmount) external returns (uint256 liquidReceived);

  // USDC movements (Vault deposits in, withdraws to pay users)
  function depositUSDC(uint256 amount) external;       // Vault → Custody
  function withdrawUSDC(address to, uint256 amount) external; // Custody → user

  // Read
  function wRWABalance() external view returns (uint256);
  function liquidBalance() external view returns (uint256);
  function usdcBalance() external view returns (uint256);
}
```

### `IVault` (public surface)

```solidity
interface IVault {
  enum State { Initialized, LaunchpadStart, LaunchpadFail, EpochBased, WindDown, Closed }

  // Setup
  function initLaunchpad(uint64 startTime, uint64 endTime, uint256 minAmount) external;
  function configAsset(address pruv, address liquidBuffer, uint16 illiquidBps) external;

  // Launchpad phase
  function depositToLaunchpad(uint256 amount) external;
  function transitionAfterDeadline() external;
  function claimLaunchpadShares() external;
  function refundLaunchpad() external;

  // Epoch phase — user actions (anytime)
  function requestDeposit(uint256 amount) external returns (uint256 requestId);
  function requestRedeem(uint256 shares) external returns (uint256 requestId);
  function cancelRequest(uint256 requestId) external;
  function claim(uint256 requestId) external;

  // Admin actions
  function processEpoch() external;             // Snapshot, match, settle delta
  function triggerWindDown() external;

  // Views
  function state() external view returns (State);
  function totalAssets() external view returns (uint256);
  function nav() external view returns (uint256);
  function pendingSubAmount(address user) external view returns (uint256);
  function pendingRedeemShares(address user) external view returns (uint256);
}
```

### Pruv mock contract (admin-driven price)

```solidity
contract MockPruv {
  uint256 public pricePerWRWA; // in USDC, scaled 1e18 / 1e18 (= 1.0 at deploy)

  function setPrice(uint256 newPrice) external onlyOwner;
  function subscribe(uint256 usdcAmount) external returns (uint256 wRWAOut);
  function redeem(uint256 wRWAAmount) external returns (uint256 usdcOut);
}
```

## Trust Boundary

```
┌─────────────────────────────────────────┐
│              External world             │
│  (users, admin EOA, mocks acting as     │
│   stand-ins for Pruv/Liquid)            │
└──────────┬──────────────────────────────┘
           │  public functions only
           ▼
┌─────────────────────────────────────────┐
│                Vault.sol                │
│   - State machine, queues, shares       │
│   - Calls Custody internally            │
└──────────┬──────────────────────────────┘
           │  onlyVault modifier
           ▼
┌─────────────────────────────────────────┐
│              Custody.sol                │
│   - Token operations only               │
│   - Calls external mocks                │
└─────────────────────────────────────────┘
```

Custody never accepts calls from EOAs. Vault is the sole authorised caller. This enforces the invariant that all asset moves flow through the state machine.

## Open implementation notes (for Phase E)

1. **Queue data structure**: arrays of `Request` structs + per-user index mapping. Requests not deleted on cancel; marked cancelled and skipped during epoch.
2. **Pro-rata share allocation**: requires fixed-point math (use mulDiv pattern; OpenZeppelin's `Math` library).
3. **Matching edge case**: when `subQueueUSDC == redeemQueueUSDC == 0`, epoch is a no-op (event emitted for observability).
4. **Wind-down time limit**: not specified in PRD. POC will use **30 days** after final settlement, after which leftover dust is locked (or burnt via admin call). Documented as deferred decision Q8 in `01-requirements.md`.
5. **Reentrancy**: protect `claim()`, `refund()`, `processEpoch()`, `withdrawUSDC()` with `nonReentrant` modifier (OpenZeppelin `ReentrancyGuard`).
