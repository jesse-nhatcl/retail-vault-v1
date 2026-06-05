# Fee Research — Raw Data Digest (Phase R)

**Project:** 2026-06-retail-access-vault
**Date:** 2026-06-05
**Method:** 2 parallel web-research sweeps — (A) platform fee benchmarks, (B) on-chain fee mechanics
**Status:** Phase R raw material. Final report = `06-fees/fee-research.md` (Phase E).

---

# Part A — Fee Models of Tokenized RWA Fund Platforms (2024–2026)

Scope note: "Charging mechanism" describes how the fee is technically taken (NAV accrual/deduction, mint-burn flow fee, or yield-spread). Where a tokenized product is a *feeder* into a TradFi fund, fees exist at two layers — (i) the on-chain wrapper/transfer-agent layer and (ii) the underlying fund — and these are distinguished below. Unverified figures are flagged explicitly.

## 1. Securitize — BlackRock BUIDL

- Management fee: 0.50% on Ethereum, Arbitrum, Optimism; 0.20% on Aptos, Avalanche, Polygon (tiered by chain). — https://unchainedcrypto.com/blackrock-and-securitizes-522-million-buidl-fund-goes-multi-chain/ ; https://www.coindesk.com/business/2024/11/13/blackrock-expands-tokenized-fund-buidl-beyond-ethereum-to-five-new-blockchains (2024-11-13)
- Performance/incentive fee: None (money-market fund). Flagged: not a single explicit "0%" source, but consistent with MMF type.
- Entry/subscription fee: None at fund level. Min investment historically $5M. — https://messari.io/project/blackrock-usd-institutional-digital-liquidity-fund
- Exit/redemption fee: None; redemptions at $1.00/token. Same-day USDC redemption via Circle smart-contract facility.
- Charging mechanism: Management fee accrued against the fund; yield paid as new tokens (daily dividend accrual). NAV pegged $1.
- Who pays whom: Investor → fund (mgmt fee to BlackRock). Separately, the Investment Manager pays Securitize Markets as placement agent — upfront flat fee plus quarterly fee = % of average daily NAV of investors introduced by Securitize (manager → platform rev-share, not charged to investor). — https://www.sec.gov/Archives/edgar/data/0001738078/000119312524019474/d425960d497k.htm (FY2024 497K)

## 1b. Securitize — Hamilton Lane SCOPE (Senior Credit Opportunities Fund) feeder

Two-layer structure: Securitize feeder/token wrapper vs. underlying SCOPE evergreen private credit fund.

- Feeder-level (per RWA.xyz): Management fee 1.75%; Performance fee 0%; Redemption fee 0%; Subscription fee 0%. — https://app.rwa.xyz/assets/HLSCOPE
- Securitize transaction fee on redemption: None — "redeem shares on-demand at the previous quarter's NAV per share … with no transaction fees from Securitize." — https://securitize.io/learn/press/securitize-expands-access-to-hamilton-lanes-senior-credit-opportunities-fund-via-polygon (2023-04)
- Subscription / redemption cadence: Monthly subscription; redemptions on demand at prior-quarter NAV. Min investment reduced to $10,000 (from $2M). — https://www.hamiltonlane.com/en-us/news/scope-available-via-securitize
- Underlying SCOPE incentive fee / hurdle / early-repurchase penalty / quarterly 5% NAV redemption cap: **COULD NOT VERIFY** — prospectus/KIID gated (401/403/geo-blocked). Plausible for the class but unsourced.
- ADDX (different distributor of SCOPE): one-time subscription fee "from as low as 0.5%"; min USD 5,000. — https://addx.co/en/investments/hamiltonlane-scope/index.html

## 1c. Securitize — Hamilton Lane Equity Opportunities Fund V (EOV) feeder

- Min investment reduced from ~$5M average to $20,000. — https://www.prnewswire.com/news-releases/hamilton-lanes-2-1-billion-flagship-direct-equity-fund-now-available-for-investment-on-securitize-301734791.html
- Fee rates: **COULD NOT VERIFY** publicly.

Cross-reference — Hamilton Lane Private Assets Fund (PAF/HLPAF, different HL retail evergreen, model of HL fee practice):
- Pre-March 2025: 1.5% mgmt fee; 12.5% performance fee over an 8% hurdle; carry deal-by-deal on exit.
- Post-March 2025: 1.5% mgmt; performance fee cut to 10%; hurdle removed; carry payable quarterly across whole fund including unrealized gains; loss-recovery account but no clawback. — https://www.transacted.io/hamilton-lane-restructures-retail-fund-carry-model-for-faster-fee-realization (2025)

