---
description: Phase 4 runbook — three rounds of independent analysis, rebuttal, and defend-or-update, then argument extraction and clustering
---

# Phase 4 — Debate Engine

Weeks 7-8. Full detail: PLAN.md §Phase 4. SPEC cross-refs: §6.4.

## Objectives

- Implement `DebateEngine` for the full 3-round protocol per SPEC §6.4
- Round 1: `(model × persona × sample)` combinations with temperature 0.3 / 0.7 / 1.0
- Round 2: distribute anonymized round-1 outputs (labels → `Perspective A/B/C`, consistent mapping per decision); produce rebuttal + steel-man
- Round 3: each persona gets its own round-1 output + round-2 rebuttals directed at it; produce `POSITION: maintained/updated` flag
- Add nullable `position_changed` boolean to `model_runs` (set during round-3 parse)
- Implement `ArgumentExtractor` post-round-3 JSON extraction via Claude
- Implement `ClusteringEngine`:
  - Cloud: OpenAI `text-embedding-3-small`
  - Air gap: bundled MLX lightweight embedder
  - k-means, k via elbow, clamp [2, 8]
  - Write `cluster_id` on `arguments`, `centroid_text` on `clusters`
  - Prominence = cluster size / total arguments

## Definition of done

- 3-round debate completes in cloud and air gap modes
- Round 2 rebuttals reference specific round 1 points (manual QA on fixtures)
- `POSITION: updated` flag appears on at least one round-3 output during QA
- Arguments extracted and clustered; clusters visible in DB and plausible

## Exit gate

`/spec-check` scoped to §6.4.
