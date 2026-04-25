# The Council — Technical Specification

**Version:** 1.0
**Date:** 2026-04-21
**Status:** Ready for implementation
**Owner:** Ben Podbielski
**Source docs:** PRD.md, PLAN.md

---

## 1. Platform and Environment

| Property | Value |
|---|---|
| OS | macOS 15+ |
| Language | Swift 6 |
| UI framework | SwiftUI |
| Build system | Xcode, SPM |
| Target hardware | Apple Silicon, M5, 32 GB RAM |
| Distribution | Signed and notarized DMG (no Mac App Store) |
| App Sandbox | Enabled — `com.apple.security.network.client`, file read/write for Application Support |

---

## 2. Dependencies

| Package | Purpose | Source |
|---|---|---|
| GRDB.swift | SQLite ORM | SPM |
| KeychainAccess | Keychain wrapper | SPM |
| MLXSwift | On-device LLM inference | SPM |
| Swift Markdown | Markdown rendering and export | SPM (Apple) |
| PDFKit | PDF export | System framework |

No other third-party dependencies in v1.

---

## 3. Data Model

All data stored in a single SQLite database at:

```
~/Library/Application Support/The Council/council.db
```

Files stored at:
```
~/Library/Application Support/The Council/decisions/<decision-id>/
    attachments/        # original context attachments
    graph-state.json    # force-directed layout state (positions)
    exports/            # generated markdown and PDF briefs
```

Local model weights stored at a user-configurable directory exposed in Settings (default: `~/Library/Application Support/The Council/models/`).

### 3.1 Schema

```sql
CREATE TABLE decisions (
    id                  TEXT PRIMARY KEY,          -- UUID
    created_at          INTEGER NOT NULL,           -- Unix timestamp
    status              TEXT NOT NULL,              -- draft | refining | ready | running | complete | archived
    question            TEXT NOT NULL,
    lens_template       TEXT NOT NULL,              -- see §6.2 for valid values
    reversibility       TEXT NOT NULL,              -- reversible | semi-reversible | irreversible
    time_horizon        TEXT NOT NULL,              -- weeks | months | quarters | years
    sensitivity_class   TEXT NOT NULL,              -- public | sensitive | confidential
    success_criteria    TEXT NOT NULL,
    refined_brief       TEXT,                       -- NULL until sign-off
    refinement_chat_log TEXT                        -- JSON array of {role, content, timestamp}
);

CREATE TABLE model_runs (
    id              TEXT PRIMARY KEY,               -- UUID
    decision_id     TEXT NOT NULL REFERENCES decisions(id),
    model_name      TEXT NOT NULL,                  -- e.g. "claude-opus-4-7"
    provider        TEXT NOT NULL,                  -- anthropic | openai | google | xai | local-mlx | local-ollama
    persona         TEXT NOT NULL,                  -- see §6.3 for valid values
    round_number    INTEGER NOT NULL,               -- 1 | 2 | 3
    sample_number   INTEGER NOT NULL,               -- 1-based index within persona+round
    temperature     REAL NOT NULL,                  -- 0.3 | 0.7 | 1.0
    prompt          TEXT NOT NULL,
    response        TEXT,                           -- NULL if failed
    tokens_in           INTEGER,
    tokens_out          INTEGER,
    cost_usd            REAL,
    created_at          INTEGER NOT NULL,
    error               TEXT,                       -- NULL if success
    position_changed    INTEGER                     -- NULL | 0 | 1  (set during round-3 parse)
);

CREATE TABLE arguments (
    id                  TEXT PRIMARY KEY,           -- UUID
    decision_id         TEXT NOT NULL REFERENCES decisions(id),
    source_run_id       TEXT NOT NULL REFERENCES model_runs(id),
    position            TEXT NOT NULL,              -- for | against | neutral
    text                TEXT NOT NULL,
    cluster_id          TEXT REFERENCES clusters(id),
    prominence          REAL NOT NULL DEFAULT 1.0   -- computed after clustering
);

CREATE TABLE clusters (
    id              TEXT PRIMARY KEY,               -- UUID
    decision_id     TEXT NOT NULL REFERENCES decisions(id),
    position        TEXT NOT NULL,                  -- for | against | neutral
    centroid_text   TEXT NOT NULL
);

CREATE TABLE verdicts (
    id                  TEXT PRIMARY KEY,           -- UUID
    decision_id         TEXT NOT NULL REFERENCES decisions(id),
    created_at          INTEGER NOT NULL,
    verdict_text        TEXT NOT NULL,
    confidence          INTEGER NOT NULL,           -- 0-100
    key_for_json        TEXT NOT NULL,              -- JSON array of argument texts
    key_against_json    TEXT NOT NULL,
    risk                TEXT NOT NULL,
    blind_spot          TEXT NOT NULL,
    opportunity         TEXT NOT NULL,
    pre_mortem          TEXT NOT NULL,
    outcome_deadline    INTEGER NOT NULL,           -- Unix timestamp
    test_action         TEXT NOT NULL,
    test_metric         TEXT NOT NULL,
    test_threshold      TEXT NOT NULL,
    outcome_status      TEXT NOT NULL DEFAULT 'pending'   -- pending | right | partial | wrong | dismissed
);

CREATE TABLE outcomes (
    id              TEXT PRIMARY KEY,               -- UUID
    verdict_id      TEXT NOT NULL REFERENCES verdicts(id),
    marked_at       INTEGER NOT NULL,
    result          TEXT NOT NULL,                  -- right | partial | wrong
    actual_notes    TEXT NOT NULL,
    what_changed    TEXT NOT NULL
);

CREATE TABLE settings (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL
);
```

