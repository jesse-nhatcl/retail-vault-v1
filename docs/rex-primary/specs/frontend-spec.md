# REX Primary — Frontend (dApp) Specification

The retail-facing dApp: what screens exist, what each shows, and the flows a user walks. Behavior is
driven by the contracts (`spec.md`) and read through the services API (`services-spec.md`).

> **Status honesty (answers "is FE documented, or do we need to discuss?"):** the **screens, states,
> and flows are specified below** (they follow directly from the PRD's user journeys and the
> contract lifecycle). The **stack and visual design are open** - see "Open questions" first. The FE
> can be fully built from this spec once those choices are made; nothing here is blocked on
> contracts.

---

## Open questions (need a decision before Phase 6 build)

| # | Question | Options | Default proposal |
|---|---|---|---|
| Q1 | Framework | Next.js/React · other | **Next.js + React** (ecosystem, wallet libs) |
| Q2 | Wallet connection | wagmi+viem · RainbowKit · Web3Modal | **wagmi + viem** (+ RainbowKit for the connect UI) |
| Q3 | Multi-chain UX | one home-chain app · surface the PRUV side too | **home-chain only** for retail; PRUV is internal plumbing they never see |
| Q4 | Design system | Tailwind+shadcn · MUI · custom | **Tailwind + shadcn** |
| Q5 | i18n | English only · EN + VI | decide with product (team is bilingual) |

These are look-and-stack decisions; the screens and states below do not depend on them.

---

## 1. Principles

- **Show the async truth.** Retail must always see whether a request is queued, in-flight (bridging),
  or claimable. Hiding the cross-chain delay creates support tickets and mistrust.
- **Preview before signing.** Every subscribe/redeem/cancel shows the exact wRWA/USDC out and fees
  (from the on-chain `preview*` via the API) before the user signs. No hidden fees (constitution
  Article 8).
- **Permissionless.** No KYC/login gate for retail (constitution Article 9). Wallet-connect only.
- **Home chain only.** Users transact in USDC and hold wRWA on the home chain; they never interact
  with PRUV directly.

## 2. Screens

### 2.1 Product / Subscribe

- Inputs: USDC amount. Shows current **NAV**, estimated **wRWA out**, and **fee** (preview).
- Action: `requestDeposit`. On success, shows the new request as **queued** with its receipt id.
- Guard: only in `EpochBased`; disabled with a clear reason otherwise (e.g. "in launchpad",
  "winding down").

### 2.2 Redeem

- Inputs: wRWA amount (from the user's wRWA balance). Shows NAV, estimated **USDC out**, and
  redemption **fee** (preview).
- Action: `requestRedeem`. On success, request shown as **queued**.

### 2.3 Portfolio / Requests

The heart of the async UX. Lists the user's requests with live status from the API:

| Column | Source |
|---|---|
| kind (subscribe/redeem), amount | request |
| status: queued / in-flight / claimable / claimed / cancelled | derived (services-spec §4) |
| action | **Cancel** (if queued), **Claim** (if claimable), else none |

Also shows the user's **wRWA balance** (their actual holding) and current **NAV**.

### 2.4 Cancel

- Available while a request is **queued** (before its epoch initiates).
- Shows the refund amount; for a subscribe, shows the **cancellation fee** deducted (preview).
- Action: `cancelRequest`.

### 2.5 Claim

- Available when a request is **claimable** (its epoch settled).
- Shows the payout (wRWA for a subscribe, USDC for a redeem).
- Action: `claim`.

### 2.6 Launchpad

- Only during `LaunchpadStart`. Shows: amount **gathered vs minimum**, **countdown** to close, the
  user's deposited amount.
- Action: `depositToLaunchpad`.
- After close: if success, **Claim wRWA** (`claimLaunchpad`); if fail, **Refund USDC**
  (`refundLaunchpad`). The UI reflects which, from `LaunchpadClosed(success)`.

### 2.7 Wind-down

- Shown when state is `WindDown`/`Closed`. Explains subscriptions are closed; surfaces any pending
  redemption obligations still settling; lets users **claim** settled payouts.
- Notes clearly that retail-held wRWA is unaffected and remains theirs.

## 3. State-driven availability

| Lifecycle state | Subscribe | Redeem | Cancel | Claim | Launchpad | Refund |
|---|---|---|---|---|---|---|
| Initialized | off | off | off | off | off | off |
| LaunchpadStart | off | off | (launchpad cancel) | off | **on** | off |
| LaunchpadFail | off | off | off | off | off | **on** |
| EpochBased | **on** | **on** | on (queued) | on (claimable) | off | off |
| WindDown | off | (final window if configured) | off | on (claimable) | off | on (pending subs) |
| Closed | off | off | off | on (residual) | off | off |

## 4. In-flight communication

When a user's request is **in-flight**, the UI must explain: "Your epoch is settling across chains;
this typically takes about [latency from Phase 0 T0.2]. Your payout will be claimable once it
completes." Show a non-blocking progress indicator driven by the bridge message status from the API,
never a fake spinner that implies instant settlement.

## 5. Non-goals

No secondary trading of receipts (receipts are non-transferable, ADR-006). No PRUV-side UI for
retail. No portfolio analytics beyond holdings + request status in the first release.
