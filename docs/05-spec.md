# 05 — Final Spec: retail-access-vault (Local POC)

**Project:** retail-access-vault
**Status:** Spec ready for implementation
**Date:** 2026-06-02
**Source PRD:** PRD Retail Access (Alt-1)
**Architecture:** ADR 001 — Vault + Custody

> **Reading order for new engineers:** This document is self-contained. You do **not** need to read `00-brief.md` through `04-estimation.md` to start implementing. Those exist as the audit trail for how each decision was made. Reach for them only if a clarification request requires "why".

---

## 1. Executive Summary

Build a local proof-of-concept demonstrating the **mechanism** of Alt-1 from the Retail Access PRD: an ERC-7540-style async vault that wraps an illiquid private credit fund (Hamilton Lane Evergreen, simulated as `MockPruv`) along with a liquid buffer (~20%), offering retail investors permissionless subscription and redemption via a queue + matching + 3-layer redemption protocol.

**Goal:** Prove the mechanism logic — state transitions, queue math, P2P matching, 3-layer fallback — works coherently on a single Anvil chain with mock external dependencies.

**Non-goals:** Not a product. No mainnet. No bridge. No frontend. No real Pruv API. No audit hardening.

**Success criteria:**
1. All 8 test scenarios pass via `forge test`
2. Demo script renders human-readable output for any scenario via `forge script Demo --sig 'run(string)' "S<n>"`
3. State machine invariants hold across all flows
4. Total LOC (production + tests) under 2,000

---

## 2. Context (1-page recap)

### What problem this solves
Hamilton Lane Evergreen (and similar private credit funds) have:
- High ticket minimums (e.g., $100k+) → out of reach for retail
- Periodic subscription/redemption windows → not always-on liquidity
- Limited primary distribution channels

Retail Access Vault sits in front: pools retail USDC, hits the minimum ticket, holds the wrapped position in custody, mints transferable share tokens. A liquid buffer (~20%) absorbs typical redemption pressure; only when the buffer is exhausted does the protocol redeem from the underlying illiquid position.

### Why Alt-1 over Alt-2
| | Alt-1 (chosen) | Alt-2 |
|---|---|---|
| Custody | Self-built contract | Balancer pool ETF token |
| `totalAssets()` | Sum of held assets via NAV oracle | Balancer ETF price |
| Complexity | Medium | Higher (Balancer integration) |
| Reasonability of POC | Direct, traceable | Wrapped in 3rd-party |

Alt-1 is the cleaner POC subject — Custody is something we own and can reason about end-to-end.

---

## 3. Architecture

### 3.1 Contract topology

```
┌─────────────────────────────────────┐
│           Vault.sol                 │
│  State, queues, matching, shares    │
└────────────┬────────────────────────┘
             │ controls (onlyVault)
             ▼
┌─────────────────────────────────────┐
│           Custody.sol               │
│  Holds wRWA, liquid, idle USDC      │
└────────────┬────────────────────────┘
             ▼
   [MockUSDC, MockPruv, MockLiquidBuffer, MockAMM]
```

Full architecture diagram: `02-architecture/diagrams/system-arch.png`.

### 3.2 Trust boundaries

- **External world** (users, admin) → calls Vault public functions only
- **Vault** → only caller authorised to call Custody
- **Custody** → only caller authorised to move tokens in/out of mocks

### 3.3 Why this decomposition

- Custody is a PRD noun — putting it in a separate contract matches reviewer mental model
- Vault state machine can be unit-tested with a `MockCustody`
- Future Alt-2 migration = swap Custody implementation, Vault untouched

---

## 4. State Machine

State diagram source: `02-architecture/diagrams/state-machine.png`.

```
[*] → Initialized → LaunchpadStart → ┬→ EpochBased → WindDown → Closed
                                     └→ LaunchpadFail
```

| State | Entry trigger | Exit trigger | Allowed operations |
|---|---|---|---|
| `Initialized` | `constructor` | `launchpadStartTime` reached | Admin: `initLaunchpad`, `configAsset` |
| `LaunchpadStart` | Time-based | `launchpadEndTime` reached | Users: `depositToLaunchpad`. Anyone: `transitionAfterDeadline` |
| `LaunchpadFail` | min not met at end | (terminal except refunds) | Users: `refundLaunchpad` |
| `EpochBased` | min met at end | Admin: `triggerWindDown` | Users: `requestDeposit`, `requestRedeem`, `cancelRequest`, `claim`. Admin: `processEpoch`, `setPrice` on Pruv |
| `WindDown` | Admin | All redemptions settled | Users: `claim` only. Admin: continue settlement |
| `Closed` | Settlement complete | (terminal) | None |

