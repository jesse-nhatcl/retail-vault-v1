# ADR-004: NAV via a Hyperlane-message oracle

**Status:** Accepted as default (2026-07-01), to be confirmed in Phase 0 research (T0.3).

## Context

Matching values the redemption queue against the subscription queue at NAV. NAV lives on PRUV
(`RWAConversion.value()`, 18-decimal) and must reach the home chain trustworthily. The PRD calls for
NAV "updated on epoch"; the user has no prior preference. Options:

- **(a)** Off-chain relay signs `setNav` with a trusted key.
- **(b)** Hyperlane interchain message carries NAV (a PRUV `NavReporter` dispatches to a home
  `NavOracleConsumer`).
- **(c)** Chainlink / CCIP.

## Decision

Default to **(b)**: reuse Hyperlane (already integrated for the token bridge) to relay NAV. Reasons:
one security model (the same ISM we already vet for the bridge), no second trust vendor, latency
bounded by the relay we measure in T0.2.

Defenses layered on top: **staleness guard** (reject NAV older than `STALENESS_WINDOW`) and
**sanity bound** (reject a move larger than `MAX_NAV_MOVE_BPS` since the last accepted value). Only
the enrolled reporter on the expected domain may update.

## Consequences

- Adds a `NavReporter` (PRUV) and `NavOracleConsumer` (home).
- Settlement reverts `StalePrice` rather than settling on an outdated price (constitution Article 6).
- Ties NAV liveness to bridge/relay liveness; the keeper must keep NAV fresh before initiating.

## Alternatives

(a) is simplest but adds a bespoke trusted signer. (c) is oracle-grade but introduces a vendor and
cost. Reconsider if Hyperlane latency or liveness proves inadequate in T0.2/T0.3.
