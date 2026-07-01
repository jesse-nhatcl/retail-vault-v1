# ADR-001: REX and Pruv live on different chains (cross-chain, async)

**Status:** Accepted (2026-07-01)

## Context

Pruv Finance is deployed on its own chain (PRUV Testnet, Hyperlane domain `7336`). Retail transact
on a general EVM (initially Sepolia). Two placements were possible:

- **PA1** — deploy REX on the PRUV chain: `Custody`/executor talks to Pruv synchronously, epoch stays
  atomic, bridge only for user onboarding.
- **PA2** — deploy REX on a separate home chain: every Pruv interaction crosses the bridge and is
  asynchronous.

The PRD describes bridging USDC to Pruv and bridging the RWA back to the dApp chain, i.e. the dApp
lives apart from Pruv. Management confirmed PA2.

## Decision

Adopt **PA2**. REX runs on the home chain; Pruv interaction is via Hyperlane and a PRUV-side
`PruvExecutor`. The epoch is a two-phase, non-atomic flow: `initiateEpoch` (send delta) → bridge →
`settleEpoch` (distribute).

## Consequences

- The epoch cannot be atomic; we need in-flight states, idempotency by message id, and no-stranded-
  funds recovery (constitution Articles 4, 5).
- The unmatched portion of a redemption waits for an async round-trip (no instant exit).
- New trust surface: the bridge, the executor, and cross-chain messaging.
- Simpler than PA1 in one respect: no home-chain custody is required (see ADR-003).

## Alternatives

PA1 keeps synchronous atomic epochs and is simpler to reason about, but contradicts the PRD's
topology and management's direction. Revisit only via a new ADR.
