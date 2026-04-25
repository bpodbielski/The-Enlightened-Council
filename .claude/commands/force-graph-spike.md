---
description: Week-1 de-risking spike for the Synthesis Map force simulation
---

# force-graph-spike

1-2 day spike in Week 1. Non-negotiable gate for Phase 5.

## Goal

Prove we can render 200 nodes at ≥ 55 fps on M5 32 GB using SwiftUI `Canvas` inside `TimelineView(.animation)`.

## Steps

1. Create `Spike/ForceGraphSpike` Swift package (not the main app).
2. Implement `ForceSimulation` with Verlet physics:
   - Repulsion: `1/d²`, strength 200
   - Spring: ideal 80px, strength 0.3
   - Centering: 0.05
   - Damping: 0.85
3. Add Barnes-Hut quadtree (theta 0.9) that engages automatically at 100 nodes.
4. Render in `Canvas` inside `TimelineView(.animation)`:
   - Draw edges first, nodes second, labels last
   - Skip labels < 8px at current zoom
5. Generate 50, 100, 200 node graphs with random edges.
6. Measure fps for each node count across 10 seconds using `CADisplayLink`-equivalent counter on macOS.
7. Record results in `Spike/results.md`.

## Go / no-go

- **Go:** ≥ 55 fps at 200 nodes. Proceed to Phase 5 as planned.
- **Borderline (40-54 fps):** Proceed but plan Barnes-Hut refinement and consider column-view as primary for > 150 nodes.
- **No-go (< 40 fps):** Switch Phase 5 plan to column-view primary + small graph mode (< 50 nodes). Update TASKS.md and PLAN.md §Phase 5.

## Output

- Write `Spike/results.md` with fps numbers at each node count
- Update TASKS.md Phase 0 spike item with outcome
- If borderline or no-go, open a TODO in PLAN.md §Phase 5 with the chosen mitigation