## 2. Ondo Finance

### OUSG
- Management fee: 0.15% — WAIVED until July 1, 2026. Fund expenses capped at 0.15% p.a. — https://docs.ondo.finance/qualified-access-products/ousg/fees-and-taxes
- Performance fee: None.
- Exit: "Instant minting and redemption may incur additional fees" (bps not numerically disclosed). — https://docs.ondo.finance/qualified-access-products/ousg/instant-limits
- Charging mechanism: NAV-level; instant-transaction fees charged on the flow. OUSG largely invests into BlackRock BUIDL underneath.

### USDY
- Model: Yield-spread (NOT an explicit fee on principal). Holders receive portfolio return MINUS ~25 bps annual fee Ondo retains. — https://www.ccn.com/education/crypto/ondo-finance-tokenized-us-treasuries-ousg-usdy/
- RWA.xyz shows all fees "0%" — spread is implicit in the APY set by Ondo.
- Redemption fee: one source states 20 bps redemption fee + wire fee on redemptions under $100K — **needs reconfirmation** (live page 404).
- Charging mechanism: Yield spread — Ondo keeps (gross portfolio yield − published USDY APY).

## 3. Superstate

### USTB
- Management fee: 0.15% p.a.; monthly rebate 0.10% on holdings above $25M (effective 0.05% above $25M). — https://docs.superstate.com/ustb
- Perf/entry/exit: None.

### USCC
- Management fee: 0.75% p.a. of average daily NAV, monthly in arrears; does NOT accrue until fund reaches $50M NAV. — https://docs.superstate.com/uscc
- Perf/entry/exit: None.

## 4. Franklin Templeton — BENJI / FOBXX

- Total expense ratio: 0.20%; management fee component 0.15%; no 12b-1. — https://www.morningstar.com/funds/xnas/fobxx/quote ; SEC 497K
- Perf/entry/exit: None. NAV $1.00 stable; yield via daily dividend tokens.

## 5. OpenEden — TBILL

- Management fee / TER: 0.30% p.a., charged daily on TVL. — https://docs.openeden.com/tbill/fees
- Transaction fee: **5 bps on BOTH subscription and redemption**, paid in USDC to manager treasury (covers gas, wire, conversion).
- Performance fee: None.
- Charging mechanism: TER accrued daily on NAV; transaction fee taken on-chain on the mint/redeem flow.

## 6. Midas — mTBILL / mBASIS

### mTBILL
- Management fee: 0%. Performance fee: 10% on interest. Redemption fee 0.07% (per trackers; Midas marketing shows 0%). — https://app.rwa.xyz/assets/mTBILL ; https://readi.fi/asset/structured-product-mtbill-midas-mtbill-by-midas/
- NAV independently verified by Ankura Trust.

### mBASIS
- Management 0%; Performance 10%; mint/redeem 0% headline.
- Note: redemption fees "include all fees hypothetically arising from a liquidation process" — real exit cost can exceed headline 0%. — MFSA Final Terms 2024-10-28: https://www.mfsa.mt/wp-content/uploads/2024/11/Midas-Software-GmbH-Final-Terms-Document-dated-28-October-2024.pdf

## 7. Backed Finance — bIB01

- Issuance (mint) fee: 0.20%. Redemption (burn) fee: 0.20%. Management fee 0.25% p.a. — https://app.rwa.xyz/assets/bIB01 ; bIB01 factsheet 2023-08-08
- Charging mechanism: Flow fee on mint/burn against issuer + NAV accrual. (Older source cited 0.5% issuance — 0.20% is the recent/official figure.)

## 8. Centrifuge — Anemoy JTRSY + protocol fee

### JTRSY (Janus Henderson Anemoy Treasury Fund)
- Management fee: 0.15%; perf 0%; no entry/exit; daily redemptions. — https://www.anemoy.io/funds/jtrsy ; https://app.rwa.xyz/assets/JTRSY

### Centrifuge protocol layer
- Protocol fee proposal: 0.4% on valuation of completed loans → CFG treasury. — https://gov.centrifuge.io/t/centrifuge-protocol-fees/4840 (**confirm enacted status**)
- Pool onboarding fee: 50 bps flat for permissionless pools. — https://gov.centrifuge.io/t/cp74-updating-transaction-fees-for-pools/5773
- Who pays whom: Pool/issuer → Centrifuge protocol treasury (distinct from investor-facing fund fee).

