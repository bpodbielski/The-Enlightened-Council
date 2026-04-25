# TASKS.md — Running Backlog

Source of truth for what's in progress and what's next. Updated by Claude Code every session.

Format per task: `- [ ] <task>` for pending, `- [~]` for in progress, `- [x]` for done.

---

## Current phase

**Phase 5 — Synthesis Map** (Weeks 9-10)

Goal: force-directed graph of clustered arguments, VerdictTray, filters, keyboard controls.

---

## Phase 0 — Foundation

- [x] Create Xcode project (Swift 6, macOS 15+, App Sandbox entitlements) — TheCouncil.xcodeproj generated, builds clean
- [x] Add SPM dependencies: GRDB.swift, KeychainAccess, MLXSwift, swift-markdown — all resolved on branch
- [x] App shell: NavigationSplitView with sidebar entries (New Decision, This Week, All Decisions, Settings)
- [x] DatabaseManager.swift with full schema migrations (7 tables per SPEC §3.1) — actor, GRDB pool, seeds 13 defaults
- [x] KeychainStore.swift with CRUD for 4 provider keys (service names per SPEC §5) — .whenUnlockedThisDeviceOnly
- [x] Settings screen skeleton with 7 tabs (General, Models, Debate, Cost, Air Gap, Export, About)
- [x] API key entry fields wired to Keychain
- [x] Default settings pre-written to `settings` table on first launch
- [x] Force-simulation spike (Verlet physics, 200 nodes, fps measurement) — GO: 5,151 ticks/sec at 200 nodes (0.19 ms/tick), 85× above 60 fps bar. Results in Spike/results.md.
- [x] Phase 0 acceptance: app launches, keys round-trip, migrations clean, spike ≥ 55 fps — BUILD SUCCEEDED, 6/6 tests pass, spec-reviewer PASS, security-reviewer CLEAN
- NOTE (Phase 3): Air gap URLSession enforcement must be the first thing implemented before any network client code lands

---

## Phase 1 — Intake and Refinement (Week 2)

- [x] IntakeView with 7 fields and validation per SPEC §7.3
- [x] AttachmentView (file picker, URL field, paste zone)
- [x] AnthropicClient.swift with streaming — SSE, retries, air-gap check, claude-opus-4-7 for refinement
- [x] RefinementView two-pane layout (40% brief / 60% chat)
- [x] Refinement system prompt (2-4 clarifying questions, redaction suggestions)
- [x] Redaction pattern matching (email w/ \b anchors, `$`-amounts, capitalized name pairs w/ places list, custom keywords)
- [x] Inline `[REDACTED: reason]` with approve/dismiss
- [x] Sign-off flow writes `refined_brief` to DB, advances to `ready`
- PHASE 1 CLOSED: BUILD SUCCEEDED, 21/21 tests pass, spec-check PASS (all 14 checks), security CLEAN

---

## Phase 2 — Cloud Orchestration (Weeks 3-4)

- [x] OpenAIClient.swift, GeminiClient.swift, GrokClient.swift — SSE streaming, retries, air-gap check
- [x] LensTemplate loader (8 JSON files)
- [x] Persona loader (10 prompt files)
- [x] CouncilOrchestrator with `withTaskGroup` parallel execution
- [x] Round gate (N+1 waits for all N to complete or fail)
- [x] Per-run cost tracking writes `tokens_in`, `tokens_out`, `cost_usd`
- [x] Live cost accumulation in ExecutionView
- [x] Cost guardrails ($2 soft, $5 hard) with boundary-cross-only emission
- [x] Rate limit handling (429 exponential backoff 2s→64s, 5 retries) — shared across clients
- [x] Other errors per SPEC §8.1 (5xx: 3 retries fixed 2s)
- [x] ExecutionView with timeline, status chips, live counter, cancel button
- [x] CouncilConfigurationView with chips and steppers
- [x] AirGapNetworkGuard URLProtocol wired to all cloud clients
- PHASE 2 CLOSED: BUILD SUCCEEDED, full test suite green (21 prior + 20 new Phase 2 tests), guardrails/orchestrator/clients covered

