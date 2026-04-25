# The Council — Implementation Plan

**Version:** 1.0
**Date:** 2026-04-21
**Owner:** Ben Podbielski
**Source docs:** PRD.md · SPEC.md
**Supersedes:** BUILD_PLAN.md (now an executive summary pointing to this doc)
**Target:** v1.0 ship in 16 weeks (single developer)

---

## Overview

Ten sequential phases with two parallel overlaps. Each phase has a concrete definition of done before the next begins. Total estimate: 12–16 weeks. Highest-risk item (force graph) gets a spike in Week 1 to de-risk Phase 5.

---

## Phase 0 — Foundation
**Week 1 | Goal: Empty app runs, settings persist, database initializes**

### Tasks

- Xcode project: Swift 6, macOS 15+ target, App Sandbox (`com.apple.security.network.client`, Application Support read/write)
- SPM packages: `GRDB.swift`, `KeychainAccess`, `MLXSwift`, `swift-markdown`
- App shell: `NavigationSplitView` sidebar + main content (entries: New Decision, This Week, All Decisions, Settings)
- Full SQLite schema via `DatabaseManager.swift` migrations (all 7 tables: `decisions`, `model_runs`, `arguments`, `clusters`, `verdicts`, `outcomes`, `settings`)
- `KeychainStore.swift`: CRUD for 4 provider API keys (service names: `com.benpodbielski.thecouncil.apikey.*`)
- Settings screen skeleton with all 7 tabs: General, Models, Debate, Cost, Air Gap, Export, About
- API key entry fields per provider wired to Keychain
- Default settings pre-written to `settings` table on first launch
- **Spike:** 1–2 day force-simulation prototype (`ForceSimulation.swift`) — Verlet physics, 200 nodes, measure fps. Go/no-go before proceeding.

### Definition of done

- App launches and shows sidebar + home screen
- API keys round-trip through Keychain across restarts
- All database migrations run cleanly; test writes to each table succeed
- Force-simulation spike hits ≥55 fps at 200 nodes (or risk is logged and mitigation planned)

---

## Phase 1 — Intake and Refinement
**Week 2 | Goal: A decision enters the system and produces a refined brief**

### Tasks

- `IntakeView`: single-column form, 7 fields per SPEC §7.3 — `TextEditor` for question (min 20 chars) and success criteria (min 10 chars), `Picker` for decision type, segmented controls for reversibility/time horizon/sensitivity
- `AttachmentView`: file picker + URL field + paste zone
- Inline note for Confidential class: "Air gap mode will be enforced."
- `Decision` Swift model + GRDB insert; status advances `draft → refining` on submission
- `AnthropicClient.swift`: streaming chat via Anthropic API, shared by refinement and council
- `RefinementView`: two-pane layout — left 40% brief draft, right 60% streaming conversation
- Refinement system prompt: 2–4 clarifying questions in one turn, redaction suggestions, structured brief output
- Redaction suggestion: regex patterns for email, `$`-amounts, capitalized two-word pairs; render inline as `[REDACTED: reason]` with approve/dismiss
- Sign-off button: writes `refined_brief` to DB, advances status to `ready`, routes to Council Configuration

### Definition of done

- Submit form → refinement chat opens with Claude
- Claude asks clarifying questions; conversation is streaming
- Redaction suggestions appear for PII/financials and can be approved or dismissed
- Sign-off produces a stored `refined_brief`; decision status is `ready`

---

## Phase 2 — Cloud Model Orchestration
**Weeks 3–4 | Goal: Four cloud models run in parallel and return stored output**

### Tasks

- `OpenAIClient.swift`, `GeminiClient.swift`, `GrokClient.swift`: async streaming HTTP clients
- `LensTemplate` loader: parse 8 JSON files from `Resources/LensTemplates/`
- `Persona` loader: parse 10 prompt files from `Resources/Personas/`
- `CouncilOrchestrator.swift`: `withThrowingTaskGroup` parallel execution per SPEC §6.5
- Round gate: round N+1 waits for all round-N tasks to complete or fail before starting
- Per-run token and cost tracking: write `tokens_in`, `tokens_out`, `cost_usd` to `model_runs`
- Live cost accumulation: sum `cost_usd` for active decision, publish to `ExecutionView`
- Cost guardrails: soft warning at $2 (non-blocking), hard pause at $5 (blocking override dialog)
- Rate limit handling: 429 → exponential backoff (2s start, ×2, max 5 retries, max 64s), then mark `error`
- Other error handling per SPEC §8.1 (401, 5xx, timeout, invalid JSON, empty response)
- `ExecutionView`: timeline with per-round rows, per-model status chips (`Waiting → Running → Done | Failed`), live cost counter, cancel button (saves partial results)
- `CouncilConfigurationView`: model panel chips, persona chips, rounds/samples steppers, estimated cost display

