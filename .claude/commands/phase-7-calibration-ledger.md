---
description: Phase 7 runbook — weekly review screen with outcome marking and pattern surfacing
---

# Phase 7 — Calibration Ledger

Week 12. Full detail: PLAN.md §Phase 7. SPEC cross-refs: §6.9.

## Objectives

- Build `ThisWeekView`: list verdicts where `outcome_status = 'pending'` AND deadline ≤ now + 7d, OR deadline < now
- Sidebar badge: count of due + overdue
- Per-verdict summary with outcome mark controls (right / partial / wrong / dismiss), actual notes, what-changed
- Enforce outcome state machine per SPEC §6.9 (pending → one of 4 terminal states)
- Pattern queries run only when `COUNT(marked) >= 20`:
  - Calibration rate by lens template
  - Calibration rate by reversibility
- Pattern display: horizontal bar chart sorted desc, `n=X` label
- Empty state at < 20: "Patterns appear after 20 marked outcomes. You have N so far."
- Decision Detail → Outcome tab: mark form (pending) or outcome record (marked)

## Definition of done

- Mark outcomes on 5 sample verdicts; all persist
- This Week shows accurate due/overdue counts
- Pattern queries execute without error (may be sparse at low volume)
- Dismissed verdicts no longer appear in This Week

## Exit gate

`/spec-check` scoped to §6.9.
