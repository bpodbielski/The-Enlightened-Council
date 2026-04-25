# The Council — Build Plan (Executive Summary)

**Version:** 2.0
**Date:** 2026-04-22
**Status:** Superseded in detail by PLAN.md — this doc is the one-page brief

---

## What this doc is

A one-page orientation. Full task-level plan lives in **PLAN.md**. Product requirements in **PRD.md**. Implementation spec in **SPEC.md**.

---

## Target

Native macOS app. Swift 6. SwiftUI. Ships as a signed and notarized DMG. Single developer. v1 in 12 to 16 weeks.

---

## Ship gate (from SPEC §13)

v1 ships when all 10 acceptance criteria pass. Summary:

- All 8 lens templates run end-to-end in both cloud and air gap modes
- Force-directed graph at ≥ 60 fps with 200 nodes on M5
- Verdict brief exports cleanly to Markdown and PDF
- Air gap toggle blocks all cloud traffic (verified by proxy)
- Cost guardrails: soft warn at $2, hard pause at $5
- Sequential local run (Qwen 32B then Mistral 22B) ≤ 15 min on M5 32 GB
- Zero crashes across a 20-decision stress test
- Zero telemetry in production
- Signed and notarized DMG mounts on a clean macOS 15 install

Full list: SPEC §13.

---

## Phase milestones

| Week | Phase | Demo-able outcome |
|---|---|---|
| 1 | 0 — Foundation | App opens, Settings works, API keys persist, force-sim spike passes |
| 2 | 1 — Intake + Refinement | Form produces a refined brief via Claude |
| 3–4 | 2 — Cloud Orchestration | 4-model parallel run completes, cost tracked |
| 5–6 | 3 — Local Orchestration | Air gap run end-to-end, no outbound traffic |
| 7–8 | 4 — Debate Engine | 3-round debate with clustered arguments |
| 9–10 | 5 — Synthesis Map | 60 fps force graph, verdict tray works |
| 11 | 6 — Verdict Capture | Verdict saved with pre-mortem |
| 12 | 7 — Calibration Ledger | This Week screen operational |
| 13 | 8 — Export | Markdown and PDF exports match on-screen |
| 14–15 | 9 — Polish | Signed DMG, accessibility pass |
| 16 | 10 — Dogfood and Ship | 20 real decisions, v1 declared |

---

## Critical path and risk

- **Phase 5 (Synthesis Map) is highest technical risk.** Force-simulation spike in Week 1 is non-negotiable. Go/no-go before Week 9.
- **Phases 2 and 3 overlap.** Cloud and local orchestration both feed Phase 4.
- **Phase 7 needs real data.** Run real decisions through Phases 6 and 7 as soon as they are functional.
- **Phase 10 is non-negotiable.** No ship without dogfood signal.

---

## What is NOT in v1

- Team features, multi-user, cloud sync, iCloud sync
- Custom persona authoring, lens template editor
- Share-sheet integrations, bundle import/export
- Mixed cloud-plus-local runs in one council
- Voice intake

Full list: PRD §4 and SPEC §14.

---

## Where to go next

- **Product intent:** PRD.md
- **Implementation detail:** SPEC.md
- **Phase-by-phase task list:** PLAN.md
- **Operational instructions for Claude Code:** CLAUDE.md
