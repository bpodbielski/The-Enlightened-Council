# TESTING.md — Test Strategy

---

## Test pyramid

- **Unit tests** — parsers, extractors, prompt builders, schema migrations, slug generator, redaction patterns, cost calculation, temperature mapping
- **Integration tests** — orchestrator against stubbed clients, debate engine end-to-end against canned responses, air gap URLSession enforcement
- **UI tests** — critical path: intake → refinement → run → synthesis map → verdict → outcome
- **Performance tests** — force simulation fps, local run wall-clock, database read latency

---

## Framework

XCTest only. No third-party test frameworks.

---

## Test targets

- `TheCouncilTests` — unit and integration
- `TheCouncilUITests` — XCUITest critical path

---

## Test naming

`func test_<subject>_<condition>_<expected>()`

Example: `test_debateEngine_roundTwo_anonymizesLabels()`

---

## Required tests per phase

### Phase 0

- Migration runner applies all migrations on a fresh database
- Migration runner is idempotent
- KeychainStore round-trips a value per provider
- Force-sim spike records fps at 50, 100, 200 nodes

### Phase 1

- Intake validation rejects short question and short success criteria
- Redaction patterns catch emails, dollar amounts, two-word capitalized pairs
- Refinement streaming appends tokens to the conversation state
- Sign-off writes `refined_brief` and advances status

### Phase 2

- Each cloud client parses a canned success response
- Each cloud client surfaces a 401 as `APIError.unauthorized`
- Orchestrator runs N tasks in parallel, collects all results
- Orchestrator marks a failed run as `error` and continues
- 429 retry budget respected (max 5, max wait 64s)
- Cost accumulation matches sum of stored `cost_usd`
- Soft warn at $2 surfaces non-blocking dialog
- Hard pause at $5 surfaces blocking dialog

### Phase 3

- MLXRunner loads and unloads a small model fixture
- Memory pressure gate does not proceed below 10 GB free
- URLSession blocklist rejects each hostname in the air gap list
- Confidential sensitivity auto-enables air gap

### Phase 4

- Round 2 anonymization produces a consistent Perspective A/B/C mapping per decision
- Round 3 parse flips `position_changed` when POSITION: updated appears
- ArgumentExtractor handles malformed JSON without crashing
- k-means elbow method picks k within [2, 8]

### Phase 5

- 200-node graph holds ≥ 55 fps for 5 seconds (target 60)
- Barnes-Hut engages at 101 nodes
- Drag to tray adds and remove button clears
- Filter toggles hide nodes without altering physics state
- Column-view fallback triggers when fps drops below 30 for > 3 seconds

### Phase 6

- Verdict save writes all required fields
- Pre-mortem generation handles Claude timeout gracefully
- Re-opening a verdict shows stored fields

### Phase 7

- ThisWeek query returns pending verdicts within 7 days or overdue
- Outcome marking writes to `outcomes` and advances `outcome_status`
- Pattern query gated: returns empty when marked outcomes < 20
- Pattern query returns rates by lens when ≥ 20

### Phase 8

- Slug function: lowercase, hyphens, strip specials, 60 char truncate
- Markdown export matches template
- PDF export opens in Preview with expected metadata

### Phase 9

- VoiceOver traversal visits every screen without dead-end
- Air gap enforcement test passes (proxy-verified in CI-optional harness)

---

## Fixtures

`TheCouncilTests/Fixtures/` contains:

- `canned-anthropic-success.json`
- `canned-openai-success.json`
- `canned-gemini-success.json`
- `canned-grok-success.json`
- `canned-rate-limit-429.json`
- `canned-unauthorized-401.json`
- `canned-malformed-json.txt`
- `canned-refined-brief.md`
- `canned-round-1-outputs.json`
- `canned-round-2-outputs.json`
- `canned-round-3-outputs.json`
- `canned-extracted-arguments.json`

---

## Mocking

- Each `StreamingChatClient` has a `MockStreamingChatClient` conforming implementation
- Injection via initializer arguments. No swizzling, no runtime substitution
- MLXRunner has a `MockMLXRunner` for deterministic local test runs

---

## Performance budgets (gate at PR time)

| Test | Budget | Source |
|---|---|---|
| Force sim at 200 nodes | ≥ 55 fps for 5s | SPEC §11 |
| Local run wall-clock | ≤ 15 min | SPEC §11 |
| Markdown export | < 1s | SPEC §11 |
| PDF export | < 3s | SPEC §11 |
| DB read, 500 decisions | < 100ms | SPEC §11 |
| App launch to Home | < 2s | SPEC §11 |

---

## CI strategy

Local-first. Optional GitHub Actions for macOS runners with self-hosted option for MLX smoke tests.

On every commit:
- `swiftformat --lint`
- `swiftlint --strict`
- `xcodebuild test` on `TheCouncilTests` target

On phase close:
- Full UI test suite
- Performance suite
- Air gap proxy verification (manual or self-hosted)

---

## What not to test

- SwiftUI view internal rendering (compose-level only)
- Third-party library internals (GRDB, MLXSwift)
- macOS system behavior (Keychain permissions dialog, notarization)
