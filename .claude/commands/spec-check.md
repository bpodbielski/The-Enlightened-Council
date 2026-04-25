---
description: Verify the current branch against SPEC acceptance criteria (or a specific section)
---

# spec-check

Run this before closing any phase. Pass a section number as argument (example: `/spec-check §6.4`) or leave blank to run the full SPEC §13 acceptance criteria.

## What this does

1. Parses the target SPEC section(s).
2. Maps each acceptance bullet to a test or manual verification step.
3. Runs the automatable checks.
4. Reports pass/fail with file-and-line evidence.

## Full-suite checklist (SPEC §13)

- [ ] 8 lens templates run end-to-end in cloud and air gap modes without crashes
- [ ] Force-directed graph ≥ 60 fps with 200 nodes on M5
- [ ] Markdown and PDF exports match on-screen verdict
- [ ] Calibration ledger surfaces due verdicts in This Week
- [ ] Air gap blocks all cloud traffic (proxy-verified)
- [ ] Cost guardrails: $2 soft, $5 hard, no silent overruns
- [ ] Sequential local run ≤ 15 min on M5 32 GB
- [ ] 20-decision stress test zero crashes
- [ ] Zero telemetry in production
- [ ] Signed notarized DMG mounts on clean macOS 15

## How to use

1. State the section to check (or "full").
2. For each bullet, run the associated test or check.
3. Output a pass/fail table with explicit evidence paths (test name, file, line).
4. Any fail blocks phase closure; log remediation in TASKS.md.
