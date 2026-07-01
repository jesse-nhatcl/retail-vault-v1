# Pruv Finance — On-chain Interface (reference)

In-folder reference for the external Pruv Finance contracts REX integrates with, extracted from
Pruv's published examples (upstream: the `pruv-docs` repository). Kept here so this folder is
self-contained. Values marked `(confirm T0.x)` must be re-verified on the live PRUV testnet during
Phase 0 research; this is a snapshot, not a substitute for reading the live contracts.

---

## Contracts

Pruv exposes four contracts on the PRUV chain:

| Contract | Role |
|---|---|
| `RWAToken` | The fund vault. A standard **ERC-4626** (UUPS-upgradeable, role-based). |
| `RWAConversion` | The NAV source. |
| `RWAFee` | Entry/exit fee calculator. |
| `Whitelist` | KYC gate (ERC-1155). |

## RWAToken (ERC-4626) — key functions

```
deposit(uint256 assets, address receiver) returns (uint256 shares)   // subscribe
redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)  // redeem
mint(uint256 shares, address receiver) returns (uint256 assets)
withdraw(uint256 assets, address receiver, address owner) returns (uint256 shares)
previewDeposit / previewMint / previewRedeem / previewWithdraw
convertToShares(uint256 assets) / convertToAssets(uint256 shares)
maxDeposit / maxMint / maxRedeem / maxWithdraw
asset() returns (address)          // the underlying stablecoin
totalAssets() / totalSupply() / balanceOf(address) / decimals()
rwaConversion() returns (address)  // the NAV contract
rwaFee() returns (address)         // the fee contract
maxSupply() / cappedSupply()       // supply cap
```

**Implication for REX:** subscribing to Pruv is `deposit(assets, receiver)`; redeeming is
`redeem(shares, receiver, owner)`. Both are **synchronous** on the PRUV chain. The "subscription
window" the PRD mentions is a business/operational constraint, not a contract-level gate.

## RWAConversion (NAV)

```
value() returns (uint256)     // NAV, 18-decimal, parity = 1e18 (e.g. 1.5e18 = 1.5)
setValue(uint256 newValue)    // admin-set NAV
```

**Implication for REX:** this is the NAV the oracle relays to the home chain. 18-decimal, parity
`1e18`. See `../decisions/ADR-004-oracle-nav-hyperlane.md`.

## RWAFee (entry/exit fees)

```
feeOnRaw(uint256 amount, uint8 timing) returns (uint256)    // fee added on top (entry, timing 0)
feeOnTotal(uint256 amount, uint8 timing) returns (uint256)  // fee taken from total (exit, timing 1)
fee(uint8 timing) returns (uint8, uint256)
setFee(uint8 kind, uint256 bps, uint8 timing) / setRecipient(address, uint8)
```

**Implication for REX:** Pruv charges its own entry/exit fee whenever the executor deposits/redeems.
Per `../decisions/ADR-005-fee-model.md`, this cost is borne only by the net delta that round-trips
Pruv; matched P2P flow pays no Pruv fee.

## Whitelist (KYC gate)

```
balanceOf(address account, uint256 id) returns (uint256)   // id 1 = the KYC credential
```

**Implication for REX:** every `deposit`/`redeem` at Pruv requires the caller to hold `Whitelist`
token id 1. Retail cannot each be whitelisted, so the single `PruvExecutor` holds it - which is what
lets a permissioned fund serve permissionless retail (constitution Article 9).

## Bridge (Hyperlane, reference addresses)

Pruv's reference bridge connects PRUV Testnet (domain `7336`) and Kaia Kairos (domain `1001`) via
Hyperlane warp routes: a `HypERC20CollateralWithFee` on PRUV and a `HypERC20` synthetic on the
remote chain, for USDC and for the RWA token (observed 6-decimal). REX targets a different home chain
(Sepolia), so whether an existing wRWA route reaches it or one must be deployed is a Phase 0 research
item (T0.2). See `rex-bridge-hyperlane` skill and `../decisions/ADR-001-cross-chain-pa2.md`.

## Decimals observed

| Token | Decimals |
|---|---|
| Bridged RWA (synthetic) | 6 `(confirm T0.1)` |
| USDC | 6 |
| NAV (`value()`) | 18, parity `1e18` |
