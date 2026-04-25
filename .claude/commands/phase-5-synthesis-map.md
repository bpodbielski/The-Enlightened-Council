---
description: Phase 5 runbook — 60 fps force-directed graph with drag-to-tray verdict assembly
---

# Phase 5 — Synthesis Map

Weeks 9-10. Full detail: PLAN.md §Phase 5. SPEC cross-refs: §6.6, §11.

## Objectives

- Implement `ForceSimulation` with Verlet integration:
  - Repulsion `1/d²`, strength 200
  - Spring, ideal edge length 80px, strength 0.3
  - Centering gravity 0.05
  - Velocity damping 0.85
- Barnes-Hut quadtree (theta 0.9) engages automatically at > 100 nodes
- `GraphView` with `TimelineView(.animation)` Canvas render loop
- Draw order: edges → node circles → labels (skip labels < 8px at current zoom)
- Node encoding per SPEC §6.6: color by model, size by prominence, dashed outlier border
- Edge encoding: agreement `#34C759`, rebuttal `#FF3B30`, tangent `#8E8E93` dashed
- Interactions: pinch zoom 0.25×-4×, two-finger pan, drag (pins node), click (detail panel), hover tooltip, drag-to-tray
- `VerdictTray` on right: vertical list of dropped nodes + remove button
- Filter toggles (model, persona, round, position); hidden nodes remain in simulation
- Graph state persistence: serialize `{id, x, y, pinned}` to `graph-state.json` on verdict capture
- Fallback: if fps < 30 for > 3s, offer "Switch to column view" dialog
- VoiceOver mode: present arguments as structured list

## Definition of done

- Full argument graph renders for a completed decision
- 200-node graph holds ≥ 55 fps on M5 (target 60)
- Drag 5 nodes to tray; tray populates correctly
- Filter toggles hide/show correctly; layout stable
- Column-view fallback reachable and functional

## Notes

- Week-1 spike (`/force-graph-spike`) is the de-risking prerequisite for this phase.
- If the spike failed the fps bar, start the phase on the Barnes-Hut fallback path or the column-view alternative.

## Exit gate

Performance test run and `/spec-check` scoped to §6.6.
