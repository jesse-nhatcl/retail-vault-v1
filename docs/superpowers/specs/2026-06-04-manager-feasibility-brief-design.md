# Design — Manager Feasibility Brief

**Date:** 2026-06-04
**Status:** Approved, ready to build
**Goal:** Present the retail-access-vault POC to managers (both tech-lead and exec) in a way that
proves **Alt-1 is feasible** — beyond the existing `Demo.s.sol` script.

---

## 1. Context

The POC is complete: 2 production contracts (Vault + Custody), 4 mocks, 36 passing tests, 8 verified
acceptance scenarios, and a manager-readable `Demo.s.sol`. What's missing is a **presentation-grade
artifact** the team can show live (screen-share) and leave behind (email) for a mixed audience.

- **Audience:** both engineering/tech-lead and business/exec — needs layering.
- **Setting:** both live walkthrough and read-alone.
- **Objective:** prove feasibility — the complex mechanism (matching, 3-layer redemption, NAV) works
  coherently, and the team can build it.

## 2. Deliverables

1. `docs/presentation/feasibility-brief.html` — single self-contained HTML file (inline CSS, images
   embedded as base64). No server, no external dependencies. Dark, professional theme. Print-friendly.
2. `docs/02-architecture/diagrams/{system-arch,state-machine,process-epoch-sequence}.png` — rendered
   from the existing `.mmd` sources via `mmdc --scale 3 --width 2400`, then embedded base64 into (1).
3. Real captured output of `forge script script/Demo.s.sol --sig 'run(string)' "ALL"`, embedded in
   the brief's "See it run" section.

## 3. HTML structure (single scroll page, anchored nav)

| # | Section | Audience | Content |
|---|---------|----------|---------|
| 0 | Hero / Verdict | Exec | Badge "FEASIBLE — 8/8 mechanism scenarios verified"; one-line description; 3 bullets of what the POC proves; fact strip (2 production contracts, 36 tests pass, single Anvil chain) |
| 1 | Problem & why Alt-1 | Exec | Retail can't reach private credit (high min, periodic windows) → vault pools/wraps/buffers. Short Alt-1 vs Alt-2 table |
| 2 | How it works | Both | Architecture diagram + state-machine diagram (PNG). Four pillars in plain language: async queue · P2P matching · 3-layer redemption · manual NAV |
| 3 | What we proved: 8 scenarios | Both | 8 cards, each: name + "what it proves" (1 line) + concrete before→after numbers + PASS badge. **Core feasibility evidence** |
| 4 | See it run | Both | Monospace block of the real `ALL` demo output (8/8 PASS) + the commands to reproduce |
| 5 | Under the hood | Tech | processEpoch sequence diagram (PNG); decimals/NAV convention; worked S4 matching math; test coverage breakdown (4 mock + 7 custody + 16 vault + 8 scenario + 1 fuzz = 36); resolved spec inconsistencies |
| 6 | Scope · risks · next | Exec | In-scope vs deferred; POC simplifications (manual price unenforced, Pruv full-fill, 1:1 AMM); suggested next phases (L2 integration, real Pruv, audit) |

## 4. Data sourcing (no invented numbers)

- Scenario numbers: from `docs/05-spec.md §9` and cross-checked against the test assertions.
- Demo output: literal capture of the `ALL` run.
- Test count: literal `forge test` summary (36).
- Spec inconsistencies: from the project memory / scenario test headers.

## 5. Build method

1. `mmdc -i <f>.mmd -o <f>.png --scale 3 --width 2400` for each of the 3 diagrams (per
   `~/.claude/rules/research.md`; on timeout, fall back to `--scale 2 --width 1600` and report).
2. Run the demo, capture `ALL` output to a temp file.
3. Hand-author the single HTML file with inline CSS; embed PNGs as base64 `data:` URIs.
4. Verify: file opens, all 3 images render (base64 present), demo block matches real output.

## 6. Non-goals

- No live/interactive JS (static scroll page only).
- No slide deck / PDF in this iteration (HTML is the hero; PDF export can follow if asked).
- No change to contracts, tests, or `Demo.s.sol`.

## 7. Acceptance

- One `.html` opens standalone with all diagrams and the real 8/8 demo output visible.
- Exec can grasp the verdict from the top fold; tech-lead finds depth lower down.
- Every number traces to spec §9 or a real command run.