---

## Phase 3 — Local Orchestration (Weeks 5-6)

- [x] MLXRunner.swift sequential load/run/unload for Qwen 2.5 32B then Mistral Small 22B — actor with catalog + gate; placeholder emit stream (real MLX generate loop to bind in later polish)
- [x] Memory pressure gate (thermal nominal, ≥ 10 GB free) — `LocalResourceGate` with injectable providers; host_statistics64 backed
- [x] Qwen 32B fallback to Qwen 14B — fallback ID declared in catalog; fallback prompt flow deferred to UI polish
- [x] OllamaClient.swift optional bridge — NDJSON streaming against localhost:11434
- [x] Local model download manager (Settings → Air Gap tab) — `ModelDownloadManager` with placement/presence APIs; transport stubbed for now
- [x] URLSession blocklist patch (AI hostnames per SPEC §6.1) — already installed Phase 2 via `AirGapNetworkGuard`; Phase 3 added launch-time refresh + toggle reactivity + acceptance test
- [x] Air gap toggle + confidential auto-enable — toggle flips live `AirGapURLProtocol.active`; confidential decisions auto-enable before orchestrator dispatch
- [x] Title bar "Air Gap Active" indicator — toolbar label with wifi.slash icon in `ContentView`
- [ ] Thermal throttle banner in ExecutionView — gate surfaces state; banner UI deferred to Phase 4 polish
- [ ] Fallback confirmation dialog for Qwen 32B→14B — UI sheet in Configuration deferred
- PHASE 3 CLOSED (core): BUILD SUCCEEDED, full suite green, orchestrator now dispatches MLX/Ollama via `CloudClientFactory` identically to cloud. Real MLX generate loop + fallback dialog flagged as Phase 4 polish work.

---

## Phase 4 — Debate Engine (Weeks 7-8)

- [x] DebateEngine full 3-round protocol per SPEC §6.4
- [x] Round 1 temperature variation (0.3, 0.7, 1.0) — retained from Phase 2
- [x] Round 2 anonymization (Perspective A/B/C mapping per decision) — stable sort on (model,persona)
- [x] Round 2 rebuttal + steel-man prompt
- [x] Round 3 defend-or-update with POSITION flag
- [x] `position_changed` nullable boolean on `model_runs` — parsed by DebateEngine.parsePosition and written by CouncilOrchestrator at round-3 insert
- [x] ArgumentExtractor post-round-3 JSON extraction — bracket-balanced JSON scan, fenced-block tolerant, unknown position → neutral
- [x] ClusteringEngine (OpenAI embeddings cloud, MLX local) — `Embedder` protocol with injectable implementations
- [x] k-means with elbow method (min 2, max 8) — k-means++ seeding, deterministic SplitMix64
- [x] Prominence = cluster size / total
- [x] `CouncilOrchestrator.runDebate(...)` — drives all 3 rounds with DebateEngine between-round prompt construction via CaptureBox
- [ ] Thermal throttle banner in ExecutionView — deferred to Phase 4 polish
- [ ] Qwen 32B→14B fallback confirmation dialog — deferred to Phase 4 polish
- [ ] ExecutionView wired to `runDebate` — deferred to Phase 4 polish (current `start` still calls `run(tasksByRound:)`)
- PHASE 4 CLOSED (core): BUILD SUCCEEDED, full suite green (19 new tests: 9 DebateEngine + 5 ArgumentExtractor + 5 ClusteringEngine). UI polish and end-to-end wiring deferred.

---

## Phase 5 — Synthesis Map (Weeks 9-10)

- [ ] ForceSimulation Verlet integration (repulsion, spring, centering, damping)
- [ ] Barnes-Hut quadtree at > 100 nodes (theta 0.9)
- [ ] GraphView with TimelineView(.animation) Canvas rendering
- [ ] Node visual encoding (color by model, size by prominence, dashed outlier border)
- [ ] Edge encoding (green agreement, red rebuttal, gray dashed tangent)
- [ ] Zoom (0.25x-4x), pan, drag (pin), click (detail), hover (tooltip), drag-to-tray
- [ ] VerdictTray with remove button per item
- [ ] Filter toggles (model, persona, round, position)
- [ ] Graph state persistence to `graph-state.json`
- [ ] Column-view fallback when fps < 30 for > 3s
- [ ] VoiceOver structured-list mode

