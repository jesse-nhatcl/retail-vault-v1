# ADR-005: Fee model - REX fees plus Pruv fee on the delta only

**Status:** Accepted (2026-07-01). Per user direction: follow the PRD, propose best practice.

## Context

The PRD authorizes two REX fees: a **subscription cancellation** fee and a **redemption** fee.
Separately, Pruv charges its own **entry/exit** fees (`RWAFee.feeOnRaw`/`feeOnTotal`) whenever the
executor deposits/redeems. We must decide who bears Pruv's fee and how REX fees are presented.

## Decision

- The two PRD fees are **REX product fees**: configurable bps, a named recipient (REX treasury),
  and always shown in `previewSubscribe`/`previewRedeem` before the user signs.
- **Pruv's entry/exit fee is charged only to the net delta** that actually round-trips Pruv. The
  matched peer-to-peer portion never touches Pruv and therefore bears no Pruv fee. Cost follows
  causation.
- **No hidden fees:** every amount paid or received is derivable from a public preview call.

## Consequences

- Netting is rewarded: users whose flow is matched avoid Pruv fees, reinforcing the Matching
  system's purpose.
- The fee split (REX vs Pruv) must be transparent in the UI and events.
- Fee accounting is an explicit invariant: fees collected equal fees delivered to recipients.

## Alternatives

Socializing Pruv's fee across all participants (matched and unmatched alike) is simpler to compute
but unfair to matched users and blunts the incentive to net. Rejected.