## 9. Maple Finance / Syrup

- Fee mechanism: Management fees charged during loan payments as portion of GROSS borrower interest (not fee on lender principal/NAV). — https://docs.maple.finance/syrupusdc-usdt-for-lenders/faq
- Protocol take: ~15–20% of total borrower interest (third-party reported); lenders receive ~80–85%. — https://www.modularcapital.xyz/writing/maple
- Split mechanism (open-term loans): `platformManagementFeeRate` (→ MapleTreasury) + `delegateManagementFeeRate` (→ Pool Delegate), per payment, delegate-set per pool.
- Legacy reference: establishment fee 0.99% annualized (66 bps Treasury / 33 bps Delegate).
- Exit: no stated bps exit fee; withdrawals via queue. Instant exit = DEX swap spread (~12 bps normal; >50 bps discount signals buffer exhausted). — https://maple.finance/insights/instant-liquidity-for-syrupusdc
- 25% of protocol revenue → SYRUP buyback (MIP-019, Nov 2025).

## TradFi Reference — Evergreen / Interval / Tender-Offer Private Credit Funds

- Management fee: typically **1.0%–1.5% of NAV p.a.** (on NAV, not committed capital — key difference vs drawdown PE). — https://www.morningstar.com/business/insights/blog/rise-of-evergreen-funds ; https://carta.com/learn/private-funds/private-equity/pe-fund-structures/evergreen-funds/
- Incentive fee: **10%–20% over hurdle; common credit structure = 12.5% on income over ~5% hurdle, with full catch-up**.
- Hurdle: typically 5%–6% for credit; some PE evergreens 8% (HL PAF pre-2025).
- Early repurchase fee: commonly **2% on shares repurchased within ~12 months** (typical, not universal). — https://www.morningstar.com/funds/5-things-you-need-know-about-interval-fund-fees
- Quarterly repurchase cap: interval funds must offer ≥5% of outstanding shares per quarter at NAV; some cap monthly ~2%.
- Servicing/distribution (retail share classes): 12b-1-type fees ~0.25%–0.85% on top of base mgmt + incentive.
- Charging mechanism: mgmt + incentive accrue daily/monthly against NAV; early-repurchase fee deducted from redemption proceeds on the flow.

## Part A Comparison Table

| Platform / Product | Mgmt fee (p.a.) | Perf fee | Entry | Exit / early-exit | Charging mechanism |
|---|---|---|---|---|---|
| BlackRock BUIDL | 0.20–0.50% (by chain) | None | None | None | NAV accrual; yield as new tokens |
| HL SCOPE feeder (Securitize) | 1.75% (feeder) | 0% feeder; underlying UNVERIFIED | None | 0% via Securitize; prior-qtr NAV | Feeder NAV |
| Ondo OUSG | 0.15% (waived → 2026-07) | None | None | Instant fee (bps undisclosed) | NAV-level; instant fee on flow |
| Ondo USDY | ~25 bps spread (implicit) | None | 0% | ~20 bps (reconfirm) | Yield-spread |
| Superstate USTB | 0.15% (0.05% >$25M) | None | None | None | NAV accrual |
| Superstate USCC | 0.75% (after $50M NAV) | None | None | None | NAV accrual, monthly arrears |
| Franklin BENJI | 0.15% (TER 0.20%) | None | None | None | Expense ratio on NAV |
| OpenEden TBILL | 0.30% TER | None | 5 bps | 5 bps | TER on NAV + flow fee |
| Midas mTBILL | 0% | 10% on interest | 0% | 7 bps (tracker) | Perf on interest + flow |
| Midas mBASIS | 0% | 10% | 0% | 0% headline (+embedded costs) | Perf + spread at redemption |
| Backed bIB01 | 0.25% | None | 0.20% | 0.20% | Flow fee mint/burn + NAV |
| Centrifuge JTRSY | 0.15% | 0% | None | None | NAV accrual |
| Maple syrupUSDC | delegate-set; ~15–20% of interest | embedded | None | Queue (free) / DEX spread (instant) | Fee on gross interest flow |
| TradFi evergreen credit (ref) | 1.0–1.5% NAV | 10–20%, 12.5%/5% hurdle common | varies | ~2% if <12mo; 5%/qtr cap | NAV accrual + flow deduction |

## Part A — Key unverified flags