### 3.2 Migrations

Migrations run on every app launch before any database access. Each migration is versioned in code and applied in order. Missing migrations block app start and display a recovery dialog.

---

## 4. Application Architecture

```
TheCouncil/
├── App/
│   ├── TheCouncilApp.swift         # @main, scene setup, migration trigger
│   └── AppDelegate.swift
├── Database/
│   ├── DatabaseManager.swift       # GRDB setup, migration runner
│   └── Migrations/                 # one file per migration version
├── Keychain/
│   └── KeychainStore.swift         # KeychainAccess wrapper, per-provider key CRUD
├── Models/                         # Swift value types matching schema
│   ├── Decision.swift
│   ├── ModelRun.swift
│   ├── Argument.swift
│   ├── Cluster.swift
│   ├── Verdict.swift
│   ├── Outcome.swift
│   └── Settings.swift
├── APIClients/
│   ├── AnthropicClient.swift       # streaming, shared by refinement + council
│   ├── OpenAIClient.swift
│   ├── GeminiClient.swift
│   └── GrokClient.swift
├── LocalInference/
│   ├── MLXRunner.swift             # sequential Qwen → Mistral, memory pressure
│   └── OllamaClient.swift          # optional HTTP bridge
├── Orchestration/
│   ├── CouncilOrchestrator.swift   # TaskGroup parallel cloud, sequential local
│   ├── DebateEngine.swift          # 3-round protocol, anonymization, steel-man
│   ├── ArgumentExtractor.swift     # prompt + parser for post-round-3 pass
│   └── ClusteringEngine.swift      # embeddings + k-means or HDBSCAN
├── ForceGraph/
│   ├── ForceSimulation.swift       # Verlet / Barnes-Hut, configurable
│   ├── GraphView.swift             # SwiftUI Canvas, per-frame render
│   └── GraphViewModel.swift
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
    ├── LensTemplates/              # 8 JSON configs
    └── Personas/                   # 10 versioned prompt files
```

---

## 5. Settings Keys

All settings stored in the `settings` table as text key-value pairs. Boolean values: `"true"` / `"false"`. Numeric: decimal string.

| Key | Type | Default | Notes |
|---|---|---|---|
| `default_rounds` | Int | `3` | Range 1–5 |
| `default_samples` | Int | `3` | Range 1–5 |
| `default_outcome_deadline_days` | Int | `60` | |
| `cost_soft_warn_usd` | Decimal | `2.00` | |
| `cost_hard_pause_usd` | Decimal | `5.00` | |
| `air_gap_enabled` | Bool | `false` | |
| `frontier_set_models` | JSON | see §6.1 | array of model IDs |
| `balanced_set_models` | JSON | see §6.1 | |
| `export_default_path` | String | `~/Desktop` | |
| `export_format_order` | JSON | `["markdown","pdf"]` | |
| `local_model_directory` | String | AppSupport path | |
| `ollama_enabled` | Bool | `false` | |
| `ollama_base_url` | String | `http://localhost:11434` | |

