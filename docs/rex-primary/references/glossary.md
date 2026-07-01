# REX Primary — Glossary

Canonical definitions. If a term is used differently anywhere else, this file wins.

| Term | Definition |
|---|---|
| **REX Primary** | The protocol described here: retail-facing group subscription/redemption for a tokenized private-credit fund, with epoch matching and cross-chain settlement. |
| **Pruv Finance** | The underlying fund provider. Exposes an ERC-4626 vault (`RWAToken`), a NAV contract (`RWAConversion`), a fee contract (`RWAFee`), and a KYC gate (`Whitelist`) on the PRUV chain. |
| **RWA** | Real World Asset. Here, a share of the Evergreen Private Credit fund, represented on-chain by Pruv's `RWAToken`. |
| **wRWA** | The **wrapped RWA** as it exists on the home chain: the Hyperlane **synthetic** representation of Pruv's RWA, bridged over and held by retail. What "distribute to the buyers" refers to. |
| **Home chain** | The EVM where retail transact (deposit USDC, hold wRWA, claim). Initially **Sepolia**. |
| **Fund chain / PRUV** | The chain where Pruv Finance is deployed. PRUV Testnet, Hyperlane domain `7336`. |
| **USDC** | The stablecoin retail subscribe with and are redeemed into. 6 decimals. |
| **NAV** | Net Asset Value per RWA unit, sourced from `RWAConversion.value()` (18-decimal, parity = `1e18`). Used to value the redemption queue against the subscription queue at matching time. |
| **Epoch** | The batch settlement cycle. Requests accumulate, then an epoch is initiated and later settled. |
| **initiateEpoch** | Home-chain call that snapshots the queues, runs matching, and sends the net delta to the bridge. Marks the epoch in-flight. |
| **settleEpoch** | Home-chain call, after the bridged return arrives, that distributes wRWA/USDC and opens claims. |
| **In-flight** | The window between `initiateEpoch` and `settleEpoch`, while value is crossing the bridge. |
| **Matching** | Netting the subscription queue (USDC) against the redemption queue (wRWA valued at NAV). The matched portion settles peer-to-peer; only the delta hits Pruv. |
| **Net delta** | The unmatched remainder after matching: net subscriptions (bridge USDC to Pruv, deposit) or net redemptions (bridge wRWA to Pruv, redeem). |
| **Receipt** | Proof of a queued request, used to claim the result later. A claim ticket, **not** a tradeable share and **not** a vault token. |
| **PruvExecutor** | The REX contract **on the PRUV chain**. The sole KYC'd (whitelisted) actor. Receives bridged USDC and calls `RWAToken.deposit`; receives bridged wRWA and calls `RWAToken.redeem`; bridges the result back. |
| **NavOracleConsumer** | Home-chain contract that stores the latest relayed NAV with a timestamp, enforcing staleness and sanity-bound guards. |
| **NavReporter** | PRUV-chain contract that reads `RWAConversion.value()` and dispatches it over Hyperlane to the `NavOracleConsumer`. |
| **FeeModule** | Home-chain contract computing REX's subscription-cancellation and redemption fees. |
| **Keeper** | Off-chain service that triggers `initiateEpoch`, watches bridge delivery, and triggers `settleEpoch`. |
| **Warp Route** | Hyperlane's token-bridging standard. A `HypERC20Collateral` locks the real token on one chain; a `HypERC20` synthetic mints a 1:1 representation on the other. `transferRemote` moves value across. |
| **Hyperlane** | The interchain messaging layer. Used both for the warp routes (tokens) and, in the default design, for relaying NAV. |
| **ISM** | Interchain Security Module — Hyperlane's pluggable verification for inbound messages. The trust root for cross-chain safety. |
| **Launchpad** | The initial fundraising state: gather USDC to a minimum ticket; on success subscribe to Pruv and distribute wRWA; on failure refund 100%. |
| **Wind-down** | The shutdown state: disable new subscriptions, refund pending, settle the redemption queue via Pruv; retail-held wRWA is unaffected. |
| **Staleness guard** | Rejection of a NAV older than a configured age, so settlement never uses an outdated price. |
| **Sanity bound** | Rejection of a NAV that moved more than a configured maximum since the last accepted value, defending against a corrupted or spoofed relay. |
| **ERC-4626** | Tokenized vault standard (deposit/redeem/preview/convert). Pruv's `RWAToken` implements it. REX itself is **not** a 4626 vault. |
| **ERC-7540** | Asynchronous ERC-4626: `requestDeposit`/`requestRedeem` then claim. REX borrows this **request pattern** but issues receipts, not shares. |
| **ERC-7887** | The cancellable-request extension: a queued request may be withdrawn before its window closes. |
| **Walking skeleton** | The thinnest end-to-end slice that exercises the whole system: one subscribe request settled across both chains. Built first. |