State transitions are **one-way**. No reverse paths.

---

## 5. Public API (Vault.sol)

### 5.1 Setup (admin)

```solidity
function initLaunchpad(uint64 startTime, uint64 endTime, uint256 minAmount) external onlyOwner;
function configAsset(address pruv, address liquidBuffer, address mockAmm, uint16 illiquidBps) external onlyOwner;
```

- `initLaunchpad` callable only in `Initialized` state
- `configAsset` callable only in `Initialized` state; `illiquidBps` in basis points (8000 = 80%)
- Both inputs frozen once state advances past `Initialized`

### 5.2 Launchpad phase

```solidity
function depositToLaunchpad(uint256 amount) external nonReentrant;
function transitionAfterDeadline() external;  // permissionless
function claimLaunchpadShares() external nonReentrant;
function refundLaunchpad() external nonReentrant;
```

- `depositToLaunchpad`: only callable in `LaunchpadStart` state. Pulls USDC. Updates `launchpadDeposits[msg.sender] += amount` and `totalLaunchpadLocked += amount`.
- `transitionAfterDeadline`: permissionless. Only callable after `launchpadEndTime`. Branches to `EpochBased` (success path: vault calls `Pruv.subscribe(totalLocked)` via Custody to acquire wRWA + buys liquid buffer per target ratio) or `LaunchpadFail`.
- `claimLaunchpadShares`: only callable in `EpochBased`. Mints shares pro-rata based on `launchpadDeposits[user] / totalLaunchpadLocked × totalSupply`. **First epoch only.**
- `refundLaunchpad`: only callable in `LaunchpadFail`. Returns USDC.

### 5.3 Epoch phase

```solidity
struct Request {
  address user;
  uint256 amount;     // USDC for sub, shares for redeem
  uint64 epochSubmitted;
  bool fulfilled;
  bool cancelled;
}

function requestDeposit(uint256 amount) external nonReentrant returns (uint256 requestId);
function requestRedeem(uint256 shares) external nonReentrant returns (uint256 requestId);
function cancelRequest(uint256 requestId) external nonReentrant;
function claim(uint256 requestId) external nonReentrant;
```

- `requestDeposit`: pulls USDC into Vault, appends to `subQueue`, emits `DepositRequested(user, id, amount, epoch)`
- `requestRedeem`: locks shares (transfer to Vault), appends to `redeemQueue`, emits `RedeemRequested`
- `cancelRequest`: caller must own request, request must be unfulfilled and uncancelled, request must belong to current pending epoch. Refunds USDC or shares accordingly. Emits `RequestCancelled`.
- `claim`: only after `processEpoch` has stamped the request's epoch. Pays out USDC (for redeem requests) or mints shares (for deposit requests). Emits `Claimed`.

### 5.4 Admin / settlement

```solidity
function processEpoch() external onlyOwner nonReentrant;
function triggerWindDown() external onlyOwner;
```

See §6 for `processEpoch` algorithm. `triggerWindDown` is one-way.

### 5.5 Views

```solidity
function state() external view returns (State);
function totalAssets() external view returns (uint256);   // value in USDC, 6 decimals
function nav() external view returns (uint256);           // scaled 1e18
function pendingSubAmount(address user) external view returns (uint256);
function pendingRedeemShares(address user) external view returns (uint256);
function currentEpoch() external view returns (uint64);
```

---

## 6. `processEpoch` Algorithm (CORE)

This is the heart of the protocol. Reference flow: `02-architecture/diagrams/process-epoch-sequence.png`.

### 6.1 Pseudocode

