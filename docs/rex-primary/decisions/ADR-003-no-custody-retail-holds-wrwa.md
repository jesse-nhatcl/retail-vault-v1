# ADR-003: No custody; retail hold the bridged wRWA

**Status:** Accepted (2026-07-01), confirmed by David Kurniawan.

## Context

In a cross-chain design (ADR-001) the subscribed RWA could either (a) stay on the PRUV chain held by
a custody/executor, with retail holding a home-chain claim, or (b) be bridged to the home chain and
distributed to retail directly.

David Kurniawan confirmed: "you need to bridge back the wRWA and distribute it to the buyers, so no
more custody."

## Decision

Option (b). The wRWA is bridged to the home chain and **distributed to buyers**, who hold it
directly. There is **no custody contract** holding a standing pool of user assets. REX holds value
only transiently in-flight during epoch settlement.

## Consequences

- Requires a **wRWA warp route** to the home chain (both directions), in addition to USDC (see
  dev-plan T0.2 for reuse-vs-deploy).
- Removes the POC's `Custody` and its 20% liquid buffer / 3-layer redemption. Redemption is
  match → Pruv, with no instant-exit buffer (trade-off flagged in `../prd/prd-analysis.md` §4).
- No home-chain custody honeypot; the risk shifts to the bridge and executor.
- Pairs with ADR-002 (no share): retail hold wRWA, not a REX claim token.

## Alternatives

Keeping wRWA in a PRUV-side custody avoids per-user wRWA bridging cost, but contradicts David's
direction and reintroduces custody. Revisit only if bridging cost proves prohibitive, via a new ADR.
