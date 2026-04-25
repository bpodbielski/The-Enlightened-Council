# CLAUDE.md — Operational Instructions for Claude Code

This file is Claude Code's primary orientation. Read the entire file before starting any task.

---

## Project identity

**Name:** The Council
**Type:** Native macOS application
**User:** One user (Ben Podbielski). Personal tool. Not for distribution.
**Purpose:** Run high-stakes strategic decisions through a structured multi-model AI debate and capture a calibrated verdict for later outcome review.

---

## Must-read docs, in order

1. **PRD.md** — product requirements, problem, goals, user flow, features at product level
2. **SPEC.md** — technical spec. Authoritative for schema, file paths, model IDs, protocol formats, performance budgets, and acceptance criteria
3. **PLAN.md** — phase-by-phase implementation plan with definitions of done
4. **TASKS.md** — current backlog; update as you work
5. **STYLE.md** — Swift 6 and SwiftUI conventions for this project
6. **TESTING.md** — test strategy, harnesses, and gates per phase

When PRD and SPEC disagree on an implementation detail, SPEC wins. When SPEC and PLAN disagree on a schedule or task sequence, PLAN wins for sequencing and SPEC wins for definition of done content.

---

## Hard rules (never violate)

- **No telemetry. No analytics. No crash reporting.** No network traffic except intentional AI API calls and user-triggered URL fetches.
- **No iCloud sync. No cloud account system. No team features.** Single-user, single-machine.
- **API keys live in Keychain only.** Never write a key to the database, a file, a log, or a response body. Keychain accessibility class: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Air gap is load-bearing.** When `air_gap_enabled = true` or `sensitivity_class = confidential`, block every cloud AI hostname at the URLSession layer before any council run. Confidential class auto-enables air gap.
- **No prompts or responses logged outside the SQLite database.** No `print()` of user content in release builds. No crash reports capturing body text.
- **Schema changes go through migrations.** Never mutate an existing migration after it ships. Append a new migration instead.
- **SPEC is authoritative for:** database schema, file paths, Keychain service names, model IDs, debate protocol formats, performance budgets, error behavior, acceptance criteria.
- **Never delete or force-push shared branches.** Never bypass hooks or signing.

---

## Platform and stack

- macOS 15 or newer
- Swift 6 (strict concurrency)
- SwiftUI (no UIKit bridging except where unavoidable)
- Xcode + Swift Package Manager
- GRDB.swift (SQLite)
- KeychainAccess (Keychain wrapper)
- MLXSwift (local inference)
- Swift Markdown (Apple)
- PDFKit (system framework)

App Sandbox entitlements:
- `com.apple.security.network.client` (disabled in air gap via URLSession blocklist)
- Application Support read/write
- User-selected file read/write (scoped bookmarks for attachments)

---

## Repo layout (matches SPEC §4)

```
TheCouncil/
├── App/
├── Database/
│   └── Migrations/
├── Keychain/
├── Models/
├── APIClients/
├── LocalInference/
├── Orchestration/
├── ForceGraph/
├── Features/
│   ├── Intake/
│   ├── Refinement/
│   ├── Configuration/
│   ├── Execution/
│   ├── SynthesisMap/
│   ├── VerdictCapture/
│   ├── DecisionDetail/
│   ├── ThisWeek/
│   └── Settings/
└── Resources/
    ├── LensTemplates/     # 8 JSON files (see Resources/LensTemplates/)
    └── Personas/          # 10 versioned prompt files (see Resources/Personas/)
```

---

## Build, test, run

```bash
# Build
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil -configuration Debug build

# Run all tests
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil test

# Run a single test target
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil -only-testing:TheCouncilTests/DebateEngineTests test

# Format and lint (pre-commit hook runs these)
swiftformat .
swiftlint --strict

# Release DMG pipeline
./scripts/build-dmg.sh
./scripts/notarize.sh
```

---

## Development workflow

1. Pick the current phase from **PLAN.md**. Scan its definition of done.
2. Read the related SPEC section(s).
3. Check **TASKS.md** for current state of that phase.
4. Work one task at a time. Keep commits small and scoped.
5. Write tests first for parsers, orchestrators, extractors, and migration code.
6. Run `swiftformat`, `swiftlint`, and the full test suite before committing.
7. Update **TASKS.md** with status.
8. Close a phase only when every item in PLAN's definition of done passes.

---

## Phase gates (summary of SPEC §13)

v1 ships when all pass:
- 8 lens templates run end-to-end, cloud and air gap
- Force graph ≥ 60 fps with 200 nodes on M5
- Markdown and PDF exports match on-screen verdict
- Calibration ledger surfaces due verdicts
- Air gap blocks every cloud AI hostname (proxy-verified)
- Cost guardrails: $2 soft, $5 hard, zero silent overruns
- Local sequential run (Qwen 32B then Mistral 22B, 3 rounds, 4 personas, 3 samples) ≤ 15 min on M5 32 GB
- 20-decision stress test with zero crashes
- Zero telemetry in production (network-monitor verified)
- Signed notarized DMG mounts on clean macOS 15

---

## Data paths (authoritative)

- Database: `~/Library/Application Support/The Council/council.db`
- Per-decision files: `~/Library/Application Support/The Council/decisions/<uuid>/`
- Local model weights: user-configurable (default `~/Library/Application Support/The Council/models/`)

---

## Slash commands and subagents

Reusable slash commands live under `.claude/commands/`:
- `phase-0-foundation` through `phase-10-ship` — phase runbooks
- `spec-check` — verify current branch against SPEC §13
- `force-graph-spike` — Week-1 physics de-risking exercise
- `redaction-check` — scan a brief for PII patterns per SPEC §6.7
- `airgap-verify` — run the air gap network enforcement test

Specialized subagents live under `.claude/agents/`:
- `swift-engineer` — feature code, test-first
- `test-writer` — parsers, orchestrators, extractors
- `spec-reviewer` — reads SPEC.md and grades a PR against it
- `graph-performance-specialist` — Phase 5 physics and render tuning
- `security-reviewer` — scans for telemetry, key leaks, air gap violations

---

## What to do when unsure

- SPEC.md is the first place to look for implementation detail.
- If SPEC is silent, read PRD.md for intent.
- If both are silent, write the assumption in a comment, add a TODO in TASKS.md, and proceed with the simplest option that preserves the hard rules.
- Never guess API keys, model IDs, Keychain service names, or file paths. All are in SPEC.

---

## Prohibited

- Adding any SPM dependency not listed in SPEC §2 or explicitly approved by the user
- Calling any third-party service beyond the four named AI providers and local MLX / optional Ollama
- Writing anything outside the project directory or the app's Application Support folder
- Using Combine for new code (Swift Concurrency only)
- UIKit or AppKit bridging unless SwiftUI blocks the requirement