```
function processEpoch():
  require(state == EpochBased)

  # Step 0: NAV assumed updated externally (admin called pruv.setPrice)
  # Snapshot variables (read-only this step)
  navNow = totalAssets() * 1e18 / totalSupply()
  subPending = sum(subQueue where !cancelled and !fulfilled and epoch == currentEpoch)
  redeemShares = sum(redeemQueue where !cancelled and !fulfilled and epoch == currentEpoch)
  redeemValueUSDC = redeemShares * navNow / 1e18

  # Step 1: Matching
  matchedUSDC = min(subPending, redeemValueUSDC)
  matchedShares = matchedUSDC * 1e18 / navNow

  # Allocate matched shares to subscribers pro-rata
  for each unfulfilled sub request:
    userMatched = request.amount * matchedUSDC / subPending
    record fulfillment[id] = { sharesAcquired: userMatched * 1e18 / navNow, usdcConsumed: userMatched }

  # Allocate matched USDC to redeemers pro-rata
  for each unfulfilled redeem request:
    userMatched = request.amount * matchedShares / redeemShares
    record fulfillment[id] = { usdcAcquired: userMatched * navNow / 1e18, sharesBurned: userMatched }

  # Burn matched shares (held by vault on redeemer's behalf)
  totalSupply -= matchedShares  # already-locked redeem shares are burnt here

  # Step 2: Settle net delta
  netSubUSDC = subPending - matchedUSDC
  netRedeemUSDC = redeemValueUSDC - matchedUSDC

  if netSubUSDC > 0:
    # Buy assets per rebalance-toward-target
    (buyIlliquidUSDC, buyLiquidUSDC) = computeRebalanceBuy(netSubUSDC)
    custody.subscribeToPruv(buyIlliquidUSDC)
    custody.swapUSDCForLiquid(buyLiquidUSDC)
    # Mint additional shares pro-rata to net-sub portion of remaining sub requests
    additionalSharesTotal = netSubUSDC * 1e18 / navNow
    for each unfulfilled sub request:
      userNet = request.amount - fulfillment[id].usdcConsumed
      additionalShares = userNet * 1e18 / navNow
      fulfillment[id].sharesAcquired += additionalShares
    totalSupply += additionalSharesTotal
    # USDC for the net sub goes from Vault to Custody before subscribeToPruv

  elif netRedeemUSDC > 0:
    # 3-layer sourcing
    remaining = netRedeemUSDC

    # Layer 2: liquid buffer
    liquidAvail = custody.liquidBalance()  # already in USDC-equivalent at 1:1
    take = min(remaining, liquidAvail)
    if take > 0:
      custody.swapLiquidForUSDC(take)
      remaining -= take

    # Layer 3: illiquid
    if remaining > 0:
      wrwaToRedeem = remaining * 1e18 / pruvPrice
      custody.redeemFromPruv(wrwaToRedeem)
      # may return less than `remaining` if Pruv mock partially fulfills — POC assumes full fulfillment
      remaining = 0  # POC simplification; rollover documented as edge case

    # Distribute USDC to redeem requests pro-rata
    for each unfulfilled redeem request:
      userNetShares = request.amount - fulfillment[id].sharesBurned
      userNetUSDC = userNetShares * navNow / 1e18
      fulfillment[id].usdcAcquired += userNetUSDC
      fulfillment[id].sharesBurned += userNetShares
    totalSupply -= (redeemShares - matchedShares)

  # Step 3: Mark queue as processed
  emit EpochProcessed(currentEpoch, navNow, matchedUSDC, netSubUSDC, netRedeemUSDC)
  currentEpoch += 1

  # User now calls `claim(requestId)` to actually withdraw their shares/USDC
```

### 6.2 Rebalance-toward-target formula

```
function computeRebalanceBuy(netSubUSDC):
  totalAssetsAfter = totalAssets() + netSubUSDC
  targetIlliquidUSDC = totalAssetsAfter * illiquidBps / 10000
  targetLiquidUSDC = totalAssetsAfter * (10000 - illiquidBps) / 10000

  currentIlliquidUSDC = custody.wRWABalance() * pruvPrice / 1e18
  currentLiquidUSDC = custody.liquidBalance()  # 1:1

  buyIlliquid = max(0, targetIlliquidUSDC - currentIlliquidUSDC)
  buyLiquid = max(0, targetLiquidUSDC - currentLiquidUSDC)

  # If sum exceeds netSubUSDC (rare with 1:1 mocks), scale down proportionally
  total = buyIlliquid + buyLiquid
  if total > netSubUSDC:
    buyIlliquid = buyIlliquid * netSubUSDC / total
    buyLiquid = buyLiquid * netSubUSDC / total
  elif total < netSubUSDC:
    # Excess goes to illiquid (or split arbitrarily — POC choice)
    buyIlliquid += (netSubUSDC - total)

  return (buyIlliquid, buyLiquid)
```

