# The Council — Product Requirements Document

**Version:** 1.0
**Date:** 2026-04-21
**Status:** Approved for build
**Owner:** Ben Podbielski (personal tool, not for distribution)

---

## 1. Overview

The Council is a native macOS application that runs high-stakes strategic decisions through a structured multi-model AI debate and presents the output as a visual argument map you assemble into your own verdict. Every verdict is logged and later validated against the actual outcome, building a personal calibration record over time.

Built for one user: an enterprise strategy and innovation director making recurring strategic decisions. Strictly personal. No team features. No cloud sync. No telemetry.

---

## 2. Problem Statement

Single-model AI councils suffer from self-preference bias documented across three peer-reviewed papers (NeurIPS 2024, ICLR 2025, arXiv 2026). One model playing five personas then reviewing its own outputs does not produce genuine peer review. Mode collapse from RLHF further suppresses tail-distribution insights where non-obvious analysis lives.

Running multi-model panels manually is painful: copy-paste across four web UIs, no peer review, no synthesis, no record of what worked. No existing tool combines multi-model diversity, structured debate, custom lens focus, visual synthesis, and a calibration record on a native Mac app with air gap support for sensitive decisions.

---

## 3. Goals

- Run any strategic decision through 3 or more models with distinct training lineages.
- Force real debate across 3 rounds of independent analysis, rebuttal, and defense.
- Present arguments as a visual map you assemble, not a verdict handed down.
- Log every verdict with confidence and outcome deadline.
- Track calibration patterns over time to improve future model panel and lens selection.
- Support full air gap mode with local inference for sensitive work.
- Minimize friction for the fifth, fifteenth, and fiftieth use.

---

## 4. Non-Goals

- Team collaboration or multi-user workflows
- Cloud synchronization or account system
- Enterprise SSO, RBAC, or compliance certifications
- Mobile or web clients
- Real-time collaboration on verdicts
- Marketplace for lens packs or personas
- General-purpose AI chat (single, narrow purpose)

---

## 5. Users and Context

**Primary and only user:** one enterprise strategy and innovation director.

**Typical decisions run through it:**

- Strategic bets and capital allocation
- Make vs buy vs partner
- Market entry or expansion
- Pivot, scale, or kill
- Innovation portfolio balance
- Vendor or technology selection
- Org design and team structure
- Pilot to scale transition

**Use frequency:** 2 to 8 decisions per week, most resolving within 60 to 180 days.

**Hardware target:** Apple Silicon Mac, M5 chip, 32GB RAM.

---

## 6. User Flow

### 6.1 Intake

Structured form with these fields:

- **Question** (free text, required)
- **Decision type** (dropdown of 8 lens templates, required)
- **Reversibility** (reversible / semi-reversible / irreversible, required)
- **Time horizon** (weeks / months / quarters / years, required)
- **Sensitivity class** (public / sensitive / confidential, required)
- **Success criteria** (free text, required)
- **Context attachments** (files, URLs, pasted text, optional)

Sensitivity class drives routing. Confidential auto-forces air gap mode. Submitting the form creates a decision record and routes to the refinement chat.

### 6.2 Refinement

The form output pre-fills a chat with Claude. Claude:

- Reviews the brief for ambiguity or gaps
- Asks 2 to 4 clarifying questions in one turn
- Suggests redactions for PII, financials, names, or identifying detail if the decision will route to cloud models
- Produces a structured decision brief

You approve, edit, or iterate. Sign-off produces the final brief the council sees.

### 6.3 Council Configuration

Pre-filled from the lens template defaults:

- Model panel (cloud and/or local, per sensitivity routing)
- Personas per model (curated, 4 to 6 default depending on lens)
- Debate rounds (3 default)
- Samples per persona (3 default)

One-click run, or adjust and run.

### 6.4 Council Execution

Progress view shows:

- Current model running
- Current round
- Tokens consumed and live cost
- Errors or rate limits with graceful fallback

Three-round protocol:

1. **Round 1 (Independent).** Each (model x persona x sample) produces an independent analysis with recommendation, evidence, and flagged limitations.
2. **Round 2 (Rebuttal).** Each persona receives the other perspectives anonymized and writes a rebuttal identifying weaknesses, unstated assumptions, and counter-evidence. No model sees its own round 1 output.
3. **Round 3 (Defend or Update).** Each persona reviews the rebuttals against its round 1 position and either defends with stronger evidence or updates its recommendation with explicit change flagging.