1. Hamilton Lane SCOPE underlying incentive fee / hurdle / early-redemption penalty / quarterly cap — prospectus gated.
2. HL Equity Opportunities Fund V feeder fees — unverified.
3. Ondo USDY 20 bps redemption fee — live page 404; reconfirm.
4. Midas mTBILL 0% vs 7 bps redemption discrepancy (marketing vs trackers).
5. Backed bIB01 minimums (5,000 USDC vs 100 CHF) and older 0.5% issuance figure.
6. Maple per-pool split not published as fixed %.
7. Centrifuge 0.4% protocol fee — governance proposal; confirm enacted.

---

# Part B — On-Chain Vault Fee Mechanics (Technical)

## B1. ERC-4626 / ERC-7540 entry & exit fee patterns

### Fee-on-assets vs fee-on-shares
- **Fee-on-assets**: take fee from underlying asset amount *before* share conversion (OpenZeppelin `ERC4626Fees` model).
- **Fee-on-shares**: mint fewer shares to depositor / burn extra on exit; credit delta as shares to fee receiver (Lagoon, Yearn fee shares).
- Difference: fee-on-assets gives treasury liquid assets immediately (no vault PnL exposure); fee-on-shares keeps treasury invested, dilutes price-per-share path.

### OpenZeppelin `ERC4626Fees` — exact mechanics
All fee logic in `preview*` functions; base conversion untouched.

```solidity
uint256 private constant _BASIS_POINT_SCALE = 1e4;

function previewDeposit(uint256 assets) public view override returns (uint256) {
    uint256 fee = _feeOnTotal(assets, _entryFeeBasisPoints());
    return super.previewDeposit(assets - fee);
}
function previewMint(uint256 shares) public view override returns (uint256) {
    uint256 assets = super.previewMint(shares);
    return assets + _feeOnRaw(assets, _entryFeeBasisPoints());
}
function previewWithdraw(uint256 assets) public view override returns (uint256) {
    uint256 fee = _feeOnRaw(assets, _exitFeeBasisPoints());
    return super.previewWithdraw(assets + fee);
}
function previewRedeem(uint256 shares) public view override returns (uint256) {
    uint256 assets = super.previewRedeem(shares);
    return assets - _feeOnTotal(assets, _exitFeeBasisPoints());
}
```

```solidity
// fee added on top of a net amount
_feeOnRaw(assets, bps)   = assets.mulDiv(bps, 1e4, Ceil);
// fee already embedded in a gross amount
_feeOnTotal(assets, bps) = assets.mulDiv(bps, bps + 1e4, Ceil);
```

`_feeOnRaw` where user specifies the *net* leg (mint/withdraw); `_feeOnTotal` where user specifies the *gross* leg (deposit/redeem). Rounding always `Ceil` in favor of vault. Fee transferred to recipient inside overridden `_deposit`/`_withdraw` after standard mint/burn.
Source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/mocks/docs/ERC4626Fees.sol

### Why ERC-7540 async vaults charge at settlement/claim
Lifecycle: request → valuation → settlement (fulfill) → claim. "The exchange rate between shares and assets including fees and yield is up to the Vault implementation" (EIP-7540). No synchronous price at request time → fees plug into the *fulfillment* step where curator posts NAV and per-request rate is frozen. Lagoon: "rates frozen at settlement for async requests." Natural place to mint fee shares since totalAssets/totalSupply recomputed anyway.
Sources: https://eips.ethereum.org/EIPS/eip-7540 ; https://lagoon.finance/blog/erc-7540-explained ; https://docs.centrifuge.io/developer/protocol/architecture/vaults/

## B2. Management-fee accrual methods

### (a) Share-dilution / streaming — mint fee shares to treasury
Dominant DeFi pattern. Each accrual mints new shares to fee recipient; existing holders diluted; PPS in asset terms preserved (no asset leaves vault). Used by Yearn v3, MetaMorpho, Lagoon, Veda-style vaults.

**Yearn v3** — vault calls external `Accountant` on every `process_report`; accountant returns `(total_fees, total_refunds)` in asset terms; vault mints corresponding shares.
```
feeAssets = totalAssets * mgmtBps * (now - lastReport) / (SECS_PER_YEAR * MAX_BPS)
feeShares = feeAssets * totalSupply / (totalAssets - feeAssets)   // convert at post-fee NAV
```
Yearn detail: fee-share issuance also unlocks locked profit so PPS does not visibly dip; profit streamed over `profit_max_unlock_time`.
Sources: https://docs.yearn.fi/developers/v3/periphery ; https://github.com/yearn/yearn-vaults-v3/blob/master/TECH_SPEC.md