### 6.3 Implementation tips

- Use `Math.mulDiv` from OpenZeppelin for all pro-rata calcs (avoids overflow)
- Bound queue iteration: cap requests per epoch (e.g., 100) to avoid out-of-gas
- Cancelled requests stay in queue but are skipped in iteration
- Emit events before state mutations for easier debugging
- Use named events: `MatchingPerformed(uint256 matchedUSDC, uint256 matchedShares)`, `NetSubSettled(...)`, `NetRedeemSettled(...)`

---

## 7. Wind-Down Sequence

```
triggerWindDown():
  require(state == EpochBased)
  state = WindDown
  emit WindDownTriggered()

  # 1. Refund pending sub queue
  for each unfulfilled sub request in subQueue:
    if !cancelled:
      transfer USDC back to user
      mark cancelled
  emit PendingSubsRefunded(totalRefunded)

  # 2. Liquidate all liquid buffer
  liquidBalance = custody.liquidBalance()
  custody.swapLiquidForUSDC(liquidBalance)
  emit LiquidBufferLiquidated(liquidBalance)

  # 3. Settle redeem queue with USDC from steps 1+2
  availableUSDC = custody.usdcBalance()
  redeemPaid = 0
  for each unfulfilled redeem request:
    payout = request.amount * navNow / 1e18
    if availableUSDC >= payout:
      custody.withdrawUSDC(user, payout)
      mark fulfilled
      availableUSDC -= payout
      redeemPaid += payout
      totalSupply -= request.amount
    else:
      break  # need more USDC from illiquid

  # 4. Liquidate illiquid (if redeem queue not settled)
  if redeem queue has unfulfilled:
    custody.redeemFromPruv(all wRWA holdings)
    repeat redemption distribution until queue empty

  # 5. Final stable claim period (30 days from this point)
  # Any remaining vault token holders can call `claim` to pro-rata distribute remaining USDC
  # After 30 days, admin can `closePool()` to terminate
```

---

## 8. Configuration Defaults

| Config | Value | Source |
|---|---|---|
| Launchpad period (default) | 7 days | Reqs §6 |
| Launchpad minimum (default) | 50,000 USDC | Reqs §6 |
| Target asset ratio (illiquid) | 8000 bps (80%) | PRD example |
| Vault token decimals | 18 | Standard |
| USDC mock decimals | 6 | Match real USDC |
| Pruv price decimals | 18 (price scaling) | Implementation convention |
| Wind-down final claim period | 30 days | Reqs §9 default |
| Max requests per epoch | 100 (iteration bound) | Gas safety |

All configurable at deploy; only the launchpad ones are user-facing per PRD.

---

## 9. Test Scenarios (8)

All scenarios use the same fixture: 3 actors (Alice, Bob, Charlie) with funded MockUSDC balances.

### S1 — Happy Path Full Lifecycle
| Step | Action | Expected |
|---|---|---|
| 1 | Deploy + configure (min=50k, ratio=80/20) | state=Initialized |
| 2 | warp to launchpad start | state→LaunchpadStart |
| 3 | Alice 30k, Bob 30k, Charlie 40k deposit | totalLocked=100k |
| 4 | warp past end | |
| 5 | transitionAfterDeadline | state→EpochBased, custody=80k wRWA + 20k liquid, totalSupply=100k |
| 6 | Alice requestDeposit(10k) | subQueue has 1 request |
| 7 | Bob requestRedeem(5k shares) | redeemQueue has 1 request |
| 8 | admin processEpoch (NAV unchanged) | matched 5k, Alice gets 5k matched shares + 5k new shares, Bob 5k USDC |
| 9 | Alice & Bob claim | balances updated |
| 10 | admin triggerWindDown | state→WindDown, settle all |
| 11 | Final state | state=Closed (after 30d) or pending claim |

**Assert:** totalAssets ≥ pending obligations at every step; final share supply = 0.

### S2 — Launchpad Fail + Refund
| Step | Action | Expected |
|---|---|---|
| 1 | Deploy + configure (min=50k) | |
| 2 | warp to launchpad start | |
| 3 | Alice 30k deposit | totalLocked=30k |
| 4 | warp past end | |
| 5 | transitionAfterDeadline | state→LaunchpadFail |
| 6 | Alice refundLaunchpad | Alice USDC restored, custody empty |

