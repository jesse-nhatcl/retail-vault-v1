# ADR-006: Token and interface standards (locked)

**Status:** Accepted (2026-07-01).

## Context

The PRD names two EIPs explicitly ("mimic the **ERC-7540** abstraction but without issuing a vault
token"; withdrawals "based on **ERC-7887**") and Pruv's fund is an **ERC-4626** vault. These need to
be pinned unambiguously so no one assumes REX is a compliant tokenized vault.

## Decision

| Standard | Where it applies | REX's relationship |
|---|---|---|
| **ERC-4626** | Pruv's `RWAToken` (external, on PRUV) | REX **consumes** it via `PruvExecutor.deposit/redeem`. REX itself is **not** an ERC-4626 vault. |
| **ERC-7540** (async request pattern) | REX subscription/redemption | REX **borrows the request pattern** (`requestDeposit`/`requestRedeem` → claim) but is **not** a compliant ERC-7540 vault, because it issues **no share token** (ADR-002). |
| **ERC-7887** (cancellable requests) | REX pending requests | A queued request may be cancelled before its epoch initiates. |
| **ERC-20** | wRWA and USDC | wRWA on the home chain is the Hyperlane `HypERC20` synthetic; USDC is standard ERC-20. |

### The receipt

The claim receipt is **not** a vault share and **not** an ERC-4626/7540 unit. Default
implementation: a **non-transferable claim record** (`requestId → owner`), the simplest thing that
satisfies "receipt token, not a vault token." If the product later needs the claim itself to be
transferable (e.g. secondary trading of a pending position), it may be issued as an ERC-721; that is
a change requiring an update to this ADR, not an implementer's choice.

### Explicit non-goals

- REX does **not** implement ERC-4626 (`totalAssets`, `convertToShares`, a share `balanceOf`, etc.).
- REX does **not** implement full ERC-7540 (no `share` accounting, no `pendingDepositRequest` share
  math beyond the receipt record needed for claims).

## Consequences

- Integrators must not expect a `share` token or 4626 views from REX. The user's asset is the wRWA
  (an ERC-20 on the home chain), priced by Pruv.
- The request/claim surface is small and bespoke; it reuses 7540/7887 *naming* for familiarity, not
  compliance.
- If ADR-002 is overturned (a real share is wanted), this ADR is revisited alongside it: REX would
  then likely become a genuine ERC-7540 vault.

## Related

`ADR-002-no-vault-token.md`, `ADR-003-no-custody-retail-holds-wrwa.md`, `../specs/spec.md` §3.0, glossary
entries for ERC-4626 / ERC-7540 / ERC-7887.
