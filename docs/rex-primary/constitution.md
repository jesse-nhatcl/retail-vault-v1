# REX Primary — Engineering Constitution

The non-negotiable principles that govern every design and implementation decision in REX Primary.
A constitution is not a style guide: it is the set of rules we do **not** trade away for
convenience, deadline, or cleverness. When a decision is hard, re-read this. When code and this
document disagree, the code is wrong.

**Violating the letter of a principle is violating its spirit.** If you find yourself arguing that
a shortcut "technically complies," stop.

Amendments happen only through an ADR in `decisions/`, reviewed and merged like code. Until then,
these hold.

---

## Article 1 — Source of truth

1.1 The **PRD REX Primary** is the source of truth for *what* to build. `specs/spec.md` is the source of
truth for *how it behaves*. Code implements the spec; it never redefines it.

1.2 When the PRD is ambiguous or self-contradictory (for example the §Matching "vault token"
wording), the resolution is recorded as an ADR and referenced from the spec. No silent
interpretation.

1.3 The POC (`retail-access-vault`) is **reference, not authority**. A POC pattern is adopted only
when it also satisfies this constitution in the cross-chain setting.

## Article 2 — No custody

2.1 REX **never holds retail assets at rest**. Retail own the bridged **wRWA** directly; exiting
retail receive **USDC** directly. The protocol holds value only **transiently in-flight** during an
epoch settlement.

2.2 There is no pooled-portfolio contract. Any design that reintroduces a standing balance of user
funds on the home chain requires an ADR overriding this article.

## Article 3 — No vault token (working assumption)

3.1 REX issues **claim receipts** (proof of a queued request), **not** shares. Retail exposure is
the wRWA itself, priced by Pruv, not a REX-issued unit priced by REX.

3.2 This is a working assumption pending confirmation of the PRD §Matching wording (see
`decisions/ADR-002-no-vault-token.md`). If it is overturned, it is overturned by ADR, not by an
implementer's convenience.

## Article 4 — Cross-chain safety first

4.1 Every cross-chain action is **idempotent** and keyed by a unique message id. Replaying a bridge
message must never mint, pay, or distribute twice.

4.2 **No funds may be stranded.** Every path that sends value across the bridge has a defined
recovery path if the far side fails (retry, or admin sweep on the destination chain).

4.3 Trust only messages from an **enrolled sender on an expected domain**. Validate origin before
acting on any inbound message (NAV update, bridged token, settlement callback).

## Article 5 — Async settlement discipline

5.1 An epoch is **not atomic**. It is `initiateEpoch()` (compute delta, send to bridge) then, after
the far side executes and the return bridges back, `settleEpoch()` (distribute). Never assume the
Pruv leg completes within one transaction.

5.2 While an epoch is **in-flight**, the invariant `claimable obligations ≤ assets accounted for`
must hold at every step. No new epoch initiates until the current one settles or is explicitly
recovered.

5.3 Double-settle is forbidden by construction, not by hope. Guard with epoch state, not comments.

## Article 6 — NAV integrity

6.1 NAV is read from the **oracle only** (`RWAConversion.value()` relayed to the home chain). REX
never invents, interpolates, or hard-codes a price.

6.2 A NAV that is **stale** (older than the configured window) or **out of sanity bounds** (moved
more than the configured maximum since the last accepted value) is **rejected**. Settlement that
depends on NAV reverts rather than settling on a bad price.

## Article 7 — Matching fairness

7.1 Matching runs **before** any Pruv interaction. Subscriptions and redemptions net off peer-to-
peer at NAV; **only the net delta** is bridged to Pruv.

7.2 The matched portion never round-trips Pruv, and therefore **bears no Pruv fee**. Cost follows
causation: only the delta that actually causes a Pruv deposit/redeem pays Pruv's entry/exit fee.

## Article 8 — Fees are honest

8.1 The only REX fees are those the PRD authorizes (subscription cancellation, redemption). They
are **configurable**, have a named recipient, and are **shown in preview before the user signs**.

8.2 **No hidden fees.** Every amount a user pays or receives must be derivable from a public
`preview` call before they act.

## Article 9 — Permissioning

9.1 Retail are **permissionless**. No KYC gate on subscribe/redeem/claim at the REX layer.

9.2 The **only** KYC'd actor is the on-chain `PruvExecutor`, which holds the Pruv `Whitelist`
credential (ERC-1155 token id 1). This is what makes a permissioned fund accessible to permissionless
retail.

9.3 Privileged actions (admin, keeper, relay) use **least privilege** and are held by a multisig in
production. No single EOA controls funds or upgrades on mainnet.

## Article 10 — Value conservation

10.1 Value is created or destroyed **only** by a Pruv `deposit`/`redeem`. REX moves tokens; it does
not manufacture them.

10.2 Across a full epoch (including the bridge legs), tokens in equal tokens out plus fees. This is
an invariant to be fuzzed, not an aspiration.

## Article 11 — Testing discipline

11.1 **TDD** (`superpowers:test-driven-development`): a failing test precedes production code, on
both chains and in off-chain services.

11.2 Acceptance scenarios assert **exact numbers** (the PRD's 10k/4k matching example is a contract,
not an approximation).

11.3 No subsystem is "done" without **cross-chain integration tests** (mock bridge + mock Pruv) and,
before any mainnet consideration, a **testnet end-to-end** run logged on both chains.

11.4 At least the value-conservation and no-stranded-funds invariants are covered by fuzz.

## Article 12 — Security conventions

12.1 Custom errors, never `require("string")`. Every state mutation emits a named event, emitted
**before** external calls where possible.

12.2 `nonReentrant` on every externally-triggered value movement (`claim`, `refund`, `settleEpoch`,
bridge callbacks). `SafeERC20` for all transfers. Checks-effects-interactions always.

12.3 Compiler pinned (no caret). No upgradeable proxy without an ADR defining the upgrade authority.

## Article 13 — Change control

13.1 Every irreversible or load-bearing decision is an **ADR** in `decisions/`. The ADR records the
context, the options, the choice, and the consequences.

13.2 Changing behavior means changing the **spec first**, then the code. A PR that changes behavior
without a spec change is incomplete.

## Article 14 — Scope discipline

14.1 Build the **walking skeleton first**: one subscribe round-trip across both chains, end to end,
before breadth (launchpad, wind-down, fees, UI polish).

14.2 YAGNI. No feature enters scope without appearing in the PRD or an ADR. Three straightforward
lines beat one premature abstraction.

---

### Amendment process

Propose an ADR in `decisions/` (`ADR-NNN-title.md`) stating which article changes and why. On merge,
update this constitution with a pointer to the ADR. No principle is amended by implication.