### Definition of done

- Single-round run with frontier set (4 models) completes; all outputs stored in `model_runs`
- Cost tracked live and matches sum of stored `cost_usd`
- Simulated 429 degrades gracefully — other models continue, failed run marked `error`
- Cancel mid-run saves partial results and advances to Synthesis Map with warning banner

---

## Phase 3 — Local Model Orchestration
**Weeks 5–6 | Goal: Air gap mode runs both local models end-to-end**

### Tasks

- `MLXRunner.swift`: sequential load → run → unload for Qwen 2.5 32B (4-bit) then Mistral Small 22B (4-bit)
- Memory pressure gate between models: poll `mach_host_self()` and `ProcessInfo.thermalState`; proceed only when thermal nominal and available RAM ≥ 10 GB
- Fallback: if Qwen 32B fails to load, offer Qwen 14B class with user confirmation dialog
- Thermal throttle banner: pause inference, show banner, resume automatically
- `OllamaClient.swift`: optional HTTP bridge to `http://localhost:11434` (toggled in Settings)
- Local model download manager in Settings → Air Gap tab: download, verify checksum, unload, delete, directory path picker
- Air gap network enforcement: patch `URLSession` shared configuration to block AI hostnames at app launch and before every council run (block list per SPEC §6.1)
- Air gap toggle in Settings; confidential sensitivity class auto-enables air gap
- Title bar `"Air Gap Active"` indicator when enabled

### Definition of done

- Air gap on → run a 3-round decision with Qwen then Mistral; both complete, outputs stored
- Sequential RAM handoff verified: model 2 does not load until model 1 fully unloads
- No outbound connections to AI hostnames during air gap run (verify via proxy or Little Snitch)
- Confidential decision auto-routes to local models with no cloud option available

---

## Phase 4 — Debate Engine
**Weeks 7–8 | Goal: Three-round structured debate produces clustered, labeled arguments**

### Tasks

- `DebateEngine.swift`: full 3-round protocol per SPEC §6.4
  - Round 1: `(model × persona × sample)` combinations with temperature 0.3 / 0.7 / 1.0
  - Round 2: distribute anonymized round-1 outputs (strip model/persona labels → `Perspective A/B/C`), rebuttal + steel-man prompt
  - Round 3: each persona gets its own round-1 output + round-2 rebuttals targeting it; produce `POSITION: maintained/updated` with explicit change flag
- `position_changed` boolean indexed on `model_runs` (nullable, set during round-3 parse)
- Anonymization: consistent label mapping per decision, stored in memory during orchestration run
- `ArgumentExtractor.swift`: post-round-3 aggregation call to Claude with structured JSON extraction prompt; parse into `arguments` table
- `ClusteringEngine.swift`: 
  - Cloud mode: OpenAI `text-embedding-3-small`
  - Air gap mode: bundled lightweight embedder via MLX
  - k-means clustering, k by elbow method (min 2, max 8)
  - Write `cluster_id` to `arguments`, `centroid_text` to `clusters`
  - Prominence = (cluster size) / (total arguments); write to `arguments.prominence`

### Definition of done

- 3-round debate completes in both cloud and air gap modes
- Round-2 rebuttals reference specific round-1 points (manual QA)
- `POSITION: updated` flag appears in at least one round-3 output during QA run
- Arguments extracted and written to DB; clusters visible and plausible

---

## Phase 5 — Synthesis Map
**Weeks 9–10 | Goal: Force-directed graph renders at 60 fps; verdict assembled by dragging nodes**

### Tasks

- `ForceSimulation.swift`: full physics per SPEC §6.6
  - Verlet integration: repulsion (`1/d²`, strength 200), spring (ideal 80px, strength 0.3), centering gravity (0.05), velocity damping (0.85)
  - Barnes-Hut quadtree (theta 0.9) auto-engaged at >100 nodes
- `GraphView.swift`: `TimelineView(.animation)` render loop on `Canvas`
  - Draw order: edges → node circles → labels (skip labels < 8px at current zoom)
  - Node visual encoding per SPEC §6.6 (color by model, size by prominence, dashed border for outliers >1.5σ)
  - Edge encoding: agreement green `#34C759`, rebuttal red `#FF3B30`, tangent gray `#8E8E93`
