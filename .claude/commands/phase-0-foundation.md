---
description: Phase 0 runbook — empty app runs, settings persist, database initializes, force-sim spike passes
---

# Phase 0 — Foundation

Week 1. Full detail: PLAN.md §Phase 0. SPEC cross-refs: §1, §2, §3, §4, §5.

## Objectives

- Create Xcode project with Swift 6 + macOS 15+ target + App Sandbox entitlements
- Wire SPM dependencies: GRDB.swift, KeychainAccess, MLXSwift, swift-markdown
- Build app shell (NavigationSplitView, 4 sidebar entries)
- Implement `DatabaseManager` with migrations for all 7 tables per SPEC §3.1
- Implement `KeychainStore` with CRUD for 4 provider keys, service names per SPEC §5
- Build Settings skeleton with 7 tabs
- Wire API key entry per provider
- Write default settings to `settings` table on first launch
- Run the force-simulation spike (1-2 days, goal: ≥ 55 fps at 200 nodes)

## Definition of done

- App launches and shows sidebar + home screen
- API keys round-trip through Keychain across restarts
- All migrations run cleanly; test writes to each table succeed
- Force-sim spike hits ≥ 55 fps at 200 nodes (or mitigation planned and logged in TASKS.md)

## Steps

1. Run `/force-graph-spike` first. Do not proceed until fps meets the bar or risk is logged.
2. Create the Xcode project. Enable App Sandbox.
3. Add SPM deps. Commit the `Package.resolved`.
4. Implement migrations in `Database/Migrations/`. One file per version.
5. Implement `DatabaseManager` with a read/write API per STYLE.md.
6. Implement `KeychainStore`. Add unit tests for round-trip.
7. Scaffold Settings tabs. Wire key entry to Keychain.
8. Write default settings on first launch.
9. Run the Phase 0 test suite: all migrations + keychain round-trip.
10. Update TASKS.md.

## Exit gate

Run `/spec-check` scoped to Phase 0 tasks before closing the phase.
