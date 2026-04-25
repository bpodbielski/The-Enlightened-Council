# The Council

A native macOS app for running high-stakes strategic decisions through a structured multi-model AI debate.

One user. Personal tool. No cloud sync. No telemetry. Air gap mode for sensitive work.

---

## What it does

- You write a decision brief. Claude refines it through structured questioning.
- Three to four frontier models (Anthropic, OpenAI, Google, xAI) run a 3-round debate across multiple personas. Each persona defends, rebuts, and defends again.
- Arguments are extracted and clustered. A force-directed graph lets you drag arguments into a verdict tray.
- You capture a verdict with confidence, outcome deadline, and a Claude-generated pre-mortem.
- On the outcome deadline, the app asks you to mark right / partial / wrong. Patterns surface after 20 outcomes.

Air gap mode swaps cloud models for Qwen 2.5 32B and Mistral Small 22B (MLX, 4-bit, sequential).

---

## Why this exists

Single-model AI councils fail because of self-preference bias and mode collapse. Running four frontier models manually across web UIs is slow and leaves no calibration record. Existing tools do not combine multi-model diversity, structured debate, visual synthesis, and outcome-marked calibration on a native Mac app with air gap support.

---

## Platform

- macOS 15 or newer
- Apple Silicon (M5 target)
- 32 GB RAM (for the air gap sequential run)

Distributed as a signed and notarized DMG. No Mac App Store.

---

## Docs

- `PRD.md` — product requirements
- `SPEC.md` — technical specification (authoritative for implementation)
- `PLAN.md` — phase-by-phase plan
- `BUILD_PLAN.md` — one-page exec summary
- `CLAUDE.md` — operational instructions for Claude Code
- `STYLE.md` — Swift / SwiftUI conventions
- `TESTING.md` — test strategy
- `TASKS.md` — current backlog

---

## Build

```bash
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil -configuration Debug build
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil test
./scripts/build-dmg.sh
./scripts/notarize.sh
```

---

## License

Private. All rights reserved.