A steel-man pass runs inside round 2: each persona also writes the strongest version of the position opposite its own recommendation.

After round 3, an aggregation pass extracts arguments and clusters them semantically by position.

### 6.5 Synthesis Map

A force-directed graph renders:

- **Nodes:** individual arguments extracted from model outputs
- **Clusters:** arguments grouped by position
- **Edges:** agreement (green), rebuttal (red), tangent (gray)
- **Color:** by source model
- **Size:** by prominence (how many samples surfaced a similar argument)
- **Outliers:** pushed to the edges, visually emphasized

You click a node to see the full reasoning (model, persona, round). You drag nodes into a verdict tray on the right.

### 6.6 Verdict Capture

One-page brief template auto-populates from the verdict tray:

- Question (from refined brief)
- Key arguments for
- Key arguments against
- Risk (top failure mode)
- Blind spot (unquestioned assumption)
- Opportunity (unseen upside)
- Verdict (you write, optional Claude assist)
- Confidence (0 to 100 slider)
- Outcome deadline (default 60 days)
- Test (specific action, metric, threshold)
- Pre-mortem (AI-generated, you edit)

### 6.7 Calibration Ledger

Verdict saves to the local SQLite journal. On the outcome deadline, the app surfaces the verdict in the weekly review screen. You mark:

- Outcome: right, partial, wrong
- Actual outcome notes
- What changed your thinking

Over time, patterns surface:

- Which lens templates produced high-confidence verdicts that proved right
- Which model panels produced verdicts you later regretted
- Which personas most influenced your final synthesis

Pattern surfacing triggers at 20+ marked outcomes.

---

## 7. Feature Specification

### 7.1 Model Panel

Specific model IDs and version pinning: see SPEC.md §6.1 (authoritative).

**Cloud mode frontier set (default):**

- Anthropic Claude (Opus tier)
- OpenAI GPT (top tier)
- Google Gemini (top tier)
- xAI Grok (top tier)

**Cloud mode balanced set (alternate in settings):**

- Anthropic Claude (Sonnet tier)
- OpenAI GPT (mid tier)
- Google Gemini (mid tier)

**Air gap mode (sequential local run):**

- Primary: Qwen 2.5 32B at 4-bit MLX
- Secondary: Mistral Small 22B at 4-bit MLX

Sequential execution reflects RAM constraints on 32GB M5. Model 1 unloads before model 2 loads.

**Model selection menu (Settings).**

Per-provider entries with:

- Enable toggle
- Provider and API endpoint
- Tier dropdown (where applicable)
- Context window limit
- Cost per 1K input tokens and cost per 1K output tokens (for budget tracking)
- Default for frontier set / balanced set / air gap membership

Per-query override: pick a subset of enabled models for the active run.

**Sensitivity routing:**

- Public: any enabled cloud or local model
- Sensitive: redaction layer approval required before cloud routing
- Confidential: local models only, cloud APIs blocked at network layer

### 7.2 Lens Templates (curated v1)

| Template | Default Personas | Default Rounds |
|---|---|---|
| Strategic bet and capital allocation | Strategist, Finance Lens, Risk Officer, Operator, Skeptic | 3 |
| Make vs buy vs partner | Strategist, Finance Lens, Operator, Outsider, First Principles | 3 |
| Market entry or expansion | Strategist, Outsider, Customer Voice, Regulator, Skeptic | 3 |
| Pivot, scale, or kill | Founder Mindset, Finance Lens, Customer Voice, Operator, Skeptic, First Principles | 3 |
| Innovation portfolio balance | Strategist, Finance Lens, Founder Mindset, Risk Officer | 3 |
| Vendor or technology selection | Operator, Finance Lens, Risk Officer, First Principles | 3 |
| Org design and team structure | Operator, Strategist, Outsider, Skeptic | 3 |
| Pilot to scale transition | Operator, Finance Lens, Customer Voice, First Principles, Risk Officer | 3 |

### 7.3 Persona Library (curated v1)