API keys are stored exclusively in Keychain, not in the settings table.

Keychain service names:
- `com.benpodbielski.thecouncil.apikey.anthropic`
- `com.benpodbielski.thecouncil.apikey.openai`
- `com.benpodbielski.thecouncil.apikey.google`
- `com.benpodbielski.thecouncil.apikey.xai`

---

## 6. Feature Specifications

### 6.1 Model Panel

**Cloud frontier set (default):**
- Anthropic: `claude-opus-4-7`
- OpenAI: `gpt-5.4`
- Google: `gemini-3.1-pro-preview`
- xAI: `grok-4.20-0309-non-reasoning`

**Cloud balanced set:**
- Anthropic: `claude-sonnet-4-6`
- OpenAI: `gpt-5.4-mini`
- Google: `gemini-3-flash-preview`
- xAI: `grok-4.1`

**Cloud flash set:**
- OpenAI: `gpt-5.4-nano`
- Google: `gemini-3.1-flash-lite-preview`
- xAI (mini): `grok-4.1`
- xAI (fast): `grok-4.1-fast`

**Air gap set (sequential):**
1. Qwen 2.5 32B — 4-bit MLX quantization
2. Mistral Small 22B — 4-bit MLX quantization

Sequential execution: model 1 fully unloads (confirmed by memory pressure API) before model 2 loads.

Fallback: if Qwen 32B fails to load, fall back to Qwen 14B class. Surface error and ask user to confirm continuation.

**Sensitivity routing enforcement:**

| Sensitivity | Allowed paths | Enforcement |
|---|---|---|
| Public | Cloud or local | None |
| Sensitive | Cloud with redaction sign-off, or local | Pre-run confirmation dialog |
| Confidential | Local only | Air gap auto-enabled, cloud API calls return error before network layer |

Air gap network enforcement: patch URLSession shared configuration to refuse connections to known AI provider hostnames. Block list:
```
api.anthropic.com
api.openai.com
generativelanguage.googleapis.com
api.x.ai
```

### 6.2 Lens Templates

Stored as JSON files in `Resources/LensTemplates/`. Each file:

```json
{
    "id": "strategic-bet",
    "label": "Strategic bet and capital allocation",
    "default_personas": ["strategist","finance-lens","risk-officer","operator","skeptic"],
    "default_rounds": 3,
    "default_samples": 3
}
```

Valid template IDs:
- `strategic-bet`
- `make-buy-partner`
- `market-entry`
- `pivot-scale-kill`
- `innovation-portfolio`
- `vendor-technology`
- `org-design`
- `pilot-to-scale`

### 6.3 Persona Library

Stored as versioned prompt files in `Resources/Personas/<id>-v1.md`. File format:

```
---
id: skeptic
version: 1
label: The Skeptic
---
[System prompt content]
```

Valid persona IDs: `skeptic`, `first-principles`, `operator`, `strategist`, `outsider`, `customer-voice`, `finance-lens`, `risk-officer`, `founder-mindset`, `regulator`.

### 6.4 Debate Protocol

**Round 1 — Independent analysis**

Each `(model × persona × sample)` combination receives:
- The refined decision brief
- The persona system prompt
- The lens template context
- Temperature from the sample index: sample 1 → 0.3, sample 2 → 0.7, sample 3 → 1.0

Expected output format (parsed by `ArgumentExtractor`):

```
RECOMMENDATION: [for/against/conditional]
EVIDENCE:
- [evidence point 1]
- [evidence point 2]
KEY ASSUMPTION: [single most critical assumption]
FLAGGED LIMITATION: [what this analysis does not cover]
```

**Round 2 — Rebuttal + steel-man**

Each persona receives all round-1 outputs *except its own*, with model/persona labels stripped (anonymized). It produces:

```
REBUTTAL:
- WEAKNESS: [flaw in argument X]
- ASSUMPTION: [unstated assumption in argument Y]
- COUNTER-EVIDENCE: [evidence that contradicts argument Z]
STEEL-MAN: [strongest version of the opposite recommendation]
```

Anonymization: replace `[Model Name] / [Persona Name]` with `Perspective A`, `Perspective B`, etc. (consistent mapping per decision, not per round).

**Round 3 — Defend or update**

Each persona receives its round-1 output and all round-2 rebuttals directed at it. It produces:

```
POSITION: [maintained/updated]
IF MAINTAINED:
  STRONGER EVIDENCE: [additional support]
  REBUTTAL RESPONSE: [why rebuttals don't change the position]
IF UPDATED:
  CHANGE: [what changed and why]
  NEW RECOMMENDATION: [for/against/conditional]
```

Explicit `POSITION: updated` flag is indexed in the `model_runs` table via a nullable `position_changed` boolean column.

**Argument extraction (post round 3)**

A separate aggregation pass sends all round-3 outputs to Claude with a prompt requesting structured argument extraction. Output: a JSON array of `{position, text}` objects. Parse into the `arguments` table.

**Semantic clustering**

Arguments clustered using embeddings. Cloud mode: OpenAI `text-embedding-3-small`. Air gap mode: local sentence-transformers via MLX or a bundled lightweight embedder. Clustering algorithm: k-means with k determined by elbow method, minimum k=2 (for/against), maximum k=8. Write cluster assignments to `arguments.cluster_id`, write centroids to `clusters.centroid_text`.

Prominence score = (number of arguments in cluster) / (total arguments). Written to `arguments.prominence`.

### 6.5 Orchestration

**Cloud parallel execution**

```swift
await withThrowingTaskGroup(of: ModelRunResult.self) { group in
    for (model, persona, sample) in combinations {
        group.addTask {
            try await runSingleModelRun(model, persona, sample)
        }
    }
    for try await result in group {
        await saveRun(result)
        await updateProgressUI(result)
    }
}
```

Runs are independent within a round. Round N+1 does not begin until all round-N runs complete or fail.

**Rate limit handling**

On 429 response: exponential backoff starting at 2s, max 5 retries, max wait 64s. After 5 failures, mark run as `error`, continue with remaining. Surface count of failed runs in execution UI.

**Cost tracking**

Live cost = sum of `model_runs.cost_usd` for the active decision. Updated after each run completes. Soft warning ($2): non-blocking dialog with "Continue" / "Cancel". Hard pause ($5): blocking dialog — council execution suspends until user selects "Override and continue" or "Stop and save partial results".

**Local sequential execution**

```swift
let runner = MLXRunner()
try await runner.load(model: .qwen32b4bit)
let qwenResults = try await runner.runAllPersonasAllRounds(brief: brief, personas: personas)
try await runner.unload()
try await runner.load(model: .mistralSmall22b4bit)
let mistralResults = try await runner.runAllPersonasAllRounds(brief: brief, personas: personas)
try await runner.unload()
```

Memory pressure check: after `unload()`, poll `ProcessInfo.processInfo.thermalState` and available memory via `mach_host_self()`. Proceed when thermal state is nominal and available RAM is ≥ 10 GB.

Performance target: 3-round debate (Qwen + Mistral, 4 personas, 3 samples each) ≤ 15 minutes on M5 32 GB.

### 6.6 Force-Directed Graph

**Physics model**

Each node has position `(x, y)` and velocity `(vx, vy)`. Per tick:

1. **Repulsion:** for each pair of unconnected nodes, apply repulsive force proportional to `1 / distance²`, strength configurable (default: 200).
2. **Spring:** for each edge, apply spring force toward ideal edge length (default: 80px), strength configurable (default: 0.3).
3. **Centering gravity:** pull all nodes toward canvas center with weak force (default: 0.05).
4. **Velocity damping:** multiply `vx`, `vy` by 0.85 per tick.
5. **Position update:** `x += vx`, `y += vy`.

For >100 nodes, use Barnes-Hut quadtree approximation (theta = 0.9) for repulsion step. Switch automatically at the 100-node threshold.

