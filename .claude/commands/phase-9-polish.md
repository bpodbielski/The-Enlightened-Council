---
description: Phase 9 runbook — ship-quality polish, accessibility, signing, and notarization
---

# Phase 9 — Polish

Weeks 14-15. Full detail: PLAN.md §Phase 9. SPEC cross-refs: §8, §9, §10, §11.

## Objectives

- Wire every API error banner per SPEC §8.1-8.2
- "Partial results" banner on Synthesis Map for failed runs, with re-run option for failed only
- All empty states per SPEC §8.3
- Onboarding: first-launch modal (no API keys) → Settings → Models; one-time "Start here" tooltip on New Decision
- Accessibility:
  - VoiceOver labels and hints on every interactive element
  - Dynamic Type (no fixed font sizes)
  - Full keyboard tab order
  - Synthesis Map keyboard: arrows select, Space adds to tray, Escape deselects
  - Minimum contrast 4.5:1
  - Focus ring visible on all interactive elements in keyboard nav
- Performance audit: profile all screens; fix anything below 60 fps
- App icon and About screen (version, build, changelog)
- Signing and notarization setup (Developer ID, `xcrun notarytool`)

## Definition of done

- All happy paths feel finished; no placeholder UI visible
- Accessibility audit: VoiceOver traverses every screen without dead ends
- Signed and notarized DMG mounts cleanly on a fresh macOS 15 install

## Exit gate

Full suite + accessibility audit + DMG smoke test.