### S3 — ERC-7887 Cancel Pending Sub
| Step | Action | Expected |
|---|---|---|
| 1 | Reach EpochBased | |
| 2 | Alice requestDeposit(10k) | subQueue has 1 |
| 3 | Alice cancelRequest(0) | USDC refunded, subQueue empty |
| 4 | admin processEpoch | no-op |

### S4 — Matching: Sub > Redemption (PRD Case 1)
| Setup | Vault has 80k wRWA + 20k liquid, totalSupply=100k, NAV=1.0 |
|---|---|
| 1 | Alice requestDeposit(10,000) |
| 2 | Bob requestRedeem(4,000 shares) |
| 3 | admin processEpoch |
| Expected | matched=4,000 USDC. Bob gets 4,000 USDC. Alice gets 4,000 matched shares + 6,000 net-sub shares = 10,000 shares total. Custody buys 6,000 USDC of assets (rebalance-aware split). |

### S5 — Matching: Redemption > Sub (PRD Case 2)
| Setup | Vault has 80k wRWA + 20k liquid, totalSupply=100k, NAV=1.0 |
|---|---|
| 1 | Alice requestDeposit(4,000) |
| 2 | Bob requestRedeem(10,000 shares) |
| 3 | admin processEpoch |
| Expected | matched=4,000. Alice gets 4,000 shares. Bob gets 4,000 USDC from match + 6,000 USDC from liquid buffer (sufficient). Bob's 10,000 shares burnt. |

### S6 — Redemption Needs Illiquid Fallback
| Setup | Drain custody to 2k liquid, 90k wRWA (somehow earlier scenarios got buffer low) |
|---|---|
| 1 | Alice requestRedeem(8,000 shares) |
| 2 | admin processEpoch |
| Expected | Layer 2 takes 2,000 liquid. Layer 3 takes 6,000 USDC worth of wRWA (Pruv redeem). Alice gets 8,000 USDC. |

### S7 — NAV Change Affects Calcs
| Setup | totalSupply=100k, totalAssets=100k, NAV=1.0 |
|---|---|
| 1 | admin Pruv.setPrice(1.1 × 1e18) — wRWA appreciates 10%; totalAssets now 108k (80k × 1.1 + 20k); NAV = 1.08 |
| 2 | Alice requestRedeem(10 shares) |
| 3 | admin processEpoch |
| Expected | Alice receives 10 × 1.08 = 10.8 USDC. |

### S8 — Wind-Down Mid-Epoch
| Setup | EpochBased, sub queue 5k, redeem queue 5 shares |
|---|---|
| 1 | admin triggerWindDown |
| Expected | (a) sub queue refunded. (b) liquid liquidated. (c) redeem queue settled. (d) illiquid liquidated if needed. (e) state→Closed eventually. |

---

## 10. Demo Script

File: `code/script/Demo.s.sol`

Invocation:
```
forge script script/Demo.s.sol --sig 'run(string)' "S4" -vvv
```

Behavior:
1. Deploys fixture (mocks + Vault + Custody)
2. Branches on scenario ID (`S1` .. `S8`)
3. Executes scenario steps, calling `console2.log` with ANSI escape codes for color
4. Prints before/after state diffs at each step
5. Asserts key invariants inline (e.g., `totalAssets >= totalObligations`)

Sample output (target):

```
┌────────────────────────────────────────────┐
│   Scenario S4: Matching Sub > Redemption  │
├────────────────────────────────────────────┤
│ INITIAL                                    │
│   Custody: 80,000 wRWA + 20,000 liquid     │
│   Vault:   totalSupply=100,000             │
│   NAV:     1.00                            │
│                                            │
│ STEP 1: Alice requestDeposit(10,000)       │
│   ✓ Sub queue: 1 request                   │
│                                            │
│ STEP 2: Bob requestRedeem(4,000 shares)    │
│   ✓ Redeem queue: 1 request                │
│                                            │
│ STEP 3: admin processEpoch()               │
│   ✓ Matched 4,000 USDC P2P                 │
│     → Bob: +4,000 USDC, -4,000 shares      │
│     → Alice: +4,000 matched shares         │
│   ✓ Net sub 6,000 USDC → custody           │
│     → buyIlliquid: 4,800 (rebalance)       │
│     → buyLiquid:   1,200                   │
│     → Alice: +6,000 net-sub shares         │
│                                            │
│ FINAL                                      │
│   Alice shares: 10,000                     │
│   Bob shares:   0  (USDC: 4,000 ✓)         │
│   Custody:      84,800 wRWA + 21,200 liq   │
│                                            │
│ INVARIANTS                                 │
│   ✓ totalAssets (106,000) >= obligations   │
│   ✓ NAV consistent                         │
└────────────────────────────────────────────┘
```