**Rendering**

SwiftUI Canvas. Target: 60 fps up to 200 nodes. Use `TimelineView(.animation)` for the render loop. Batch draw calls: draw all edges in one pass, all node circles in one pass, node labels last. Skip label rendering for nodes < 8px diameter at current zoom.

**Node visual encoding:**

| Property | Visual |
|---|---|
| Source model | Fill color (4-color palette, consistent per session) |
| Prominence | Node radius: `max(6, min(20, prominence * 30))` |
| Position (for/against/neutral) | Cluster centroid gravity pulls same-position nodes together |
| Outlier (>1.5σ from centroid) | Dashed border, pushed to graph edge |

**Edge visual encoding:**

| Relationship | Color | Width |
|---|---|---|
| Agreement (same position) | Green `#34C759` | 1.5px |
| Rebuttal | Red `#FF3B30` | 1.5px |
| Tangent | Gray `#8E8E93` | 1px, dashed |

**Interactions:**

- **Zoom / pan:** standard pinch-zoom and two-finger pan. Zoom range: 0.25× to 4×.
- **Drag node:** grab and drag. Node becomes pinned (stops receiving force updates) until released.
- **Click node:** opens argument detail panel on right. Highlights node with white ring.
- **Hover node:** tooltip with `Model / Persona / Round N`.
- **Drag to tray:** drag node to right tray area. Visual drop zone highlights on hover.

**Graph state persistence:** on verdict capture, serialize `{id, x, y, pinned}` for all nodes to `graph-state.json` in the decision folder.

**Filter toggles (top bar):**

- Model: per-model enable/disable checkboxes
- Persona: per-persona enable/disable
- Round: 1, 2, 3 toggle
- Position: for, against, neutral

Filtered-out nodes are hidden (not removed from physics simulation, to preserve layout stability).

**Fallback:** if fps drops below 30 for >3 consecutive seconds, offer "Switch to column view" dialog. Column view: three columns (For / Against / Neutral), arguments listed as cards, drag-to-tray preserved.

### 6.7 Refinement Chat

Claude (`claude-opus-4-7`) acts as facilitator. System prompt instructs it to:

1. Review the brief for ambiguity, missing context, and unstated assumptions.
2. Ask exactly 2–4 clarifying questions in a single response (never one question at a time).
3. Propose redactions for any PII, financial figures, personal names, or identifying detail if sensitivity class is not confidential.
4. Produce a structured refined brief once the user signals readiness.

Redaction suggestion trigger: pattern-match the question and context attachments for:
- Email addresses (`\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b`)
- Dollar amounts (`\$[\d,]+`)
- Person names (NLP heuristic: capitalized two-word pairs not in a known-places list)
- Custom keywords from a user-configurable redaction keyword list in Settings

Suggested redactions appear inline in the brief draft as `[REDACTED: reason]`. User approves or dismisses each before sign-off.

Sign-off: user clicks "Approve and run council". The current brief draft is written to `decisions.refined_brief`. Status advances to `ready`.

**Streaming:** use Anthropic streaming API. Append tokens to the conversation view as they arrive.

### 6.8 Verdict Capture

Fields and sources:

| Field | Source |
|---|---|
| Question | `decisions.question` (read-only) |
| Key arguments for | Auto-populated from verdict tray (for-position nodes) |
| Key arguments against | Auto-populated from verdict tray (against-position nodes) |
| Risk | User writes, or pull from tray selection |
| Blind spot | User writes |
| Opportunity | User writes |
| Verdict | User writes; optional Claude first-draft (button-gated) |
| Confidence | Slider 0–100, default 70 |
| Outcome deadline | DatePicker, default today + 60 days |
| Test action | User writes |
| Test metric | User writes |
| Test threshold | User writes |
| Pre-mortem | AI-generated (Claude), user edits |

**Claude assist (verdict first-draft):** button labeled "Draft verdict with Claude". Sends the refined brief and all verdict tray arguments to `claude-sonnet-4-6` with a prompt to produce a 2–4 sentence recommendation. User edits before saving.

