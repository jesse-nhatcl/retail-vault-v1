# REX Primary PRD

> **This is the source of truth.** Faithful transcription of `PRD REX Primary` (the original product
> requirements document), reproduced here so this documentation folder is self-contained. Where any
> other document in this folder disagrees with this PRD, this PRD wins unless an ADR in `../decisions/`
> explicitly overrides it. Editorial notes added by engineering are clearly marked `[eng note]` and
> are not part of the original PRD.

---

## Background

### Overview

This PRD covers the basic functionality of marketing our RWA token to the retail market, covering:

- **Group Subscription:** Retail users should be able to purchase our RWA token permissionlessly.
- **Group Redemption:** Retail users should be able to redeem their investment back into liquid
  format.

### Objectives

- Market our own token to the retail market ourselves, because we do not want to be over-reliant on
  web3 foundations.
- Solve the early redemption issue from the retail market, and market the tokens without taking our
  own liquidity.
- Hit the minimum ticket size to fulfill private funds assets' requirement.

### Product Vision

Enable marketing Evergreen Private Credit funds with minimum capital needed from us.

---

## Main Protocol Product Details

### General Structure

The REX Primary consists of 3 major functions:

- **Group Subscription:** This part of the contract pools the stablecoin from retail investors and,
  upon epoch, subscribes to the asset in Pruv Finance and distributes it to the retail investors.
- **Group Redemption:** This part of the contract pools the wRWAToken from retail investors who want
  to exit and, upon epoch, redeems the asset in Pruv Finance and distributes the Stablecoin to the
  exiting investors.
- **Matching System:** The matching system handles the netting out between subscription and
  redemption; the leftover (either subscription or redemption) is the one executed to Pruv Finance.

Structure (from the PRD diagram): `Primary → { Group Subscription, Group Redemption } → Queue →
Matching → { Subscribe to Pruv, Redeem to Pruv }`.

### States

The product has 5 states:

- **Initialized:** The vault has been created and the launchpad is counting down to start.
- **Launchpad started:** Retail investors lock in their USDC to meet the minimum ticket size for
  subscribing to the asset.
- **Launchpad fail:** The launchpad fails to meet the minimum amount needed to subscribe after the
  time limit is reached.
- **Epoch-based:** After the launchpad is successful, activate epoch-based subscription and
  redemption.
- **Wind-down:** Pool shutting down.

State flow (from the PRD diagram): `START → Initialized → Launchpad start → success? →
{ yes → Epoch based, no → Launchpad fail → END }`; from Epoch based, `Closing down? → yes →
Wind-down → END`.

### Information Required

To launch the pool, the admin must provide:

- Asset to purchase (asset contract address)
- Stablecoin used
- Start of launchpad
- The period of the launchpad (how long it accepts stablecoin)
- Minimum amount needed (if the stablecoin gathered is lower than this, the pool fails)
- Epoch period

Based on this information, the engineering team prepares and deploys the app.

### Initialized

The `initialized` phase is the state after the vault is deployed but before the launchpad time
starts. All vault and redemption contracts are disabled. No transaction can be made in this state.

### Launchpad Start

When the launch time is reached, the vault status changes to `launchpad-start`. The vault enters
launchpad mode, trying to gather stablecoins within the time limit. This can use the default group
subscription contract with modified parameters.

**Flow:**

- People who lock their stablecoin receive only a **receipt token, not a vault token**.
- The receipt token is used to **claim the wrapped RWA token** they bought.

System side (from the PRD flow diagram): receive locked stablecoin → time limit reached? → minimum
purchase met? → if yes, the platform takes the stablecoin and bridges it to the Pruv Network, uses
it to subscribe to the RWA token, bridges the RWA token back to the original network, and
distributes the wrapped RWA tokens to retail users. If minimum not met, the pool fails and stablecoin
is unlocked for refund.

### Launchpad Fail

If the launchpad fails to gather the minimum stablecoin for the minimum purchase within the time
limit, it goes to `launchpad-fail`. All deposits are disabled. All retail wallets can redeem the
stablecoin they locked in previously.

### Epoch-based

After the launchpad fulfills the minimum ticket size within the time limit, the vault enters
`epoch-based`, its normal operating phase.

#### Group Subscription

- **Input:** Stablecoin
- **Return:** wRWA Token

The Group Subscription process mimics the **ERC-7540** abstraction but **without issuing a vault
token**, especially in the `requestDeposit` function. Each subscription request is queued and pooled
together, for two reasons:

1. To wait until the subscription window of the underlying asset.
2. To aggregate smaller subscriptions to fulfill the minimum subsequent subscription.

**Flow:**

1. Retail investor navigates to the product page, inputs the amount to subscribe, and clicks
   Subscribe.
2. Retail investor signs the transaction to send the stablecoin to the subscription queue (based on
   the ERC-7540 standard).
3. Retail investor gets a **receipt token** to claim their wrapped RWA token later.
4. Anytime before the subscription window is open, the retail investor can withdraw their
   subscription (based on **ERC-7887**).
5. Once the subscription window is open, the smart contract matches the subscription request with
   the redemption request and nets out the amount.
6. If any subscription amount is left after netting, the contract takes the stablecoin in the queue
   and subscribes to the token in Pruv.
7. The RWA token is then **bridged over to the chain where the dApp is, as a wrapped token**.
8. The wrapped RWA token is distributed to the retail investor according to how much receipt token
   they used to claim.

#### Group Redemption

- **Input:** wRWAToken
- **Return:** Stablecoin

Every redemption request is also queued by the ERC-7540 standard.

**Flow:**

1. Retail investor navigates to the product page, inputs the amount to redeem, and clicks Redeem.
2. Retail investor signs the transaction to send the wrapped RWA token to the redemption queue
   (based on ERC-7540).
3. Retail investor gets a receipt token to claim their stablecoin later.
4. Anytime before the window is open, the retail investor can withdraw their request (based on
   ERC-7887).
5. Once the redemption window is open, the contract matches subscription with redemption and nets
   out.
6. If any redemption amount is left after netting, the contract takes the wrapped RWA token in the
   queue and redeems in Pruv.
7. The Stablecoin is then bridged over to the chain where the dApp is.
8. The stablecoin is distributed to the retail investor according to how much receipt token they
   used to claim.

### Auxiliary System

#### Matching System

At the end of an epoch, net out the stablecoin in the subscription queue against the value of the
token in the redemption queue, and only process the delta.

- **Subscription > Redemption:** Based on the updated value on epoch, 10,000 USDC in the
  subscription queue and vault token worth 4,000 USDC in the redemption queue. Use 4,000 USDC to swap
  with 4,000 USDC worth of vault tokens. The remaining 6,000 USDC is used to purchase the underlying
  asset.
- **Redemption > Subscription:** Based on the updated value on epoch, 4,000 USDC in the subscription
  queue and vault token worth 10,000 USDC in the redemption queue. Use 4,000 USDC to swap with 4,000
  USDC worth of vault tokens. The remaining 6,000 USDC worth of vault token is burned in exchange for
  the 6,000 USDC gained from swapping the liquid asset in custody. If there is none, proceed to sell
  this asset.

> `[eng note]` The words "vault token", "burned", and "liquid asset in custody" in this Matching
> section are inconsistent with the Group Subscription statement "without issuing a vault token" and
> with management's direction (bridge wRWA to buyers, no custody). Engineering resolves this in
> `../decisions/ADR-002-no-vault-token.md` and `../decisions/ADR-003-no-custody-retail-holds-wrwa.md`:
> "vault token" here means "wRWA valued at NAV", matching settles by raw token transfer, and there is
> no custody buffer. This note is not part of the original PRD.

#### Fees

Fees are charged in two areas:

- **Subscribe cancellation:** When someone locks in their stablecoin and cancels it, they are charged
  a small fee.
- **Redemption:** When someone redeems their asset, they are charged a small fee.

### Wind-down

If, during the epoch-based phase, the company decides to decommission the vault, the admin can
trigger the final `wind-down` state. In this phase:

- All new subscription requests are disabled.
- All pending subscriptions in the queue are refunded.
- All liquid assets inside the vault are exchanged immediately to stablecoin.
- The stablecoin is used to pay the redemption requests in the redemption queue.
- Then, according to the redemption window, all illiquid assets inside the vault are emptied and
  redeemed.
- The vault is left with stablecoin, where users should redeem their vault token for stablecoin
  within the time limit.

> `[eng note]` This wind-down description assumes the custody + vault-token model (liquid/illiquid
> assets "inside the vault", users redeeming "their vault token"). Under ADR-002/ADR-003 (no vault
> token, no custody, retail hold wRWA), engineering maps this to: disable subscriptions, refund
> pending, settle the redemption queue via Pruv, and leave retail-held wRWA with its owners. See
> `../specs/spec.md` §7.7. Not part of the original PRD.