---

## 11. Tech Stack Recap

| Item | Choice |
|---|---|
| Language | Solidity 0.8.24 |
| Toolchain | Foundry (forge, anvil) |
| Libs | OpenZeppelin v5 (ERC20, Ownable, ReentrancyGuard, Math, SafeERC20) |
| Test framework | forge-std |
| Layout | `code/src/`, `code/test/scenarios/`, `code/script/` |

Full details: `03-tech-stack.md`.

---

## 12. Estimation Recap

| Item | Estimate |
|---|---|
| Most-likely | 7 working days |
| P90 (risk-adjusted) | 9.5 days |
| Total LOC | ~1,750 |

Risk register & WBS: `04-estimation.md`.

---

## 13. Out-of-Scope (will NOT be implemented in this POC)

- Cross-chain bridge logic
- Aave reinvest of idle USDC
- Curve swap formula research
- Frontend / UI
- Real Pruv API integration
- Role-based access control (single owner only)
- Linear NAV accrual / oracle (manual `setPrice` only)
- ERC-4626 full compliance
- Gas optimisation pass
- Security audit
- Mainnet/testnet deployment
- Fee model (perf/mgmt/redemption fees) — all 0%

---

## 14. Diagrams Index

| Diagram | File |
|---|---|
| System architecture | `02-architecture/diagrams/system-arch.png` |
| State machine | `02-architecture/diagrams/state-machine.png` |
| `processEpoch` sequence | `02-architecture/diagrams/process-epoch-sequence.png` |

Source `.mmd` files in same directory.

---

## 15. Glossary

| Term | Definition |
|---|---|
| **Vault** | The main contract retail users interact with |
| **Custody** | Sister contract that holds wRWA + liquid buffer; controlled only by Vault |
| **wRWA** | Wrapped RWA token issued by Pruv mock; the illiquid asset |
| **Liquid Buffer** | Yield-bearing ERC-20 mock representing the ~20% liquid sleeve |
| **Receipt (launchpad)** | Internal non-transferable balance tracking USDC locked during launchpad |
| **Epoch** | Processing window; ends when `processEpoch()` is called |
| **NAV** | Net Asset Value per share = `totalAssets / totalSupply` |
| **Matching** | P2P netting of subscription vs redemption queues at epoch boundary |
| **3-layer redemption** | (1) Matching → (2) Liquid buffer → (3) Illiquid Pruv redeem |
| **Rebalance-toward-target** | When buying new assets, prefer the under-allocated sleeve to push back to 80/20 |
| **ERC-7540** | Async deposit/redeem vault standard; we implement the mechanism, not full EIP |
| **ERC-7887** | Cancel-pending-request pattern; we implement basic cancel |

---

## 16. Deferred Items (open for later)

See `01-requirements.md §9`. Summary:

| Q | Item | When to revisit |
|---|---|---|
| Q1 | Curve swap formula | Phase 2 — real liquidity layer |
| Q2 | Aave reinvest | Phase 2 — yield optimisation |
| Q3 | Cross-chain bridge | When integrating real Pruv |
| Q4 | Real Pruv API shape | When Pruv testnet endpoint available |
| Q5 | NAV oracle | Production-only |
| Q6 | Fee model | After mechanism validated |
| Q7 | ERC-4626 compatibility | If ecosystem integration needed |
| Q8 | Partial redemption rollover semantics | Edge case for production |

---

## 17. Approval Checklist (sign-off to start implementation)

Before opening any `.sol` file, confirm:

- [ ] All 8 scenarios in §9 match user expectation (numeric outcomes especially S4/S5)
- [ ] `processEpoch` pseudocode in §6.1 matches intended semantics
- [ ] Rebalance-toward-target formula in §6.2 is correct
- [ ] Wind-down sequence in §7 is correct
- [ ] Architecture (Vault + Custody, no StrategyManager) is committed
- [ ] Estimation envelope (7-9.5 days) is acceptable
- [ ] Out-of-scope list (§13) accepted

Reply **"approve E, start coding"** to begin implementation.

Or specify edits.