**Pre-mortem generation:** automatic on "Save Verdict" click before final save. Sends verdict text and confidence to `claude-sonnet-4-6`. Prompt: "Assume it is [outcome_deadline] and this decision proved wrong. Write a concise pre-mortem (3–5 bullets) explaining the most plausible failure path." User sees the result in the pre-mortem field and can edit before confirming save.

### 6.9 Calibration Ledger

**"This Week" screen** shows verdicts where:
- `outcome_status = 'pending'` AND `outcome_deadline <= now + 7 days`, OR
- `outcome_status = 'pending'` AND `outcome_deadline < now` (overdue)

Verdicts remain in this list until marked or dismissed. Dismissed verdicts set `outcome_status = 'dismissed'`.

**Outcome marking state machine:**

```
pending → right
pending → partial
pending → wrong
pending → dismissed
```

No transitions out of terminal states in v1.

**Pattern queries** (run only when `COUNT(outcomes WHERE result IS NOT NULL) >= 20`):

```sql
-- Calibration rate by lens
SELECT d.lens_template,
       COUNT(*) AS total,
       SUM(CASE WHEN o.result = 'right' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS right_rate
FROM outcomes o JOIN verdicts v ON o.verdict_id = v.id
JOIN decisions d ON v.decision_id = d.id
GROUP BY d.lens_template;

-- Calibration rate by reversibility
SELECT d.reversibility, COUNT(*), SUM(...) ...
FROM outcomes o JOIN verdicts v ... JOIN decisions d ...
GROUP BY d.reversibility;
```

Display: horizontal bar chart per lens, sorted descending by right_rate. Label shows `n=X` sample count next to each bar.

### 6.10 Export

**Markdown template** (`[decision-title]-[YYYY-MM-DD].md`):

```markdown
# [Question]

**Date:** [created_at]
**Lens:** [lens_template label]
**Confidence:** [confidence]%
**Outcome deadline:** [outcome_deadline]

## Verdict

[verdict_text]

## Arguments For

[key_for_json items as bullet list]

## Arguments Against

[key_against_json items as bullet list]

## Risk

[risk]

## Blind Spot

[blind_spot]

## Opportunity

[opportunity]

## Pre-mortem

[pre_mortem]

## Test

**Action:** [test_action]
**Metric:** [test_metric]
**Threshold:** [test_threshold]

---
*Model panel: [comma-separated model names]*
*Total cost: $[sum of model_runs.cost_usd]*
```

**PDF template:** PDFKit-rendered equivalent of the above. Header: question + date + lens. Footer: model panel, cost, page number. Font: system serif for body, system monospace for code/model names. Page size: US Letter.

**Export triggers:**
- Verdict view: "Export" button in toolbar → sheet offering Markdown / PDF / Both
- Decision Detail → Verdict tab: same sheet

**File naming:**
```
[slugified-question]-[YYYY-MM-DD].md
[slugified-question]-[YYYY-MM-DD].pdf
```
Slug: lowercase, spaces to hyphens, strip special characters, truncate to 60 chars.

---

## 7. UI Screen Specifications

### 7.1 Navigation

Sidebar entries (top to bottom):
1. **New Decision** (always visible, primary action)
2. **This Week** (shows badge count of due/overdue)
3. **All Decisions** (chronological list)
4. **Settings**

### 7.2 Home (All Decisions)

List of decision cards. Each card:
- Question text (truncated at 2 lines)
- Status badge: `Draft` | `Refining` | `Ready` | `Running` | `Complete` | `Archived`
- Lens template label
- Created date
- Verdict deadline (if verdict exists and outcome pending)

Click card → Decision Detail.

### 7.3 Intake Form

Single-column, all fields visible at once. No multi-step wizard.

| Field | Control | Validation |
|---|---|---|
| Question | TextEditor, min 3 lines | Required, min 20 chars |
| Decision type | Picker, 8 options | Required |
| Reversibility | Segmented control (3 options) | Required |
| Time horizon | Segmented control (4 options) | Required |
| Sensitivity class | Segmented control (3 options) | Required |
| Success criteria | TextEditor, min 2 lines | Required, min 10 chars |
| Context | AttachmentView (file picker + URL field + paste zone) | Optional |

Confidential sensitivity class: show inline note "Air gap mode will be enforced."

