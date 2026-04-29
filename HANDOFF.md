# The Council — Handoff Document

**Date:** 2026-04-26
**Session scope:** Phase 8 (Export) — closes on top of Phases 0–7
**Build status:** ✅ BUILD SUCCEEDED
**Test status:** ✅ 168 tests pass (33 suites) + 1 opt-in diagnostic skipped by default
**Repository:** [github.com/bpodbielski/The-Enlightened-Council](https://github.com/bpodbielski/The-Enlightened-Council) — public, default branch `main`, remote `origin` (HTTPS)

## Phase 8 — Export (CLOSED, core)

| Deliverable | Notes |
|---|---|
| `Slug` enum | `Slug.slugify(_:)` lowercases, folds Unicode diacritics, collapses any non-`[a-z0-9]` run into a single hyphen, trims leading/trailing hyphens, then truncates to 60 chars (and re-trims if the cut landed mid-separator). `Slug.filename(question:date:)` composes `<slug>-YYYY-MM-DD` using `en_US_POSIX` so file names are locale-stable. Pure functions — every test runs without GRDB. |
| `ExportPayload` | Bundle struct — decision + verdict + optional outcome + model_runs. Computed `modelPanel` (insertion-order-preserving deduped list of `modelName`) and `totalCostUsd` (sum of `costUsd ?? 0` across runs). Both renderers consume this so they share the same input contract. |
| `MarkdownRenderer` | Pure `enum`. `render(_ payload:)` produces the exact SPEC §6.10 template: H1 question, metadata block (Date/Lens/Confidence/Outcome deadline), then H2 sections for Verdict / Arguments For / Arguments Against / Risk / Blind Spot / Opportunity / Pre-mortem / Test, plus a horizontal-rule footer with `Model panel: …` and `Total cost: $0.00`. Empty arg lists render `_(none)_`. Outcome section appears only when `verdict.outcomeStatus.isTerminal && != .dismissed`. |
| `PDFRenderer` | Pure `enum`. Builds an `NSAttributedString` body with system-serif body, bold H2s, monospace for the model panel/cost summary. Walks `CTFramesetter` via successive `CFRange`s to paginate; each page draws header (question · date · lens) + footer (`<model panel> · $cost` left-aligned, `Page X of Y` right-aligned) outside the body rect. US Letter (612×792 pt). Returns `Data` directly — `PDFDocument(data:)` round-trips cleanly. Two-pass pagination (count pages first, then render with the final count) so footers can show `X of Y`. |
| `ExportEngine` | `actor`. `export(decision:format:to:)` loads the latest verdict + outcome + runs in one GRDB read, hands them to whichever renderer(s) the user picked, and writes `<slug>-YYYY-MM-DD.{md,pdf}` atomically into the destination. `defaultExportDirectory()` reads `settings.export_default_path` (default `~/Desktop`, expands `~`). `ExportError` is exhaustive: `.verdictNotFound(decisionId:)`, `.writeFailed(path:underlying:)`. Throws (with the path) on missing/locked destinations. |
| `ExportFormat` enum | `.markdown / .pdf / .both`, `Sendable`, `CaseIterable`. Drives the segmented picker. |
| `ExportSheet` (SwiftUI) | Modal sheet: format segmented picker, destination row with "Choose…" button (`NSOpenPanel`), Export button (`borderedProminent`, default action), result block with per-file "Reveal" buttons (`NSWorkspace.activateFileViewerSelecting`). `@Observable @MainActor ExportSheetViewModel` owns destination + format + result + error state. Async export runs on the actor; the view shows a `ProgressView` while in flight. |
| `DecisionDetailView` toolbar | Conditional `Export` toolbar item — only renders when `selectedTab == .verdict && viewModel.verdict != nil`. Tap loads the default export dir (async) and presents the sheet. |
| `VerdictCaptureViewModel` | `encodeArgumentTexts` and `decodeArgumentTexts` flipped to `nonisolated` so the renderers (which are non-MainActor) can call them. Both are pure JSON helpers — actor isolation was overkill. |
| `gen_xcodeproj.py` | Added `f_export_slug`, `f_export_markdown`, `f_export_pdf`, `f_export_engine`, `f_export_sheet` (and three test entries) plus a new `grp_export` group under `grp_thecouncil` and `grp_tests_export` under `grp_tests_root`. |

### Phase 8 test coverage (28 new tests; 30 suites → 33)
- `SlugTests` (11) — lowercase, hyphen substitution, collapsed runs, punctuation strip, leading/trailing trim, empty input, accented Unicode (`naïve résumé` → `naive-resume`), emoji + CJK as separators, 60-char cap, no trailing hyphen after truncation, `Slug.filename` composes slug + date in en_US_POSIX.
- `MarkdownRendererTests` (9) — every required H2 header present, metadata block formatted, arguments rendered as bullets, model panel + cost line present, empty-args fallback, outcome section appears for `.right`, omitted for `.dismissed` and `.pending`, model panel preserves insertion order.
- `PDFRendererTests` (7) — non-empty bytes, parseable by `PDFKit.PDFDocument`, mediabox is 612×792 (US Letter), long content paginates to >1 page, extracted text contains every required header, header+footer text contains question + both models + cost, page marker reads `Page X of Y`.

### Phase 8 implementation notes

- **PDFKit vs Core Text.** Used Core Text directly for body layout because `PDFKit.PDFPage` doesn't accept attributed-string content; PDFKit owns parsing/loading on the read side. The `PDFRenderer` is the only file that touches `AppKit` — used purely for `NSAttributedString` + `NSFont` + `NSColor` to drive Core Text. SwiftUI is unaffected.
- **Two-pass pagination.** Footers need `Page X of Y` so the renderer paginates the framesetter once to count pages, then renders the same ranges with that count. Cost is small (CTFramesetter caches the typesetter; the second pass is the one that actually emits PDF bytes).
- **Model panel ordering.** Insertion order, not alphabetic, because the user typically thinks "I had Anthropic, then OpenAI, then xAI on the panel" in the order configured. Dedupe via `Set<String>` insertion on iteration.
- **`nonisolated static` JSON helpers.** Originally lived on `VerdictCaptureViewModel` (a `@MainActor` class) because that's where the verdict form needs them. Renderers are not main-actor; making the helpers `nonisolated` is a one-line fix and avoids extracting them into a third file just to share. They're pure functions — no captured state.

---


## Phase 7 — Calibration Ledger (CLOSED, core)

| Deliverable | Notes |
|---|---|
| `OutcomeStatus.dismissed` | Added the missing case + `isTerminal` computed property. Schema accepts it (Migration001 column comment already lists `dismissed`); the enum just hadn't caught up. |
| `Outcome` memberwise init | Added — Codable + custom `init(row:)` was suppressing synthesis (same fix shape as Phase 6's Verdict). |
| `OutcomeMarkingService` | `actor`. Owns the SPEC §6.9 state machine: `pending → right \| partial \| wrong \| dismissed`, terminal. `mark(verdictId:result:actualNotes:whatChanged:)` inserts an `outcomes` row + flips `verdicts.outcome_status` in a single GRDB write transaction. `dismiss(verdictId:)` updates the verdict status only (no outcomes row, since "dismissed" has no result to record). Both paths call a private `assertPending` guard that throws `OutcomeMarkingError.alreadyTerminal` if a terminal verdict is re-marked, and `verdictNotFound` for unknown ids. Injectable `now` clock + `DatabaseManager`. |
| `CalibrationService` | `actor` with `static patternThreshold = 20`. `gate()` returns `.insufficient(marked, threshold)` or `.ready(marked)`. `calibrationByLens()` and `calibrationByReversibility()` issue a SQL aggregate joining `outcomes → verdicts → decisions`, sorted by descending `right_rate` then ascending bucket label for stable display. `groupColumn` is hard-coded per method (never user input) to keep the dynamic SQL safe. |
| `CalibrationPatternsView` | Sheet presented from This Week's toolbar. Uses Apple's `Charts` framework (system, no SPM addition). Below threshold → "Patterns appear after 20 marked outcomes. You have N so far." At/above threshold → two horizontal bar charts ("By lens template", "By reversibility") with `n=X` annotations. `chartXScale(domain: 0...1)` + percent axis. |
| `ThisWeekViewModel` | `@Observable @MainActor`. Window predicate: `outcome_status = 'pending' AND (outcome_deadline <= now+7d OR outcome_deadline < now)`. Sort: ascending deadline. Per-row `notesDraft` and `whatChangedDraft` dictionaries collect the inline text fields. `mark(verdictId:result:)` and `dismiss(verdictId:)` call `OutcomeMarkingService` then reload. Static `fetchDueCount(db:now:)` powers the sidebar badge without instantiating the VM. |
| `ThisWeekView` | Replaces the placeholder. Per-row card: question + verdict text + lens/confidence/deadline labels + "Overdue" pill when applicable, two text fields (notes, what changed), and four buttons (Right green / Partial yellow / Wrong red / Dismiss destructive). Toolbar `Calibration` button opens `CalibrationPatternsView` in a sheet. Empty-state message is friendly when nothing's due. |
| `DecisionDetailView` | 5-tab segmented control: Brief / Council / Map / Verdict / Outcome (per SPEC §7.9). Brief = static metadata + refined brief. Council = scrollable transcript of `model_runs` (model · persona · round · sample) with truncated response cards and a "Maintained / Updated" pill on round-3 runs. Map = stub explaining the live Synthesis Map flow (full read-only graph rebuild deferred — flagged in TASKS.md). Verdict = read-only verdict brief (decoded `key_for_json`/`key_against_json` via `VerdictCaptureViewModel.decodeArgumentTexts`). Outcome = either the marking form (when `outcomeStatus == .pending`) or a record display (when terminal). |
| `ContentView` integration | `.decisionDetail(Decision)` destination + `navigateToDecisionDetail(decision:)` helper. `AllDecisionsView` rewrapped each card in a `Button(buttonStyle: .plain)` that fires `onSelectDecision` → navigation. Sidebar `This Week` row shows a red badge with the due+overdue count from `thisWeekDueCount`, refreshed in `.task` and on every `.onChange(of: viewModel.destination.navigationKey)` so it stays accurate after marking outcomes. |
| `gen_xcodeproj.py` | Added `Calibration/` group at app level + `f_outcome_marking`, `f_calibration_service`, `f_calibration_view` source entries; extended `Features/ThisWeek/` and `Features/DecisionDetail/` with the new VM and Detail view; added `grp_tests_thisweek` + `grp_tests_calibration` test groups. |

### Phase 7 test coverage (19 new tests)

- `OutcomeMarkingServiceTests` — 6 cases: `statusForResult` mapping for all 3 results; `OutcomeStatus.isTerminal` for all 5 cases; mark→insert+update via SQL contract; dismiss writes status but no outcomes row; terminal verdicts can't transition (invariant the actor's guard relies on); schema accepts `'dismissed'` and `Verdict.init(row:)` decodes it.
- `CalibrationServiceTests` — 9 cases: bucket math (zero / partial / all-right / all-wrong); `patternThreshold == 20`; `CalibrationGate.isReady` true only for `.ready`; lens query groups + sorts (1.0 → 0.5 → 0.0); reversibility query aggregates across lenses; gate fires at exactly 20 (boundary).
- `ThisWeekQueryTests` — 4 cases: includes deadlines within +7d and the boundary; includes overdue; excludes every terminal status (`right`/`partial`/`wrong`/`dismissed`); a dismiss cleanly removes a verdict from the next query.

### Phase 7 architectural decisions

| Decision | Rationale |
|---|---|
| `OutcomeMarkingService` is an `actor`, not a `struct` | The state-machine guard (`assertPending`) and the cascade write (insert outcomes + update verdict status) must run inside the same `db.write {}` transaction. An actor gives us a single isolation domain to serialise concurrent mark/dismiss calls without an extra lock. |
| `dismissed` writes no `outcomes` row | An outcome is a result; dismissal is the absence of one. Storing a sentinel `OutcomeResult.dismissed` would dilute calibration math (you'd have to filter it out everywhere). Calibration queries `WHERE result = 'right'` already ignore dismissed verdicts naturally. |
| `CalibrationService.fetchBuckets` builds dynamic SQL with a column name interpolated | The `groupColumn` argument is hardcoded at the public-method layer (`calibrationByLens()` passes `"d.lens_template"`; `calibrationByReversibility()` passes `"d.reversibility"`), so it never touches user input. Keeps the SQL DRY without exposing an injection surface. |
| Apple Charts (system framework) chosen for bar visualisation | macOS 13+; no SPM dependency. Imports as `import Charts`. Hand-rolled `Canvas` bars would have given more control but added 100+ lines for no functional gain at this scale. |
| Decision Detail Map tab is intentionally a stub in Phase 7 | A fully read-only `GraphView` requires re-running the post-processing pipeline against persisted arguments + clusters (or persisting the simulation state more deeply). Not in Phase 7's definition of done; tracked as TASKS.md polish. The other 4 tabs (Brief / Council / Verdict / Outcome) are all live. |
| Sidebar badge counted via a `static` query, not the live `ThisWeekViewModel` | The badge needs to refresh from anywhere (after marking, after navigation), even when the This Week screen isn't mounted. A static count query keeps the dependency one-way: `ContentViewModel` → DB, no shared mutable VM. |

---



## Post-Phase-6 hotfixes (live)

End-to-end run failed with "couldn't connect" against OpenAI. A diagnostic harness pinpointed two distinct bugs and one infrastructure trap.

### Diagnostic harness — `APIConnectivityDiagnostic`

[TheCouncilTests/Diagnostics/APIConnectivityDiagnostic.swift](TheCouncilTests/Diagnostics/APIConnectivityDiagnostic.swift). Opt-in (gated by `RUN_DIAGNOSTICS` env var, propagated via `TEST_RUNNER_RUN_DIAGNOSTICS=1`). Reads keys from Keychain, probes Anthropic + OpenAI with both SPEC and known-current model IDs, captures raw HTTP status + body, and maps each failure to a human diagnosis (401 = key, 404 = model ID, 400 = body shape, etc.). Probes use the production `OpenAIClient.buildBody` so they exercise the real request shape.

Run command:
```
TEST_RUNNER_RUN_DIAGNOSTICS=1 xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil \
  -destination "platform=macOS" \
  -only-testing:TheCouncilTests/APIConnectivityDiagnostic test
```

Keep this around — it is the single fastest way to triage any future "the app can't talk to a provider" complaint.

### Fix 1 — `KeychainStore` trims whitespace on save and load

Root cause: a clipboard paste of the OpenAI API key in Settings → Models carried a trailing `\n`. The newline embedded itself in the `Authorization: Bearer <key>\n` header; OpenAI silently treated the request as unauthenticated and returned 401 "You didn't provide an API key". Diagnostic surfaced raw key bytes (`[..., 0x0A]`) and proved the issue by re-probing with a trimmed copy → 200.

[KeychainStore.swift](TheCouncil/Keychain/KeychainStore.swift): `save()` strips `whitespacesAndNewlines` before write. `load()` does the same on read (defensive, so any keys saved before this shipped self-heal on the next read). Two new tests cover the strip-on-save and trim-on-load paths.

### Fix 2 — `OpenAIClient` switches `max_tokens` ⇄ `max_completion_tokens` per model

Even with a clean key, the GPT-5 family rejected our requests:
> `"Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead."`

The newer GPT-5 / o-series models also reject custom `temperature` (only the default is accepted).

[OpenAIClient.swift](TheCouncil/APIClients/OpenAIClient.swift:158): `buildBody` is now `static` and routes via `usesCompletionTokensParam(model:)` (matches `gpt-5*`, `o1*`, `o3*`, `o4*`):
- new family → `max_completion_tokens`, omit `temperature`
- older family (`gpt-4*` etc.) → `max_tokens` + `temperature`

`OpenAIClientTests` gained 4 cases covering both branches.

### Fix 3 (infra) — `KeychainStoreTests` no longer wipes user keys

`KeychainStoreTests` writes to the **production** Keychain service names (no test-only namespace). Its previous teardown deleted those entries — meaning every test run nuked any real keys the user had saved through the app. After my first test pass against the diagnostic, the user's keys were gone and the diagnostic reported MISSING.

[KeychainStoreTests.swift](TheCouncilTests/Keychain/KeychainStoreTests.swift): added `setUpWithError` snapshot of any pre-existing key per provider, and `tearDownWithError` deletion-then-restore so the user's keys survive a test run unchanged. A cleaner long-term fix would be to plumb a test-only `KeychainStore.Provider` namespace or service-name suffix; that's tracked in TASKS.md backlog.

### Test count change

Phase 6 closed at 117 tests. Post-fix:
- `+2` Keychain trim tests
- `+4` OpenAI `buildBody` body-shape tests
- `+1` `APIConnectivityDiagnostic` (opt-in; skipped by default)
= **123 total, 122 active passing, 1 skipped.**

---



## Phase 6 — Verdict Capture (CLOSED, core)

| Deliverable | Notes |
|---|---|
| `VerdictCaptureViewModel` | `@Observable @MainActor`. Single VM owning the full verdict form: `verdictText`, `confidence` (default 70), `risk`, `blindSpot`, `opportunity`, `testAction/Metric/Threshold`, `outcomeDeadline` (default `now + 60d` via injected clock), `preMortem`. Auto-populates `keyForArguments` / `keyAgainstArguments` from `trayItems` filtered by position on init. Injectable `StreamingChatClient` (default `AnthropicClient.shared`) and `DatabaseManager` (default `.shared`). State flags: `isDrafting`, `isGeneratingPreMortem`, `showPreMortemSheet`, `isSaving`, `didSave`, `errorMessage`. |
| `draftVerdict()` | Calls `claude-sonnet-4-6` (temperature 0.4) with `buildVerdictPrompt(brief:forArgs:againstArgs:)` — embeds refined brief + numbered FOR/AGAINST tray arguments, asks for 2–4 sentence recommendation. Drains `streamChat` into `verdictText`. Trims whitespace on completion. Failure path sets `errorMessage`. |
| `generatePreMortem()` | Called from "Save Verdict" button. Sends verdict text + confidence + outcome-deadline date string to `claude-sonnet-4-6` (temperature 0.6) using `buildPreMortemPrompt(...)` per SPEC §6.8. Streams result into `preMortem`, surfaces editable sheet via `showPreMortemSheet = true` even on failure (so user can hand-author). |
| `save()` | Atomic write inside `db.write { ... }`: inserts `Verdict` row (status `.pending`), updates `decisions.status = 'complete'` for the same `decisionId`. Calls `graphViewModel?.saveGraphState()` after successful insert. Sets `didSave = true` to drive navigation back to All Decisions. Empty-text guard rejects with inline error. |
| `encodeArgumentTexts` / `decodeArgumentTexts` | `static` JSON helpers for `key_for_json` / `key_against_json`. Encode strips to bare text array; decode tolerates malformed input by returning `[]`. Unicode-safe (round-trips emoji + accents). |
| `Verdict` memberwise init | Added explicit initializer (Codable struct didn't synthesize one because of the custom `init(row:)`). Same fix shape as Phase 4's Argument init. |
| `VerdictCaptureView` | Single-column scroll form per SPEC §7.8 / §6.8. Sections: question (read-only), key arguments FOR/AGAINST with "From council" badge, Risk/Blind Spot/Opportunity text fields, Verdict editor + "Draft with Claude" button, Confidence slider 0–100, Outcome Deadline `DatePicker`, Test Action/Metric/Threshold fields. Footer: Cancel + "Save Verdict" (kicks off pre-mortem flow). Sheet for pre-mortem editing with "Confirm Save" → calls `save()`. Error alert bound to `errorMessage`. |
| `GraphView.onCaptureVerdict` | Optional callback. When set, renders an "Capture Verdict" `.borderedProminent` button in the canvas top-trailing overlay. Hidden when nil (e.g., a future read-only Map tab in Decision Detail). |
| `ContentView` navigation | New `.verdictCapture(Decision, GraphViewModel)` case in `NavigationDestination` (with `navigationKey`). `navigateToVerdictCapture(decision:graphViewModel:)` helper on the VM. `.synthesisMap` now wires `onCaptureVerdict` → `navigateToVerdictCapture`. `.verdictCapture` constructs the view, routes Save → All Decisions, Cancel → back to Synthesis Map. |
| `AllDecisionsView` (real) | Replaces stub. New `AllDecisionsViewModel` (`@Observable @MainActor`) loads `[DecisionCard]` via `static fetchCards(db:)` — joins `decisions` to its latest `verdict` for confidence display. Sort: `created_at DESC`. UI: progress view → empty state → `LazyVStack` of `DecisionCardRow`. Each row shows question (2-line), status chip (color per `DecisionStatus`), date, lens template, and confidence (if a verdict exists). `.refreshable` reloads. |
| `gen_xcodeproj.py` | Added `f_verdict_capture_vm`, `f_verdict_capture_view`, `f_test_verdict_capture` entries; new `grp_feat_verdict` and `grp_tests_verdict` groups wired into `grp_features` and `grp_tests_root`. |

### Phase 6 test coverage (16 new tests)
- `VerdictCaptureTests` — 15 cases:
    - `populateFromTray` partitions FOR/AGAINST and excludes neutral items
    - default deadline lands at `now + 60d`; default confidence is 70
    - `buildVerdictPrompt` includes brief + numbered FOR/AGAINST + "2–4 sentence" instruction; empty arrays render "(none pinned)"
    - `buildPreMortemPrompt` includes verdict, confidence (`%`), full deadline date string, "pre-mortem", "3–5 bullets"
    - `encodeArgumentTexts` round-trip; empty produces `"[]"`; unicode (`naïve résumé 🌟`) survives
    - `draftVerdict` sets `verdictText` from streamed chunks (`"Ship " + "the change " + "in Q2." → "Ship the change in Q2."`)
    - `draftVerdict` failure sets `errorMessage` and leaves text untouched
    - `generatePreMortem` populates `preMortem` and toggles `showPreMortemSheet = true`
    - `verdictRow_writesAllFieldsAndDecisionStatusCompletes` — full-schema GRDB roundtrip + `decisions.status = 'complete'` update
    - `verdictRow_queryableByDeadline` — `WHERE outcome_deadline <= ? AND outcome_status = 'pending'` returns the right count
- `AllDecisionsViewTests` — 1 case: query orders by `created_at DESC` (Q2, Q1, Q0).

### Phase 6 implementation note: Swift-6 stub conformance gotcha
Test file declared `private struct StubStreamingChatClient: StreamingChatClient` and the compiler reported "candidate has non-matching type" despite identical signatures. Root cause: `AnthropicClientTests.swift` declares its own inline `struct ChatMessage`, so unqualified `[ChatMessage]` resolves to the test-target type, not `TheCouncil.ChatMessage`. Fixed by qualifying as `[TheCouncil.ChatMessage]` in stub signatures. Stubs are now `final class … @unchecked Sendable` with `nonisolated func streamChat`. Future verdict-style tests should follow the same pattern.

---

## Phase 5 — Synthesis Map (CLOSED, core)

| Deliverable | Notes |
|---|---|
| `ForceSimulation` | `@unchecked Sendable` class. Verlet integrator: repulsion (Barnes-Hut when n>100), spring edges (rest=80px, k=0.3), centering (0.05), damping (0.85). `canvasSize` used for centering target. `tick()` runs one step. `SimNode` has `id`, `argumentId`, `pos`, `vel`, `pinned`. `SimEdge.EdgeKind`: `.agreement`, `.rebuttal`, `.tangent`. |
| `BarnesHutQuadtree` | `BHNode` class. `insert(idx:px:py:positions:)` and `force(for:px:py:theta:strength:)`. Center-of-mass maintained on insert. Barnes-Hut criterion: `bsize/d < theta`. Leaf self-exclusion via `bodyIndex == idx` guard. |
| `GraphViewModel` | `@Observable @MainActor`. `GraphNode` with `radius = max(6, min(20, prominence * 30))`. `TrayItem`, `GraphNodeState` (Codable for JSON persistence). `GraphFilter.isVisible`. `load(arguments:clusters:assignments:decisionId:)` builds sim nodes + edges. `tick(frameTimestamp:)` advances physics + records fps. FPS fallback: `showColumnFallback = true` after 180 frames below 30 fps. Graph state persists to `~/Library/Application Support/The Council/decisions/<id>/graph-state.json`. |
| `GraphView` | `TimelineView(.animation)` + `Canvas`. 3-pass draw: edges (agreement green/rebuttal red/tangent gray dashed) → node fills → labels. Filter bar (round + position menus) + fps display. FPS fallback dialog. Detail panel on node selection. **Phase 6 addition:** optional `onCaptureVerdict` closure renders top-trailing prominent button. `GraphAccessibilityList` for VoiceOver. |
| `VerdictTray` | Drag-to-tray panel. `TrayItemRow` with remove button and position badges. `ColumnFallbackView` — three-column (For/Against/Neutral) list for low-fps fallback. |
| `ExecutionViewModel` | Rewired to `orchestrator.runDebate(...)`. Collects `completedRuns` on each `.runCompleted` event. `runPostProcessing()`: filters round-3 runs → `ArgumentExtractor` → `ClusteringEngine` (with `PassthroughEmbedder`) → writes `Argument` rows → writes `Cluster` rows → builds `GraphViewModel`. `synthesisReady: Bool` + `graphViewModel: GraphViewModel?` drive navigation. `isExtracting: Bool` shows extraction overlay. |
| `PassthroughEmbedder` | Stub using `SeededRNG` for deterministic 64-dim unit vectors. Real cloud (OpenAI `text-embedding-3-small`) and local (MLX) embedders are deferred to a later polish pass. |
| `ExecutionView` | `ThermalBanner`: polls `ProcessInfo.thermalState` every 5s, shows orange/red banner for `.serious`/`.critical`. Extraction overlay with `ProgressView`. Navigation: `synthesisReady` change → `onSynthesisReady(gvm)` or `onComplete()`. |
| `CouncilConfigurationView` | Qwen 32B memory gate: `checkLocalMemoryThenRun()` calls `LocalResourceGate().check(minFreeBytes: 20 GB)` when `qwen-2.5-32b-instruct` is enabled. Alert offers "Use Qwen 14B instead" → `viewModel.substituteQwen14B()`. |
| `ContentView` | `.synthesisMap(Decision, GraphViewModel)` destination renders `ColumnFallbackView` or `GraphView(viewModel: graphVM, onCaptureVerdict:)` based on `graphVM.useColumnView`. `.verdictCapture(Decision, GraphViewModel)` added in Phase 6. |
| `gen_xcodeproj.py` | Fixed: removed embedded `\n` from all 14 section-header `w()` calls (caused triple-newline parse error). Fixed: `BarnesHutQuadtreeTests` entry was outside `children = (...)` block in ForceGraph test group. `LastSwiftUpdateCheck` and `LastUpgradeCheck` set to `2600`. |

### Phase 5 test coverage
- `BarnesHutQuadtreeTests` — 5 cases.
- `GraphViewModelTests` — 8 cases.

---

## Phase 4 — Debate Engine (CLOSED, core)

| Deliverable | Notes |
|---|---|
| `DebateEngine` | `enum` of stateless helpers. `anonMap(for:)` assigns stable "Perspective A/B/C" labels keyed on `(model.id, persona.id)` sorted lexicographically. `buildRound2Tasks` / `buildRound3Tasks` build round-N task sets from prior round's `ModelRun`s. Temperature per sample reuses `CouncilConfigurationViewModel.temperature(forSample:)`. |
| `parsePosition(in:)` | Regex `(?im)^\s*position\s*:\s*(maintained\|updated)\b`. Returns `true`/`false`/`nil`. |
| `ArgumentExtractor` | `actor`. Streaming JSON extraction; bracket-balanced scan tolerates fenced code blocks; unknown `position` falls back to `.neutral`. |
| `ClusteringEngine` | `actor` with injectable `Embedder` protocol. k-means++ seeding, deterministic `SplitMix64(seed: 42)`, sweeps k ∈ [2, min(8, n)], picks elbow via largest inertia drop. |
| `CouncilOrchestrator.runDebate(...)` | Round-driven debate flow. Round-1 tasks from caller; rounds 2/3 built dynamically. |
| `position_changed` writeback | Round-3 parse writes `Bool?` to `model_runs.position_changed`. |
| `Argument` memberwise init | Explicit initializer. |

### Phase 4 test coverage
- `DebateEngineTests` — 9 cases.
- `ArgumentExtractorTests` — 5 cases.
- `ClusteringEngineTests` — 5 cases.

---

## Phase 3 — Local Orchestration (CLOSED, core)

| Deliverable | Notes |
|---|---|
| `LocalResourceGate` | Pure struct. `check(minFreeBytes:) -> .ok / .insufficientMemory / .thermalThrottle`. Default provider uses `host_statistics64`. Refuses on `.serious` or `.critical` thermal state. |
| `MLXRunner` | `actor` conforming to `StreamingChatClient`. Catalog: Qwen 2.5 32B (fallback → 14B), Qwen 2.5 14B, Mistral Small 22B. Real generate loop is stubbed. |
| `OllamaClient` | `actor` conforming to `StreamingChatClient`. NDJSON streaming. Localhost is NOT on the air-gap blocklist. |
| `ModelDownloadManager` | Placement under `~/Library/Application Support/The Council/models/<id>/`. Transport stub. |
| Air gap enforcement | `AirGapNetworkGuard.refresh(from:)` at app launch; settings toggle flips `AirGapURLProtocol.active` live; confidential decisions auto-enable. |
| Title-bar indicator | Orange "Air Gap Active" label in `ContentView` toolbar `.principal` slot. |
| `CloudClientFactory` | `.localMLX` → `MLXRunner.shared`, `.localOllama` → `OllamaClient.shared`. |

### Phase 3 test coverage
- `LocalResourceGateTests` — 5 cases.
- `MLXRunnerTests` — 4 cases.
- `OllamaClientTests` — 4 cases.
- `AirGapNetworkGuardTests` — 5 cases.
- `ModelDownloadManagerTests` — 3 cases.

---

## Phase 2 — Cloud Orchestration (CLOSED)

| Deliverable | Notes |
|---|---|
| `AirGapNetworkGuard` | `URLProtocol` subclass blocking 4 provider hostnames. Installed into every client's `URLSessionConfiguration`. |
| `OpenAIClient`, `GeminiClient`, `GrokClient` | `actor`s conforming to `StreamingChatClient`. SSE streaming, retry policy, 120s timeout, key-from-Keychain. |
| `LensTemplate` + `LensTemplateLoader` | Decodes JSON; enforces one of 8 valid IDs. |
| `Persona` + `PersonaLoader` | YAML-front-matter parser. 10 personas. |
| `ModelSpec` + `CloudClientFactory` | Per-provider input/output cost per 1M tokens. |
| `CostGuardrails` | `.softWarnCrossed` / `.hardPauseCrossed` only at boundary crossings. Defaults: $2 / $5. |
| `CouncilOrchestrator` | `actor`. Parallel round execution via `withTaskGroup`. |
| `CouncilConfigurationView` + VM | Model/persona chips, rounds/samples steppers (1–5), estimated cost. |
| `ExecutionView` + VM | Per-run timeline, status chips, live $/token counter. |
| Navigation | `ContentView.NavigationDestination` Refinement → `.configuration(Decision)` → `.execution(...)`. |

### Phase 2 test coverage
- 20 tests across `OpenAIClientTests`, `GeminiClientTests`, `GrokClientTests`, `LensTemplateLoaderTests`, `PersonaLoaderTests`, `CostGuardrailTests`, `CouncilOrchestratorTests`.

---

## Phase 0 / Phase 1 — Foundation & Intake (CLOSED)

See git history; covered by `DatabaseMigrationTests`, `KeychainStoreTests`, `ForceSimulationTests`, `IntakeValidationTests`, `RedactionEngineTests`, `AnthropicClientTests`.

---

## Current file tree

```
TheCouncil.xcodeproj/
Spike/
TheCouncil/
  App/
    TheCouncilApp.swift
    ContentView.swift                 ← +.verdictCapture destination, navigateToVerdictCapture()
  APIClients/
    StreamingChatClient.swift   AnthropicClient.swift
    OpenAIClient.swift                                ← +max_completion_tokens for gpt-5*/o-series
    GeminiClient.swift          GrokClient.swift        OllamaClient.swift
    AirGapNetworkGuard.swift
  Database/
    DatabaseManager.swift
    Migrations/Migration001_InitialSchema.swift
  Calibration/                            ← NEW (Phase 7)
    OutcomeMarkingService.swift            ← state machine + cascade writes
    CalibrationService.swift               ← gate + pattern queries
    CalibrationPatternsView.swift          ← Apple Charts horizontal bars
  Export/                                  ← NEW (Phase 8)
    Slug.swift                             ← filename slug + date helper
    MarkdownRenderer.swift                 ← SPEC §6.10 markdown template
    PDFRenderer.swift                      ← Core Text → CGPDFContext, US Letter
    ExportEngine.swift                     ← actor; load + render + write
    ExportSheet.swift                      ← modal: format + destination
  Features/
    Configuration/
    DecisionDetail/
      AllDecisionsView.swift               ← +onSelectDecision callback
      DecisionDetailView.swift             ← Phase 7 5-tab; +Export toolbar (Phase 8)
    Execution/
    Intake/
    Refinement/
    Settings/
    SynthesisMap/
      GraphViewModel.swift   GraphView.swift   ← +onCaptureVerdict
      VerdictTray.swift
    ThisWeek/
      ThisWeekViewModel.swift              ← NEW (Phase 7)
      ThisWeekView.swift                   ← rebuilt in Phase 7 (was a stub)
    VerdictCapture/                        ← NEW (Phase 6)
      VerdictCaptureViewModel.swift        ← +nonisolated JSON helpers (Phase 8)
      VerdictCaptureView.swift
  ForceGraph/
    ForceSimulation.swift   BarnesHutQuadtree.swift
  Keychain/KeychainStore.swift                       ← +trim whitespace on save & load
  LocalInference/
    LocalResourceGate.swift  MLXRunner.swift  ModelDownloadManager.swift
  Models/
    Decision.swift  ModelRun.swift  Argument.swift  Cluster.swift
    Verdict.swift   ← +memberwise init, +OutcomeStatus.dismissed (Phase 7)
    Outcome.swift   ← +memberwise init (Phase 7)
    AppSettings.swift
  Orchestration/
    LensTemplate.swift  LensTemplateLoader.swift
    Persona.swift       PersonaLoader.swift
    ModelSpec.swift     CostGuardrails.swift
    CouncilOrchestrator.swift  DebateEngine.swift
    ArgumentExtractor.swift    ClusteringEngine.swift
TheCouncilTests/
  APIClients/   Database/   ForceGraph/   Intake/
  Keychain/KeychainStoreTests.swift                  ← +trim tests, +setUp/tearDown user-key restore
  LocalInference/   Orchestration/   Refinement/   SynthesisMap/
  VerdictCapture/VerdictCaptureTests.swift           ← NEW (Phase 6)
  Calibration/                                       ← NEW (Phase 7)
    OutcomeMarkingServiceTests.swift
    CalibrationServiceTests.swift
  ThisWeek/ThisWeekQueryTests.swift                  ← NEW (Phase 7)
  Export/                                            ← NEW (Phase 8)
    SlugTests.swift
    MarkdownRendererTests.swift
    PDFRendererTests.swift
  Diagnostics/APIConnectivityDiagnostic.swift        ← post-Phase-6 (opt-in, RUN_DIAGNOSTICS=1)
scripts/
  gen_xcodeproj.py   ← +Export group + sources
```

**Total production Swift:** ~9,989 lines across 62 source files
**Total test Swift:** ~3,429 lines across 31 test files, 169 tests (33 suites; 1 opt-in diagnostic skipped by default)

---

## Hard constraints (never violate)

These are locked in `CLAUDE.md` and enforced by the security-reviewer:

- **No telemetry, analytics, or crash-reporting SDKs.** Zero. Not even in debug.
- **API keys in Keychain only.** Service names per SPEC §5. Accessibility: `.whenUnlockedThisDeviceOnly`. Never logged, never in DB.
- **No SPM dependencies** beyond GRDB.swift, KeychainAccess, MLXSwift, swift-markdown.
- **Swift 6 strict concurrency.** `SWIFT_STRICT_CONCURRENCY = complete` is set in the Xcode project.
- **No Combine.** `AsyncStream`/`AsyncThrowingStream`/`async-await` only.
- **Never mutate a shipped migration.** Append `Migration002_...` instead.
- **Air gap is load-bearing.** `AirGapNetworkGuard` (URLProtocol) is the URLSession blocklist — installed into every cloud client's `URLSessionConfiguration`. Confidential decisions auto-enable it before dispatch.

---

## Key architectural decisions (Phase 6 additions)

| Decision | Rationale |
|---|---|
| `VerdictCaptureViewModel` accepts `StreamingChatClient` (protocol), not `AnthropicClient` directly | Keeps the VM testable with stubs; production callers get `AnthropicClient.shared` by default. Same pattern as `ClusteringEngine` taking `Embedder`. |
| Pre-mortem flow uses a sheet (modal) rather than inline auto-fill | SPEC §6.8 mandates the user sees + can edit pre-mortem before final save. Sheet enforces a confirmation step ("Confirm Save"); inline fill would let an accidental Enter commit unedited Claude output. |
| `AllDecisionsView` query joins each decision to its latest verdict via subquery, not a single `LEFT JOIN` | GRDB row decoding is per-table; fetching `Decision` rows and then per-row pulling `confidence` keeps decoding clean and avoids a custom row aggregator. Acceptable cost at single-user scale (≤200 decisions). |
| `GraphView.onCaptureVerdict` is optional, not a separate parameter | Allows the same `GraphView` to render in both interactive Synthesis Map (button shown) and a future read-only Decision Detail Map tab (button hidden). |
| Verdict pre-mortem prompt formats the deadline with `DateFormatter(.long)` | Tests can assert "2026" appears for a 2026 timestamp; locale-stable enough for the personal-use-only scope without a custom formatter. |

---

## Open flags and forward-looking notes

| Flag | Phase it lands | Detail |
|---|---|---|
| Decision Detail Map tab | Polish (post-Phase-7) | Currently shows a placeholder. A read-only graph requires either re-running the post-processing pipeline against persisted args/clusters or persisting more of the simulation state. Other 4 tabs (Brief/Council/Verdict/Outcome) are live. |
| Live Verdict view "Export" button | Phase 9 polish | Phase 8 added the Export toolbar item to the `DecisionDetailView` Verdict tab. The post-capture `VerdictCaptureView` (immediately after Save) does not yet surface an Export action — round-trip via All Decisions for now. Trivial to add when we want it. |
| Concrete `Embedder` implementations | Polish (future) | Cloud OpenAI `text-embedding-3-small`, local MLX sentence-transformers. `PassthroughEmbedder` is the stub. |
| Token estimation is char/4 heuristic | Future polish | Replace with provider-reported usage. |
| MLX generate loop | Polish (future) | `MLXRunner` emits a deterministic placeholder; real on-device inference is deferred. |
| Delete decisions | Polish (post-Phase-6) | `AllDecisionsView` has no delete affordance. TASKS.md "Near-term polish" tracks the cascade-delete spec (DB rows + on-disk decision folder + exported files). Decide archive-vs-hard-delete before implementing. |
| `KeychainStore.Provider` test namespace | Polish (post-Phase-6) | `KeychainStoreTests` shares production service names with the running app; tests now snapshot+restore but a proper test-only namespace would be more robust. Tracked in TASKS.md. |
| PDF page-marker right-alignment uses string-width approximation | Phase 9 polish | The footer's "Page X of Y" right-aligns by measuring the rendered string width with the system font and shifting origin. Works for the short page-number string; if we ever right-align variable-length text we should switch to `CTLineGetTypographicBounds` for precision. |

---

## Phase 8 — What to do next

**Phase 9 — Polish (Weeks 14–15)**
Full detail: `PLAN.md §Phase 9`

### Starting checklist

1. **Error and empty states.** All API error banners per SPEC §8.1–8.2 wired to real UI. "Partial results" banner on the Synthesis Map for failed runs. Empty-state copy for All Decisions, This Week, Synthesis Map (no args), and the calibration patterns sub-20-marked screen (already in place).
2. **Onboarding.** First-launch modal when no API keys are configured → routes to Settings → Models. One-time "Start here" tooltip over `New Decision`.
3. **Accessibility.** VoiceOver labels/hints on every control; Dynamic Type honored (no fixed sizes); full keyboard tab order; Synthesis Map keyboard navigation (arrow-key node selection, Space to add to tray, Escape to deselect); 4.5:1 contrast minimum; visible focus rings.
4. **Performance audit.** Profile each screen, fix anything dropping below 60 fps. Force-graph spike already passed; the audit is mostly transitions + scroll perf.
5. **App icon + About screen.** Version, build number, changelog summary.
6. **Signing and notarization.** Developer ID + `xcrun notarytool` workflow. Wire `scripts/build-dmg.sh` and `scripts/notarize.sh` (currently stubs).
7. **Live Verdict view Export action.** Add the same Export toolbar item to the post-capture `VerdictCaptureView` so users can export immediately after Save without round-tripping through All Decisions.
8. **Phase 9 exit gate** — every happy path feels finished, no placeholder UI visible, accessibility audit traverses every screen via VoiceOver without dead ends, signed-and-notarized DMG mounts on a clean macOS 15.

### Prerequisites before starting Phase 9

- `/spec-check` scoped to SPEC §8 + §13 (acceptance criteria 1, 5, 9, 10).
- `security-reviewer` on Phase 8 — no new network/Keychain code (Export is filesystem-only) → likely a no-op, but worth a pass since signing/notarization is in scope for Phase 9.
- Manual end-to-end smoke: drive a complete decision (Intake → Refinement → Configuration → Execution → Synthesis Map → Verdict Capture → Decision Detail → Export both formats) and confirm the Markdown opens in Typora/Obsidian and the PDF opens in Preview.

### Files to add in `gen_xcodeproj.py` before starting Phase 9
```
# Likely additions (refine as scope solidifies):
("f_onboarding",   "Features/Onboarding/OnboardingView.swift"),
("f_partial_banner", "Features/SynthesisMap/PartialResultsBanner.swift"),
```
No new test groups expected; Phase 9 is largely UI polish + manual review.

---

## Build and test commands

```bash
# Build
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil -configuration Debug \
  -destination "platform=macOS" build

# Run all unit tests
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil \
  -destination "platform=macOS" -only-testing:TheCouncilTests test

# Run a single test class
xcodebuild -project TheCouncil.xcodeproj -scheme TheCouncil \
  -destination "platform=macOS" \
  -only-testing:TheCouncilTests/VerdictCaptureTests test

# Add new files to project (after editing gen_xcodeproj.py)
python3 scripts/gen_xcodeproj.py
```

---

## Phase gate rules (from CLAUDE.md)

- Every phase closes only when its PLAN.md definition-of-done items all pass
- Run `/spec-check` scoped to the phase's SPEC sections before closing
- Run `security-reviewer` before closing any phase that adds network or Keychain code
- **Commit and push to `origin/main` at every phase close.** After build + tests are green and HANDOFF.md is updated, stage everything (`git add .`), commit with a message of the shape `Phase N — <title> (<status>)` summarising the phase deliverable, and `git push origin main`. The remote is the canonical source of truth between sessions; no phase is "closed" until its work is on GitHub. Mid-phase WIP commits are also welcome — push whenever a coherent slice lands.
- Stop and ask before starting the next phase — one checkpoint per phase boundary
- SPEC is authoritative for schema, model IDs, hostnames, paths, performance budgets, acceptance criteria
- When SPEC is silent on an implementation question, stop and ask rather than guess; log the question in TASKS.md before pausing

---

## 10 v1 ship-gate acceptance criteria (SPEC §13)

For reference — all must pass before Phase 10 declares v1:

1. All 8 lens templates run end-to-end in cloud and air gap modes without crashes
2. Force-directed graph renders at ≥ 60 fps with 200 nodes on M5 (**de-risked: spike result 5,151 ticks/sec**)
3. Verdict brief exports to Markdown and PDF with visual parity to on-screen view
4. Calibration ledger surfaces due verdicts in This Week
5. Air gap toggle blocks all cloud network traffic (verify via proxy or Little Snitch)
6. Cost guardrails: soft warning at $2, hard pause at $5, no silent overruns
7. Sequential local run (Qwen 32B → Mistral 22B, 3 rounds, 4 personas, 3 samples) ≤ 15 min on M5 32 GB
8. No crashes across a 20-decision stress test
9. No telemetry in production build (verify via network monitor)
10. Signed and notarized DMG mounts cleanly on a clean macOS 15 install