- `GraphViewModel.swift`: drives simulation tick, publishes node positions
- Interactions: pinch-zoom (0.25×–4×), two-finger pan, node drag (pins node), click (argument detail panel), hover tooltip, drag-to-tray
- `VerdictTray`: right panel list of dropped nodes; remove button per item
- Filter toggles: model, persona, round, position — hidden nodes stay in physics simulation
- Graph state persistence: serialize `{id, x, y, pinned}` to `graph-state.json` on verdict capture
- Fallback: if fps <30 for >3s, offer "Switch to column view" dialog (three columns: For / Against / Neutral)
- VoiceOver mode: present arguments as structured list when VoiceOver active

### Definition of done

- Full argument graph renders for a completed decision
- 200-node graph holds ≥55 fps on M5 (target 60 fps)
- Drag 5 nodes to tray; tray populates correctly
- Filter toggles hide/show correctly; layout stays stable
- Column-view fallback reachable and functional

---

## Phase 6 — Verdict Capture
**Week 11 | Goal: Verdict brief saved with confidence, pre-mortem, and test**

### Tasks

- `VerdictCaptureView`: single-column form, all fields per SPEC §6.8
- Auto-populate from verdict tray: for-position nodes → `key_for_json`, against-position nodes → `key_against_json`
- Confidence slider 0–100, default 70
- `DatePicker` for outcome deadline, default today + 60 days
- "Draft verdict with Claude" button: sends refined brief + tray arguments to `claude-sonnet-4-6`, 2–4 sentence recommendation
- Pre-mortem auto-generation on "Save Verdict" click: sends verdict text + confidence + deadline to `claude-sonnet-4-6`; user sees result in editable field before confirming save
- Save writes to `verdicts` table; decision status → `complete`
- "Cancel" returns to Synthesis Map without saving

### Definition of done

- Complete a decision flow end-to-end; save a verdict
- Re-open decision → Verdict tab shows the saved verdict cleanly
- Pre-mortem generated and editable before save
- Verdict queryable by `outcome_deadline`

---

## Phase 7 — Calibration Ledger
**Week 12 | Goal: Outcomes marked; weekly review screen operational**

### Tasks

- `ThisWeekView`: list verdicts where `outcome_status = 'pending'` AND deadline ≤ now + 7 days, or deadline < now (overdue)
- Sidebar badge: count of due + overdue verdicts
- Per-verdict: brief summary, outcome mark controls (right / partial / wrong / dismiss), notes field
- Outcome state machine per SPEC §6.9 (`pending → right | partial | wrong | dismissed`; terminal)
- Pattern queries per SPEC §6.9: run only when ≥20 marked outcomes; calibration rate by lens, by reversibility
- Pattern display: horizontal bar chart per lens, sorted descending, `n=X` label
- `<20` outcomes: show "Patterns appear after 20 marked outcomes. You have N so far."
- Decision Detail → Outcome tab: mark form (if pending) or outcome record display (if marked)

### Definition of done

- Mark outcomes on 5 sample verdicts; all persist correctly
- This Week screen shows accurate due/overdue counts
- Pattern queries execute without error (results may be sparse at low volume)
- Dismissed verdicts no longer appear in This Week

---

## Phase 8 — Export
**Week 13 | Goal: Markdown and PDF exports match the in-app brief**

### Tasks

- Markdown template per SPEC §6.10; file named `[slugified-question]-[YYYY-MM-DD].md`
- PDF via PDFKit: same layout, US Letter, system serif body, monospace for model names; header and footer per spec
- Export sheet: Markdown / PDF / Both options
- Export trigger in Verdict view toolbar and Decision Detail → Verdict tab toolbar
- Default export path from `export_default_path` setting (default `~/Desktop`)
- Slug function: lowercase, spaces → hyphens, strip special chars, truncate 60 chars

### Definition of done

- Export 3 verdicts to both formats
- Markdown opens cleanly in Typora, Obsidian, and Preview
- PDF opens in Preview with correct layout; visual parity with on-screen verdict view
- Files land at configured export path with correct names

---

## Phase 9 — Polish
**Weeks 14–15 | Goal: Ship-quality; signed DMG builds**

### Tasks