Primary button: "Refine with Claude" (disabled until all required fields valid).

### 7.4 Refinement Chat

Two-pane layout:
- **Left (40%):** Current refined brief draft. Redaction suggestions appear as highlighted spans with inline approve/dismiss buttons.
- **Right (60%):** Conversation thread. User text input at bottom. Claude streams into the conversation.

Top bar: decision question (read-only), sensitivity badge.

Bottom bar (left pane): "Approve Brief and Continue →" (advances to Council Configuration).

### 7.5 Council Configuration

Compact card layout. Sections:
- **Model Panel**: selected set label + per-model chips (tap to enable/disable)
- **Personas**: grid of persona chips (tap to enable/disable)
- **Rounds**: stepper (1–5)
- **Samples**: stepper (1–5)
- **Estimated cost**: computed from enabled models × personas × rounds × samples × average token cost

Primary button: "Run Council".

### 7.6 Council Execution

Full-screen progress view:
- Timeline view: rows for each round. Within each round, model-status chips update in real time.
- Status chip states: `Waiting` → `Running` → `Done` | `Failed`
- Live counter: `$X.XX spent · X,XXX tokens`
- Cancel button (top right): stops remaining runs, saves partial results, advances to Synthesis Map with a warning banner.

### 7.7 Synthesis Map

Full-screen. Three zones:
- **Canvas (left, ~70%):** Force-directed graph. Top bar: filter toggles, zoom controls, "Reset Layout" button.
- **Right panel (30%):** Toggle between Argument Detail (when node selected) and Verdict Tray.

Verdict Tray: vertical list of dragged-in nodes. Each tray item shows: model/persona/round badge + argument text (2-line truncated) + remove button.

Top right button: "Capture Verdict →" (advances to Verdict Capture).

### 7.8 Verdict Capture

Single-column form with all fields visible. Auto-populated fields show pre-fill badge "From council". Editable.

Pre-mortem section: shows spinner while generating, then renders editable text when done.

Bottom: "Save Verdict" primary button. "Cancel" link returns to Synthesis Map without saving.

### 7.9 Decision Detail

Segmented tab bar with 5 tabs: Brief | Council | Map | Verdict | Outcome.

- **Brief:** read-only refined brief, intake fields summary.
- **Council:** model run transcript. Filter by model/persona/round. Expandable run cards showing prompt + response.
- **Map:** the synthesis map (interactive, same as 7.7).
- **Verdict:** read-only verdict brief. Export button in toolbar.
- **Outcome:** outcome marking UI. If pending: mark form. If marked: outcome record display.

### 7.10 Settings

Standard Mac preferences window (NSWindow or SwiftUI equivalent). Toolbar with tab icons.

**Tabs:**

| Tab | Contents |
|---|---|
| General | Default deadline days, empty state preferences |
| Models | API key entry per provider, model tier selection, cost per 1K input/output, frontier/balanced/air gap set membership toggles |
| Debate | Default rounds (1–5), default samples (1–5), temperature profile (read-only in v1) |
| Cost | Soft warn threshold, hard pause threshold, monthly cost chart |
| Air Gap | Air gap toggle, local model management (download, status, unload, delete, directory path) |
| Export | Default export path, format order preference |
| About | App version, build, changelog text view |

---

## 8. Error States

### 8.1 API Errors

| Error | Behavior |
|---|---|
| 401 Unauthorized | Mark all runs for provider as `error`, show banner: "API key for [Provider] is invalid. Update in Settings." |
| 429 Rate limited | Exponential backoff, retry up to 5×, then mark run as `error` and continue |
| 5xx Server error | 3 retries with 2s fixed delay, then mark run as `error` |
| Timeout (>120s) | Mark run as `error`, continue |
| Invalid JSON response | Mark run as `error`, continue |
| Empty response | Mark run as `error`, continue |

A "partial results" banner appears on the Synthesis Map if any runs failed, with a count and re-run option for failed runs only.

### 8.2 Local Model Errors