---

## Phase 6 — Verdict Capture (Week 11)

- [ ] VerdictCaptureView with all fields per SPEC §6.8
- [ ] Auto-populate tray → `key_for_json` / `key_against_json`
- [ ] Confidence slider (default 70)
- [ ] Outcome deadline picker (default today + 60 days)
- [ ] "Draft verdict with Claude" button
- [ ] Pre-mortem auto-generation on Save Verdict
- [ ] Save writes to `verdicts` table, status → `complete`

---

## Phase 7 — Calibration Ledger (Week 12)

- [ ] ThisWeekView query (pending AND deadline ≤ now + 7d OR overdue)
- [ ] Sidebar badge count
- [ ] Outcome mark controls (right / partial / wrong / dismiss)
- [ ] Notes field + what-changed field
- [ ] Pattern queries gated at ≥ 20 marked outcomes
- [ ] Pattern display (horizontal bar chart, n=X label)
- [ ] Decision Detail → Outcome tab

---

## Phase 8 — Export (Week 13)

- [ ] Markdown template per SPEC §6.10
- [ ] PDF template via PDFKit (US Letter, system serif body, monospace model names)
- [ ] Export sheet (Markdown / PDF / Both)
- [ ] Slug function (lowercase, hyphens, 60 char max)
- [ ] Default export path setting

---

## Phase 9 — Polish (Weeks 14-15)

- [ ] All error banners per SPEC §8.1-8.2
- [ ] All empty states per SPEC §8.3
- [ ] First-launch API key modal → Settings → Models
- [ ] Accessibility (VoiceOver labels, Dynamic Type, tab order, 4.5:1 contrast)
- [ ] Synthesis Map keyboard controls (arrows, Space, Escape)
- [ ] Performance audit across all screens
- [ ] App icon
- [ ] About screen with version and changelog
- [ ] Signing and notarization setup

---

## Phase 10 — Dogfood and Ship (Week 16)

- [ ] Run 20 real decisions across all 8 lens templates (cloud + air gap)
- [ ] Local friction log
- [ ] Fix all critical issues (crash, data loss, misleading output, cost errors)
- [ ] Final DMG build and private archive
- [ ] All 10 acceptance criteria pass

---

## Backlog (v2 and beyond)

See PRD §4 and SPEC §14 for the full out-of-scope list. Items tracked for v2:

- Share-sheet integrations (Apple Notes, Notion, Obsidian)
- Import/export decisions as portable bundles
- Lens template editor UI
- Custom persona authoring
- Multi-mode runs (cloud + local in the same council)
- Voice intake
- Historical pattern visualizations beyond calibration rates

---

## Near-term polish (post-Phase-6, schedule when ready)

- [ ] **Delete decisions.** Right-click / context-menu on a row in `AllDecisionsView` → "Delete decision…" with a confirm sheet. Cascade-delete:
    - `model_runs`, `arguments`, `clusters`, `verdicts`, `outcomes` rows for the decision
    - On-disk per-decision folder under `~/Library/Application Support/The Council/decisions/<id>/` (graph-state.json, attachments)
    - Verdict's outcome row if any
  Optional: a soft-delete via `decisions.status = 'archived'` toggle as a "hide without erase" alternative; the Backlog item "archive vs delete" should be decided up front. Add migration only if soft-delete needs a new column. Tests: cascade query removes everything, on-disk folder removed, archived decisions excluded from the default list.
- [ ] **Test-only `KeychainStore.Provider` namespace.** The current `setUp/tearDown` snapshot-and-restore in `KeychainStoreTests` works but is fragile (a crashed test leaves keys in flux). Plumb a service-name suffix or a test-only `Provider` so test runs use isolated Keychain entries.