- **The Skeptic.** Attacks assumptions, demands evidence.
- **The First Principles Thinker.** Rebuilds from fundamental truths.
- **The Operator.** Focuses on execution mechanics and operational reality.
- **The Strategist.** Long-term positioning and competitive dynamics.
- **The Outsider.** Cross-industry analogies and unconventional angles.
- **The Customer Voice.** Centers end-user experience and demand.
- **The Finance Lens.** Capital efficiency, ROI, unit economics.
- **The Risk Officer.** Failure modes, downside scenarios, regulatory exposure.
- **The Founder Mindset.** Asymmetric bets, conviction under uncertainty.
- **The Regulator.** Policy, compliance, legal constraints.

Each persona is a versioned system prompt template stored in the app bundle.

### 7.4 Debate Mechanics

3-round default, configurable 1 to 5 rounds in Settings. Round protocol defined in 6.4.

Steel-man requirement: at round 2, each persona writes the strongest version of the opposite recommendation alongside its rebuttal.

### 7.5 Sampling

Per persona per round:

- 3 samples default (configurable 1 to 5)
- Temperature varied across samples: 0.3, 0.7, 1.0
- Semantic clustering after round 3 collapses similar arguments

### 7.6 Force-Directed Graph

SwiftUI Canvas rendered with a custom force simulation:

- **Physics:** spring forces between connected nodes, repulsion between unconnected nodes, centering gravity
- **Interaction:** zoom, pan, drag, click, hover
- **Selection:** click a node to show full argument panel on right
- **Tray:** drag node to right tray to add to verdict assembly
- **Filtering:** toggle visibility by model, persona, round, position
- **Performance budget:** 60fps up to 200 nodes on M5

### 7.7 Verdict Brief

One-page PDF layout matches on-screen view:

- Header: question, date, lens template
- Body: verdict, confidence, arguments for, arguments against, risk, blind spot, opportunity, pre-mortem, test
- Footer: model panel used, token cost, outcome deadline

### 7.8 Calibration Ledger

Weekly review screen ("This Week" sidebar entry):

- Verdicts due within 7 days
- Verdicts overdue for outcome marking
- Recent patterns (surfaces at 20+ marked outcomes)

Pattern types surfaced:

- Calibration rate by lens template
- Calibration rate by model panel composition
- Calibration rate by decision type (reversibility, horizon)

### 7.9 Cost Guardrails

Per-query cost tracking:

- Live counter during execution
- Soft warning at $2 with option to continue
- Hard pause at $5 with explicit override

Monthly cost summary in Settings.

### 7.10 Export

- **Markdown:** verdict brief, arguments for and against, pre-mortem, test
- **PDF:** formatted brief

Share sheet support disabled in v1 (out of scope).

### 7.11 Air Gap Mode

Global toggle in Settings plus automatic enforcement for confidential sensitivity class.

When on:

- All cloud API calls blocked at the networking layer
- Only MLX (and optional Ollama) paths execute
- Title bar indicator reads "Air Gap Active"

### 7.12 Settings

- API keys per provider (stored in Keychain)
- Model selection menu (per-provider enable, tier, costs, set membership)
- Default debate rounds
- Default samples per persona
- Default outcome deadline
- Cost guardrails (soft, hard)
- Air gap toggle
- Local model management (download, quantization level, unload, delete)
- Export defaults (location, format order)

---

## 8. Data Model

SQLite local database. Tables:

- **decisions** — id, created_at, status, question, lens_template, reversibility, time_horizon, sensitivity_class, success_criteria, refined_brief, refinement_chat_log
- **model_runs** — id, decision_id, model_name, provider, persona, round_number, sample_number, temperature, prompt, response, tokens_in, tokens_out, cost_usd, created_at, error
- **arguments** — id, decision_id, source_model_run_id, position, text, cluster_id, prominence
- **clusters** — id, decision_id, position, centroid_text
- **verdicts** — id, decision_id, verdict_text, confidence, key_for_json, key_against_json, risk, blind_spot, opportunity, pre_mortem, outcome_deadline, test_action, test_metric, test_threshold, created_at
- **outcomes** — id, verdict_id, marked_at, result, actual_notes, what_changed
- **settings** — key, value (simple kv store)

Files on disk under Application Support / The Council:

- Per-decision folder for original attachments, graph state, exported briefs
- Local model weights under user-managed directory (Settings exposes path)

---

## 9. UI Screens

### 9.1 Home

