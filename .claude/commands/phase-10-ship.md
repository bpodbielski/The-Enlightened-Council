---
description: Phase 10 runbook — 20 real decisions dogfood, final fixes, v1 declared
---

# Phase 10 — Dogfood and Ship

Week 16. Full detail: PLAN.md §Phase 10. SPEC cross-refs: §13.

## Objectives

- Run 20 real decisions across all 8 lens templates, both cloud and air gap modes
- Log bugs and friction in `friction-log.txt` (gitignored)
- Fix every critical issue: crash, data loss, misleading output, cost-tracking error
- Build final signed and notarized DMG
- Verify all 10 acceptance criteria from SPEC §13

## Definition of done

- 20 decisions complete without crashes
- All critical bugs resolved
- You would show it to another director without apology
- SPEC §13 acceptance criteria 1-10 all pass

## Exit gate

`/spec-check` full pass. Tag release `v1.0.0`. Archive DMG privately.
