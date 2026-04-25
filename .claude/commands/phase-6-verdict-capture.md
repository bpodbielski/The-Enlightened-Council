---
description: Phase 6 runbook — verdict saved with confidence, pre-mortem, and test
---

# Phase 6 — Verdict Capture

Week 11. Full detail: PLAN.md §Phase 6. SPEC cross-refs: §6.8.

## Objectives

- Build `VerdictCaptureView` single-column form per SPEC §6.8
- Auto-populate: for-position tray nodes → `key_for_json`; against → `key_against_json`
- Confidence slider 0-100, default 70
- DatePicker for outcome deadline, default today + 60 days
- "Draft verdict with Claude" button: sends refined brief + tray arguments to `claude-sonnet-4-6` (2-4 sentences)
- Pre-mortem auto-generation on Save Verdict: sends verdict + confidence + deadline to `claude-sonnet-4-6`, 3-5 bullets of plausible failure paths
- User sees pre-mortem in editable field before confirming save
- Save writes to `verdicts`; decision status → `complete`
- Cancel returns to Synthesis Map without saving

## Definition of done

- Complete a decision flow end-to-end; save a verdict
- Re-open the decision → Verdict tab shows it cleanly
- Pre-mortem generated and editable before save
- Verdict queryable by `outcome_deadline`

## Exit gate

`/spec-check` scoped to §6.8.