| Error | Behavior |
|---|---|
| Insufficient RAM to load model | Dialog: "Not enough RAM to load [model]. Suggested: close other apps and retry, or switch to [smaller model]." |
| Model file missing | Dialog: "Model not found. Go to Settings → Air Gap to download it." |
| Inference crash | Catch signal, mark run as `error`, attempt model unload, continue with next model |
| Thermal throttle detected | Pause inference, show banner: "Thermal throttle detected. Waiting to continue." Resume automatically when thermal state returns to nominal. |

### 8.3 Empty States

| Screen | Empty state message |
|---|---|
| All Decisions | "No decisions yet. Start one with New Decision." + primary button |
| Synthesis Map (no arguments) | "No arguments extracted. The council run may have produced no parseable output." + "Re-run extraction" link |
| This Week | "Nothing due this week." |
| Calibration patterns (<20 outcomes) | "Patterns appear after 20 marked outcomes. You have [N] so far." |

---

## 9. Onboarding

First launch (no API keys configured):
1. Show modal: "Welcome to The Council. Add at least one API key to get started."
2. Open Settings → Models tab directly.
3. On first key saved, dismiss modal and return to Home.

First decision (no previous decisions):
- Show brief tooltip over "New Decision": "Start here." (one-time, dismissed on click).

No guided tour in v1. No sample decision.

---

## 10. Accessibility

- All interactive elements: VoiceOver labels and hints.
- Force-directed graph: full VoiceOver mode presents arguments as a structured list (not graph) when VoiceOver is active. Toggle preserved.
- Dynamic Type: all text views use `.font(.body)` and equivalent system type scales. No fixed font sizes.
- Keyboard navigation: full tab order through all forms and lists. Synthesis Map keyboard controls: arrow keys for selection, Space to add to tray, Escape to deselect.
- Minimum contrast ratio: 4.5:1 for all text.
- Focus ring visible on all interactive elements in keyboard navigation mode.

---

## 11. Performance Budgets

| Operation | Budget |
|---|---|
| App launch to Home screen | < 2s |
| Intake form to Refinement Chat (round-trip to Claude) | < 8s first token |
| Graph render, 200 nodes | ≥ 60 fps |
| Graph render, 50 nodes | ≥ 60 fps |
| Full local debate (Qwen + Mistral, 4 personas, 3 rounds, 3 samples) | ≤ 15 min |
| Export to Markdown | < 1s |
| Export to PDF | < 3s |
| Database read (decision list, 500 decisions) | < 100ms |

---

## 12. Security

- No telemetry. No analytics. No crash reporting. No network traffic except intentional AI API calls and user-triggered attachment URL fetches.
- API keys stored exclusively in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
- Air gap enforcement: URL session configuration blocklist applied at app launch when air gap enabled, re-applied on every council run regardless of setting.
- All file writes use App Sandbox scoped bookmarks for user-selected paths.
- No logging of API keys, full prompts, or model responses to disk except via the database (which is app-sandboxed and user-accessible).

---

## 13. Acceptance Criteria (v1 Ship Gate)

1. All 8 lens templates run end-to-end in cloud mode and air gap mode without crashes.
2. Force-directed graph renders at ≥ 60 fps with 200 nodes on M5.
3. Verdict brief exports to Markdown and PDF with visual parity to on-screen view.
4. Calibration ledger surfaces due verdicts in This Week.
5. Air gap toggle blocks all cloud network traffic (verified by proxy or Little Snitch).
6. Cost guardrails: soft warning at $2, hard pause at $5, no silent overruns.
7. Sequential local run (Qwen 32B → Mistral 22B, 3 rounds, 4 personas, 3 samples) completes within 15 minutes on M5 32 GB.
8. No crashes across a 20-decision stress test.
9. No telemetry in production build (verify via network monitor).
10. Signed and notarized DMG builds and mounts cleanly on a clean macOS 15 install.

---

## 14. Out of Scope for v1

- Share sheet integrations (Apple Notes, Notion, Obsidian)
- Import/export decisions as portable bundles
- Lens template editor UI (curated set only)
- Custom persona authoring
- Multi-mode runs (cloud + local in the same council)
- Voice intake
- Historical pattern visualizations beyond calibration rates
- iCloud sync (explicitly not pursued, ever)
- Multi-user or team features

---