- Error states: all API error banners per SPEC §8.1–8.2 wired to real UI; "partial results" banner on Synthesis Map for failed runs
- Empty states: All Decisions, Synthesis Map (no args), This Week, Calibration patterns per SPEC §8.3
- Onboarding: first-launch modal when no API keys configured → opens Settings → Models; one-time "Start here" tooltip over New Decision
- Accessibility: VoiceOver labels/hints on all controls; Dynamic Type for all text (no fixed sizes); full keyboard tab order; Synthesis Map keyboard controls (arrow key selection, Space to tray, Escape to deselect); 4.5:1 contrast minimum; focus rings visible
- Performance audit: profile all screens; fix any dropping below 60 fps
- App icon and About screen (version, build, changelog)
- Signing and notarization setup (Developer ID, `xcrun notarytool`)

### Definition of done

- All happy paths feel finished; no placeholder UI visible
- Accessibility audit: VoiceOver traverses every screen without dead ends
- Signed and notarized DMG mounts cleanly on a fresh macOS 15 install

---

## Phase 10 — Dogfood and Ship
**Week 16 | Goal: 20 real decisions run; v1 declared**

### Tasks

- Run 20 real decisions in cloud and air gap modes across all 8 lens templates
- Log bugs and friction in a local text file during the fortnight
- Fix all critical issues (crashes, data loss, misleading output, incorrect cost tracking)
- Final DMG build, private archive

### Definition of done

- 20 decisions complete without crashes
- All critical bugs resolved
- You would show it to another director without apology
- Acceptance criteria 1–10 from SPEC §13 all pass

---

## Acceptance Criteria (v1 Ship Gate)

From SPEC §13 — all must pass before declaring v1:

1. All 8 lens templates run end-to-end in cloud and air gap modes without crashes
2. Force-directed graph ≥ 60 fps with 200 nodes on M5
3. Verdict brief exports to Markdown and PDF with visual parity to on-screen view
4. Calibration ledger surfaces due verdicts in This Week
5. Air gap toggle blocks all cloud network traffic (verify via proxy)
6. Cost guardrails: soft warning at $2, hard pause at $5, no silent overruns
7. Sequential local run (Qwen 32B → Mistral 22B, 3 rounds, 4 personas, 3 samples) ≤ 15 minutes on M5 32 GB
8. No crashes on a 20-decision stress test
9. No telemetry in production build (verify via network monitor)
10. Signed and notarized DMG mounts on a clean macOS 15 install

---

## Dependencies and Critical Path

```
Phase 0  ──→  Phase 1  ──→  Phase 2  ──┐
                                        ├──→  Phase 4  ──→  Phase 5  ──→  Phase 6  ──→  Phase 7  ──→  Phase 8  ──→  Phase 9  ──→  Phase 10
                              Phase 3  ──┘
```

- **Phases 2 and 3 can overlap** if working on parallel tracks: cloud and local orchestration both feed Phase 4. Build each to a minimal working state, then unify.
- **Phase 5 (synthesis map) is highest technical risk.** The Week 1 force-simulation spike is non-negotiable. If it fails the fps bar, decide on the Barnes-Hut vs. column-view fallback path before reaching Phase 5.
- **Phase 7 needs real data.** Run real decisions through Phases 6 and 7 in debug builds as soon as they are functional — do not wait for Phase 10 to generate outcome data.
- **Phase 10 is non-negotiable.** Shipping without dogfood signal is shipping blind.

---

## Milestone Snapshot

| Week | Phase | Demo-able outcome |
|---|---|---|
| 1 | Foundation | App opens, Settings works, API keys persist, force-sim spike passes |
| 2 | Intake + Refinement | Form → refined brief via Claude |
| 3–4 | Cloud Orchestration | 4-model parallel run completes, cost tracked |
| 5–6 | Local Orchestration | Air gap run end-to-end, no outbound traffic |
| 7–8 | Debate Engine | 3-round debate + clustered arguments |
| 9–10 | Synthesis Map | Visual map at 60 fps, verdict tray works |
| 11 | Verdict Capture | Verdict saved with pre-mortem |
| 12 | Calibration Ledger | This Week screen operational |
| 13 | Export | Markdown + PDF exports correct |
| 14–15 | Polish | Signed DMG, accessibility pass |
| 16 | Dogfood + Ship | 20 decisions, v1 declared |

---

## Out of Scope for v1

- Share sheet integrations (Apple Notes, Notion, Obsidian)
- Import/export decisions as portable bundles
- Lens template editor UI (curated set ships only)
- Custom persona authoring
- Multi-mode runs (cloud + local in the same council)
- Voice intake
- Historical pattern visualizations beyond calibration rates
- iCloud sync (explicitly never)
- Multi-user or team features
