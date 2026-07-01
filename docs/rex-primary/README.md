# REX Primary — Project Documentation

Production design and delivery documentation for **REX Primary**: a protocol that markets a
tokenized **Evergreen Private Credit** fund (Pruv Finance) to the retail market through
permissionless **Group Subscription** and **Group Redemption**, with an epoch-based **Matching**
system that nets subscriptions against redemptions so only the delta touches the underlying fund.

> **Source of truth:** the REX Primary PRD, transcribed in
> [`prd/REX-Primary-PRD.md`](prd/REX-Primary-PRD.md). Where this documentation and the PRD disagree,
> the PRD wins unless an ADR in `decisions/` explicitly overrides it. **This folder is
> self-contained**: everything it references (the PRD, the Pruv interface, diagrams, ADRs) lives
> inside it. An earlier single-chain proof-of-concept exists elsewhere in this repository and is
> treated as reference only; REX Primary departs from it in several load-bearing ways (see
> `prd/prd-analysis.md` section "POC delta").

---

## Status

| Item | State |
|---|---|
| Phase | **Design** (pre-build). Phase 0 research not yet started. |
| Architecture | Cross-chain async (home chain + Pruv chain), bridged via Hyperlane. **Settled.** |
| Working assumption | **No vault token, no custody** — retail hold the bridged wRWA directly; REX issues claim receipts, not shares. Adopted pending final confirmation of the PRD §Matching wording (tracked in `decisions/ADR-002-no-vault-token.md`). |
| Open blockers | Warp-route-for-wRWA reuse-vs-deploy (research T0.2). |

---

## Canonical facts (read once, rely on everywhere)

- **Two chains.** *Home chain* = an EVM where retail transact in USDC (initially **Sepolia**).
  *Fund chain* = **PRUV** (PRUV Testnet, Hyperlane domain `7336`), where Pruv Finance lives.
- **Bridge** = Hyperlane **Warp Routes**, two tokens, both directions: **USDC** (home ↔ PRUV) and
  **wRWA** (PRUV ↔ home).
- **Retail hold wRWA.** The wrapped RWA is bridged to the home chain and distributed to buyers.
  There is **no pooled custody** contract and **no REX-issued share token**.
- **NAV comes from an oracle.** `RWAConversion.value()` on PRUV is relayed to the home chain; REX
  never invents a price and never trusts a stale or wildly-moved one.
- **Retail are not KYC'd.** Only the on-chain `PruvExecutor` holds the Pruv `Whitelist` credential.

---

## Folder layout

```
rex-primary/
├── README.md                 this index
├── constitution.md           non-negotiable engineering principles
├── prd/
│   ├── REX-Primary-PRD.md     the PRD, transcribed (source of truth)
│   └── prd-analysis.md        engineering analysis of the PRD
├── architecture/
│   ├── architecture.md        components, chains, trust boundaries
│   └── diagrams/              sequence diagrams (.mmd + .png) + index
├── specs/
│   ├── spec.md                contract behavior (states, matching, lifecycle)
│   ├── services-spec.md       off-chain: keeper, NAV relay, monitor, indexer/API
│   └── frontend-spec.md       dApp screens, states, flows
├── planning/
│   ├── dev-plan.md            phased roadmap with gates
│   └── tasks.md               Jira Epic/Task/Sub-task breakdown
├── decisions/                 ADR-001 .. ADR-006
├── references/
│   ├── glossary.md            terminology
│   └── pruv-interface.md      external Pruv contract interface, copied in
└── skills/                    reusable engineering skills for this project
```

## Document map

| Document | Purpose | Read if you are... |
|---|---|---|
| [`prd/REX-Primary-PRD.md`](prd/REX-Primary-PRD.md) | **The source of truth** - the PRD, transcribed in full | everyone, first |
| [`constitution.md`](constitution.md) | Non-negotiable engineering principles the whole project obeys | everyone, first |
| [`references/glossary.md`](references/glossary.md) | Terms (wRWA, NAV, epoch, warp route, in-flight, receipt...) | anyone hitting an unfamiliar term |
| [`prd/prd-analysis.md`](prd/prd-analysis.md) | What the PRD asks for, and how it maps to this design (incl. POC delta) | PM, new engineers |
| [`architecture/architecture.md`](architecture/architecture.md) | Components, chains, trust boundaries, data flows, diagrams | all engineers |
| [`specs/spec.md`](specs/spec.md) | **The production spec** - states, functions, matching math, lifecycle, errors, acceptance scenarios | contract + service engineers |
| [`specs/services-spec.md`](specs/services-spec.md) | Off-chain services spec: keeper, NAV relay, monitor, indexer/API | backend/services engineers |
| [`specs/frontend-spec.md`](specs/frontend-spec.md) | dApp spec: screens, states shown, previews, wallet flows | frontend engineers |
| [`planning/dev-plan.md`](planning/dev-plan.md) | Phased delivery roadmap, gates, team sequencing, walking skeleton | leads, everyone planning work |
| [`planning/tasks.md`](planning/tasks.md) | Jira-ready Epic/Task/Sub-task breakdown | leads creating tickets |
| [`decisions/`](decisions/) | Architecture Decision Records (the "why" behind irreversible choices) | anyone questioning a design choice |
| [`references/pruv-interface.md`](references/pruv-interface.md) | The external Pruv Finance contract interface, copied in | contract + service engineers |
| [`architecture/diagrams/`](architecture/diagrams/) | Sequence diagrams for every flow (source + rendered, in-folder) | visual learners, all engineers |
| [`skills/`](skills/) | Reusable engineering skills for this project (matching math, cross-chain settlement, bridge, oracle, conventions) | engineers implementing a subsystem |

## Reading order

1. `prd/REX-Primary-PRD.md` - the source of truth, read it first.
2. `constitution.md` - the rules of the game.
3. `prd/prd-analysis.md` - what we are building and why it differs from the POC.
4. `architecture/architecture.md` + `architecture/diagrams/` - the shape of the system.
5. `specs/spec.md` - the exact behavior to implement.
6. `specs/services-spec.md` + `specs/frontend-spec.md` - the off-chain and UI behavior.
7. `planning/dev-plan.md` + `planning/tasks.md` - how and in what order to build it.
8. `skills/` - pull the relevant skill when you start a subsystem.

## Relationship to the earlier POC

An earlier single-chain proof-of-concept (elsewhere in this repository) proved the mechanism: the
5-state lifecycle, async request queues (ERC-7540/7887), net-delta matching, and a manual NAV. REX
Primary reuses those patterns but is a different system: cross-chain, oracle-priced, custody-free,
and share-free. The POC is a pattern reference only, never the authority; the PRD and this spec are.
This folder deliberately does not link to POC files - it stands on its own.