- **Left sidebar:** New Decision, This Week, All Decisions, Settings
- **Main:** list of recent decisions with status, last activity, verdict deadline if applicable

### 9.2 New Decision (Intake Form)

Single-column form, 7 fields, primary button "Refine with Claude".

### 9.3 Refinement Chat

Two-pane: left shows current draft of the refined brief, right shows the Claude conversation. Primary button at bottom: "Approve and run council".

### 9.4 Council Configuration

Compact view with pre-filled defaults. Expandable sections for per-model and per-persona overrides. Primary button: "Run Council".

### 9.5 Council Execution

Progress view with timeline of rounds, per-model status chips, live token/cost counter, cancel button.

### 9.6 Synthesis Map

Full-screen canvas. Right panel: verdict tray plus argument detail. Top bar: filter toggles, layout controls, "Capture Verdict" button.

### 9.7 Verdict Capture

Form layout matching the brief template. Pre-populated from tray. Confidence slider, deadline picker, pre-mortem textarea with AI assist button. Primary button: "Save Verdict".

### 9.8 Decision Detail

Tabs: Brief, Council Transcript, Synthesis Map, Verdict, Outcome.

### 9.9 This Week (Calibration Review)

List of verdicts due. Per verdict: brief summary, mark outcome controls, notes field.

### 9.10 Settings

Standard Mac preferences layout. Tabs: General, Models, Debate, Cost, Air Gap, Export, About.

---

## 10. Technical Architecture

- **Platform:** macOS 15+ (latest SDK)
- **UI:** SwiftUI
- **Language:** Swift 6
- **Storage:** SQLite via GRDB.swift
- **Secrets:** Keychain via KeychainAccess
- **Local inference:** MLXSwift (primary), Ollama HTTP bridge (optional)
- **Cloud APIs:** Swift async HTTP clients per provider (Anthropic, OpenAI, Google, xAI)
- **Graph rendering:** SwiftUI Canvas + custom force simulation (Verlet or Barnes-Hut for 100+ nodes)
- **PDF:** PDFKit
- **Markdown:** Apple Swift Markdown
- **Build:** Xcode, SPM dependencies
- **Distribution:** Direct download signed and notarized DMG, no Mac App Store

---

## 11. Acceptance Criteria

v1 ships when (aligned with SPEC §13):

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

## 12. Edge Cases

- Cloud API rate limit mid-council: partial results marked, decision re-runnable for failed models.
- Token budget exceeded mid-run: hard pause, show partial results, option to continue with override.
- Model returns invalid JSON or empty response: mark run failed, continue with remaining models.
- User dismisses refinement chat with no questions asked: allowed, show a gentle reminder dialog.
- Local model fails to load (insufficient RAM): clear error with suggested remediation.
- Outcome deadline passes with no marking: verdict surfaces in weekly review indefinitely until marked or dismissed.
- User imports a pre-existing decision mid-flow: supported via paste into intake question field.

---

## 13. Risks

- **MLX stability on M5.** MLX is young. Sequential runs at 32B class models not extensively tested on 32GB. *Mitigation:* fallback to 22B class primary if 32B fails to load or crashes.
- **Cloud API drift.** Providers change endpoints, rate limits, and pricing. *Mitigation:* version-pin API adapters, show a notice when a provider responds with unexpected schema.
- **Force-directed graph performance.** 200+ node graphs need careful optimization. *Mitigation:* performance budget monitoring during build, fallback to structured column view.
- **Calibration requires discipline.** If the user does not mark outcomes, the ledger loses its value. *Mitigation:* aggressive weekly review prompts, one-click mark, outcome prompt in title bar while pending.

---

## 14. Resolved Decisions

Previously open questions, closed for v1:

- **Claude-assist in verdict drafting.** RESOLVED: manual synthesis is the default. An optional "Draft verdict with Claude" button generates a 2–4 sentence first-draft using `claude-sonnet-4-6` from the refined brief plus verdict tray contents. Implementation: SPEC §6.8.
- **Pre-mortem source.** RESOLVED: Claude only for v1. Pre-mortem generated by `claude-sonnet-4-6` on Save Verdict; user can edit before final save. Implementation: SPEC §6.8.
- **Onboarding flow.** RESOLVED: minimal. First launch prompts for API key via Settings → Models. No guided tour, no sample decision. Implementation: SPEC §9.

---
