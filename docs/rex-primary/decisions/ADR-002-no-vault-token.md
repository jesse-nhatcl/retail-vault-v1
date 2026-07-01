# ADR-002: REX issues receipts, not a vault token

**Status:** Accepted as working assumption (2026-07-01), pending final confirmation of PRD §Matching
wording.

## Context

The PRD is internally inconsistent. Four sections say retail hold the **wrapped RWA** and that REX
subscribes "**without issuing a vault token**," using a **receipt token** only to claim. The
§Matching section, however, uses the phrase "vault token" and "liquid asset in custody" - classic
ERC-4626 vault language.

A vault token would be genuinely required only if we chose a different product: retail holding a
REX-issued pooled share instead of the underlying wRWA (e.g. for a unified redemption unit, a
regulatory wrapper, or to avoid bridging wRWA per user). That is a different design, not a matching
requirement.

## Decision

REX issues **claim receipts** (proof of a queued request), **not** shares. Retail exposure is the
bridged wRWA itself. Matching settles by **raw token transfer** (wRWA ↔ USDC), never by minting or
burning a REX unit. The §Matching "vault token" wording is treated as a naming error meaning "wRWA
valued at NAV."

The user directed: assume no vault token. Management (David Kurniawan) confirmed the sibling point
("distribute the wRWA to the buyers, no more custody", see ADR-003).

## Consequences

- No REX ERC-20 share, no share-decimal dimension (removes the POC's main bug source).
- The ERC-7540 request pattern is borrowed, but REX is **not** a compliant 4626/7540 vault.
- If per-user wRWA bridging proves too costly, revisiting a share model is the escape hatch - but
  only via a new ADR overturning this one.

## Open

Final confirmation of the §Matching wording from David. If he says a real share is intended, this
ADR is superseded and `../specs/spec.md` §8 + the matching tasks change materially.