**MetaMorpho** — accrues JIT before any deposit/withdraw via `_accruedFeeShares()`:
```
totalInterest = newTotalAssets - lastTotalAssets
feeAssets     = totalInterest.mulDiv(fee, WAD)            // fee ≤ 0.5e18 (50% cap, on-chain)
feeShares     = feeAssets.mulDiv(totalSupply, newTotalAssets - feeAssets, Floor)
```
Key subtlety: `newTotalAssets - feeAssets` denominator — totalAssets already grew by full interest, fee assets must be subtracted before converting to shares or recipient over-credited.
Sources: https://github.com/morpho-org/metamorpho/blob/main/src/MetaMorpho.sol ; https://docs.morpho.org/curate/concepts/fee/

**Lagoon** — mints fee shares to `feeReceiver` at every settlement:
```
managementFee = (assets * rate / BPS) * (timeElapsed / 1 year)   // cap 10%/yr
```
Plus `protocolFee` operator taking a cut of *collected* fees (cap 10%, on-chain max 30%). Source: https://docs.lagoon.finance/vault/fees

### (b) NAV skim — deduct from totalAssets before pricing
Reported NAV reduced by accrued fees; every holder's redemption value drops proportionally; fee realized when treasury later withdraws. **Veda BoringVault**: `Accountant` publishes exchange rate computed off-chain — "total deposited × fee rate × timespan/year" — with on-chain guardrails: **update-frequency limits + rate-deviation bounds + pause**. Fee embedded in posted rate, not discrete share mint.
Source: https://docs.veda.tech/architecture-and-flow-of-funds/core-components

### (c) Per-epoch crystallization
Fees computed and locked once per settlement epoch. Lagoon "collected at each settlement"; Centrifuge epoch execution. Between epochs fee is accrued figure; at settle it crystallizes into minted shares. Bounds gas (one accrual per epoch, amortized over all requests) at cost of coarser timing; mid-epoch entrants need pro-rating or get charged for time not in fund.

### Pros/cons summary
- **Dilution (a)**: no assets leave vault; treasury stays invested; small compounding error if accruals sparse; must sequence fee mint vs profit-unlock.
- **Skim (b)**: cheapest hot path; depends on admin-posted rate → highest manipulation surface; fee "soft" until withdrawn.
- **Crystallization (c)**: best gas amortization, clear per-epoch audit trail; coarse granularity.

## B3. Performance fee — HWM and hurdle on-chain

- **Lagoon** (verified): perf fee only on PPS above all-time-high PPS, on-chain HWM:
  ```
  profit         = (pricePerShare - highWaterMark) * totalSupply   // only if > 0
  performanceFee = profit * rate / BPS                             // cap 50%
  ```
  HWM updates after profitable settlement; losses must be recovered first. Rates can only be lowered, never raised.
- **MetaMorpho**: perf fee on interest accrued = effectively per-accrual HWM on totalAssets (loss lowers `lastTotalAssets`, gains refill first). Cap 50%.
- **Yearn v3**: perf fee via pluggable Accountant on per-report `gain`; strict global PPS HWM is accountant-specific **[UNVERIFIED]**.
- **On-chain hurdle rate**: not found in Yearn/Morpho/Lagoon **[UNVERIFIED-absent]** — gap vs TradFi norm.
- **HWM manipulation with admin-set NAV**: manager can post inflated NAV to cross HWM and crystallize outsized perf fee, or under-then-over-report to harvest fake gain. Mitigations: Veda rate-deviation bounds + frequency limits + pause; Lagoon fee caps + lower-only rates + on-chain HWM; Morpho on-chain interest source (no admin price at all). **HWM is only as trustworthy as the valuation feeding PPS; admin-set NAV is the weak link.**

## B4. Exit-side fees & anti-bank-run designs

### Instant vs queued redemption (two-tier liquidity)
- **Ondo OUSG**: instant 24/7 redeem (backed by BUIDL liquidity) "may incur additional fees" vs standard redemption; exact bps not published.
- **Maple syrupUSDC**: instant exit = DEX swap spread (~12 bps normal; >50 bps discount-to-NAV signals buffer exhausted → queued redemption binding). Protocol runs dynamic instant-liquidity buffer ($200M+) + withdrawal queue.
- Pattern: instant redemption from liquid buffer carries penalty/spread; queued redemption at fund NAV is penalty-free. Penalty (a) recovers cost of idle liquidity, (b) defeats first-mover advantage.

