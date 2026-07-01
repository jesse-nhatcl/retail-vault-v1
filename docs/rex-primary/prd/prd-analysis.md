# PRD Analysis — What REX Primary Builds

A faithful reading of the `PRD REX Primary`, the interpretation decisions it forces, and how the
production design maps to it. Grounded in the PRD; the POC is referenced only to mark where we
deliberately diverge.

---

## 1. What the PRD wants

REX Primary markets a tokenized **Evergreen Private Credit** fund (Pruv Finance) to retail, so many
small investors can jointly reach the fund's minimum ticket, gain exposure, and exit back to
stablecoin - **without the company fronting its own liquidity**.

**Objectives (verbatim intent):**

1. Market the token ourselves, not dependent on web3 foundations.
2. Solve **early redemption** for retail **without using our own liquidity**.
3. Reach the **minimum ticket size** required by the private fund.

**Three functions:** Group Subscription (pool USDC, subscribe to Pruv at epoch, distribute wRWA),
Group Redemption (pool wRWA, redeem at Pruv, distribute USDC), and Matching (net the two, only the
delta hits Pruv).

**Why queue/epoch (PRD's two stated reasons):** (1) to wait for the underlying asset's
**subscription window**, and (2) to **aggregate small subscriptions** to fulfill the fund's minimum
subsequent subscription. These are the product rationale behind the epoch batching and the minimum
ticket.

**Five states:** `Initialized → LaunchpadStart → (LaunchpadFail | EpochBased) → WindDown`.

**Admin inputs to launch:** fund asset address, stablecoin, launchpad start, launchpad duration,
minimum amount, epoch period.

**Fees:** subscription cancellation fee, redemption fee.

## 2. The interpretation the PRD forces

The PRD is explicit on one point and self-contradictory on another. Both are resolved here (and in
ADRs), so implementers never guess.

### 2.1 Retail hold wRWA, not a share (resolved: yes)

Four independent PRD statements say retail receive and hold the **wrapped RWA token**:

- Group Redemption "pools the **wRWAToken** from retail investors who want to exit" - so retail
  hold wRWA to begin with.
- Launchpad: holders "receive **receipt token but not a vault token**"; the receipt is used "to
  **claim the wrapped RWA token**."
- Group Subscription: return is **wRWA Token**, explicitly "**without issuing a vault token**"; the
  RWA is "**bridged over to the chain where the dApp is as a wrapped token**" and "distributed to the
  retail investor."

The **§Matching** section contradicts this by using the words "vault token" and "liquid asset in
custody." That is legacy 4626-vault phrasing, not a second design. The **same custody/vault-token
framing** reappears in the Matching "Redemption > Subscription" case ("6,000 USDC worth of vault
token will be burned... swapping the liquid asset in custody") and in **§Wind-down** ("liquid/illiquid
assets inside the vault", "redeem their vault token"). All three are superseded together. **David
Kurniawan confirmed:** "bridge back the wRWA and distribute it to the buyers, so no more custody."
Resolution recorded in `../decisions/ADR-002-no-vault-token.md` and
`../decisions/ADR-003-no-custody-retail-holds-wrwa.md`; the wind-down mapping is in `../specs/spec.md` §7.7.

### 2.2 What "subscribe via Pruv" concretely means

The PRD leaves the Pruv interface abstract. The Pruv examples (captured in-folder at
[`references/pruv-interface.md`](../references/pruv-interface.md)) fill it in:
Pruv's `RWAToken` is a standard **ERC-4626** vault - subscribe = `deposit(assets, receiver)`,
redeem = `redeem(shares, receiver, owner)`, synchronous. NAV is a separate contract
(`RWAConversion.value()`, 18-decimal). Fees are `RWAFee.feeOnRaw`/`feeOnTotal`. Access is gated by
an ERC-1155 `Whitelist` (token id 1). This is what makes the aggregator model necessary: retail
cannot each be whitelisted, so one KYC'd executor holds the position and retail get permissionless
exposure through the bridged wRWA.

## 3. Mapping PRD → production design

| PRD element | Production design |
|---|---|
| Group Subscription (pool USDC, subscribe at epoch, distribute) | Home-chain queue → `initiateEpoch` matching → bridge net USDC → `PruvExecutor.deposit` → bridge wRWA back → distribute per receipt |
| Group Redemption (pool wRWA, redeem at epoch, distribute) | Home-chain queue → matching → bridge net wRWA → `PruvExecutor.redeem` → bridge USDC back → distribute per receipt |
| Matching (net, delta to Pruv) | Net USDC-sub vs wRWA-redeem at oracle NAV; matched portion settles P2P (raw token transfer); only delta bridges. PRD's 10k/4k example is acceptance scenario RS4. |
| 5 states | Same lifecycle, plus in-flight sub-states for async settlement (see `../specs/spec.md`). |
| NAV "updated value on epoch" | Oracle: `RWAConversion.value()` relayed to `NavOracleConsumer`, with staleness + sanity guards. |
| Fees (cancel, redeem) | `FeeModule` on the home chain; Pruv's own entry/exit fees borne only by the net delta. |
| Wind-down | Disable subs, refund pending, settle redemption queue via Pruv; retail-held wRWA untouched. |
| Bridge to/from Pruv Network | Hyperlane warp routes: USDC (home↔PRUV) and wRWA (PRUV↔home). |

## 4. POC delta (what changes vs `retail-access-vault`)

The POC and REX Primary share the lifecycle, the request/queue/cancel pattern, and net-delta
matching. They differ fundamentally elsewhere. This table is the guardrail against porting POC
assumptions that no longer hold.

| Dimension | POC | REX Primary |
|---|---|---|
| What retail hold | REX-issued vault share (18-dec), a claim on a pooled portfolio | The bridged **wRWA** itself |
| Custody | `Custody.sol` holds wRWA + liquid buffer + idle USDC | **None**; funds only transiently in-flight |
| NAV | Manual `MockPruv.setPrice` | **Oracle** relayed from `RWAConversion` |
| Matching settlement | Mint/burn shares against matched USDC | **Raw token transfer** (wRWA ↔ USDC), no mint/burn |
| Liquidity buffer / 3-layer redemption | 20% liquid sleeve, rebalance-to-80/20 | **Removed** (no custody to hold it); redemption is match → Pruv |
| Chains | Single Anvil chain, synchronous | **Two chains**, async bridge |
| Pruv | On-chain mock, same chain | Real ERC-4626 on PRUV, reached via bridge + `PruvExecutor` |
| Decimals | shares 18-dec alongside 6-dec tokens (main bug source) | No share dimension; real tokens only |
| Trust surface | One custody honeypot | No home-chain honeypot; new surface = bridge + executor + messaging |

**Consequence to flag for stakeholders:** removing the buffer removes the POC's *instant* exit path
for the unmatched portion. Unmatched redemptions must bridge to Pruv and wait for the async
round-trip. This is a deliberate trade for simplicity and "no custody"; if instant exit is required
later, it is a separate design (an OTC-style peer market, as the POC explored) and needs its own ADR.

## 5. Open questions

| Question | Status | Tracked in |
|---|---|---|
| §Matching "vault token": wording error or real share? | Assumed wording error (no vault token). Awaiting David's final word. | ADR-002 |
| Does a warp route for wRWA to the home chain exist, or must we deploy one? | Research | dev-plan Phase 0 (T0.2) |
| Wind-down: force-redeem retail-held wRWA, or leave it with them? | Spec decision: leave it; only settle the queue | ../specs/spec.md §Wind-down |