### Swing pricing / dilution levy on-chain
TradFi concept: adjust NAV or levy transacting investors so they (not the standing pool) bear trading costs, removing first-mover run incentive. **No DeFi protocol found implementing true swing pricing on-chain** [UNVERIFIED-absent]. Closest: OZ static exit fees; Maple's market-emergent NAV discount. References: https://www.iosco.org/library/pubdocs/pdf/IOSCOPD756.pdf ; https://www.bis.org/publ/work664.pdf

## B5. Epoch fees & P2P netting interaction (fee leakage)

- In 7540 queued vaults, entry/exit fee applies to the **request's settlement amount** at fulfill; rate frozen at settlement; deterministic regardless of claim timing.
- **Fee leakage risk**: if fees are charged only on *net fund-level* flow, P2P-matched volume escapes entry/exit fees → coordinated deposit+redeem pairs in the same epoch can dodge the levy.
- **Mitigation: charge entry/exit fee on each request's GROSS settlement amount (per-user), independent of netting** — matching then only saves trading/slippage cost, never bypasses fees.
- Could not confirm how Centrifuge/Lagoon book fees on netted volume [UNVERIFIED for named protocols]; principle stands as design caution.

## B6. Keeper / gas cost recovery

- **Yearn-style**: report/harvest permissioned to keepers; cost socialized into fees at report time; keepers treasury-funded, no per-call on-chain bounty in core vault.
- **Async vaults**: curator pays gas for settle/processEpoch, recovers via mgmt/protocol fee collected at same settlement (Lagoon).
- **No surveyed vault pays explicit per-call processEpoch keeper bounty in bps** [UNVERIFIED-absent]. Gelato/Chainlink Automation reimburse gas + premium from protocol treasury, not vault-level fee field.

## B7. Accrual method comparison

| Method | How taken | Precision | Gas (hot path) | Manipulation risk | Complexity |
|---|---|---|---|---|---|
| Dilution/streaming fee shares (Yearn v3, MetaMorpho, Lagoon) | Mint shares to treasury each accrual | High; small compounding error if sparse | Medium | Low if interest on-chain; higher if PPS admin-set | Higher (sequencing vs profit unlock) |
| NAV skim (Veda BoringVault) | Reduce posted rate by accrued fee | Formula-exact; depends on cadence | Lowest | **Highest** — admin posts rate; mitigated by bounds/limits/pause | Low contract, high trust |
| Per-epoch crystallization (Lagoon settle, Centrifuge) | Compute + lock per settlement, mint shares | Epoch-granular | Best amortization | Tied to epoch NAV; bounded by caps + frozen rates | Medium; netting can leak gross fees |
| Static entry/exit levy (OZ ERC4626Fees) | Skim assets on deposit/withdraw via preview* | Exact (bps, Ceil to vault) | Low | Low (no time/NAV component); not flow-adaptive | Very simple; no mgmt/perf accrual |

## Part B — Unverified / gap flags

1. Ondo OUSG instant-redemption fee bps — not published.
2. Yearn v3 global PPS HWM — accountant-specific.
3. On-chain hurdle rate — likely absent across surveyed protocols.
4. True swing pricing on-chain — no implementation found.
5. Fee booking on P2P-netted volume (Centrifuge/Lagoon) — unconfirmed; mitigation = charge per-request gross.
6. Explicit processEpoch keeper bounty in bps — not found.

## Primary sources (Part B)

- OZ ERC4626Fees: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/mocks/docs/ERC4626Fees.sol
- ERC-7540: https://eips.ethereum.org/EIPS/eip-7540
- Yearn v3: https://docs.yearn.fi/developers/v3/periphery ; https://github.com/yearn/yearn-vaults-v3/blob/master/TECH_SPEC.md
- MetaMorpho: https://github.com/morpho-org/metamorpho/blob/main/src/MetaMorpho.sol ; https://docs.morpho.org/curate/concepts/fee/
- Lagoon: https://docs.lagoon.finance/vault/fees
- Veda: https://docs.veda.tech/architecture-and-flow-of-funds/core-components
- Maple: https://maple.finance/insights/instant-liquidity-for-syrupusdc ; https://tidresearch.com/reports/syrupusdc/
- Centrifuge: https://docs.centrifuge.io/developer/protocol/architecture/vaults/
- Swing pricing: https://www.iosco.org/library/pubdocs/pdf/IOSCOPD756.pdf
