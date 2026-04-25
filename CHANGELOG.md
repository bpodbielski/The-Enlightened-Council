# CHANGELOG

All notable changes to The Council. Format based on Keep a Changelog. Semantic versioning.

---

## [Unreleased]

### Planning
- Initial PRD, SPEC, PLAN, BUILD_PLAN authored
- CLAUDE.md, STYLE.md, TESTING.md scaffolded
- .claude/ directory with commands and subagents created
- Resource scaffolding for lens templates and personas created
- Build and notarize scripts drafted

### Added — Phase 2 (Cloud Orchestration)
- `AirGapNetworkGuard` URLProtocol blocking 4 provider hostnames when air gap is active; installed into every cloud client
- `OpenAIClient`, `GeminiClient`, `GrokClient` actors implementing `StreamingChatClient` (SSE, 429 exponential backoff 2s→64s ×5, 5xx retries ×3)
- `LensTemplate` + `LensTemplateLoader` (8 validated IDs)
- `Persona` + `PersonaLoader` (YAML front matter parser, 10 validated IDs)
- `ModelSpec` with frontier/balanced sets and `estimatedCost(tokensIn:tokensOut:)`
- `CostGuardrails` with boundary-cross-only evaluate (soft $2, hard $5)
- `CouncilOrchestrator` actor running rounds via `withTaskGroup`, emitting `OrchestratorEvent` stream
- `CouncilConfigurationView` + VM: model/persona chips, rounds/samples steppers, estimated cost, Run button
- `ExecutionView` + VM: per-run timeline, status chips, live $/token counter, cancel, soft/hard alerts
- Phase 2 navigation wired: Refinement sign-off → Configuration → Execution

### Added — Phase 3 (Local Orchestration)
- `LocalResourceGate` — memory + thermal pre-flight check with injectable providers (testable). `host_statistics64`-backed free-memory estimate.
- `MLXRunner` actor — sequential load/run/unload scaffold, model catalog (Qwen 2.5 32B with 14B fallback, Mistral Small 22B), gate integration, placeholder stream keeping the orchestrator dispatch path wired end-to-end.
- `OllamaClient` actor — NDJSON streaming against localhost:11434 (configurable via `ollama_base_url` setting), accepts both chat-API `message.content` and generate-API `response` frame shapes.
- `ModelDownloadManager` actor — Application Support models directory plumbing, presence checks, stub download transport.
- Air gap guard refresh on app launch; Settings toggle now flips live `AirGapURLProtocol.active` in addition to persisting.
- Confidential decisions auto-enable air gap before orchestrator dispatch.
- Title-bar "Air Gap Active" indicator in `ContentView` toolbar with tooltip.
- `CloudClientFactory` extended to return `MLXRunner.shared` / `OllamaClient.shared` for `.localMLX` / `.localOllama` providers — orchestrator dispatches local and cloud identically.

### Added — Phase 4 (Debate Engine)
- `DebateEngine` — 3-round protocol per SPEC §6.4. Stable `(model,persona) → Perspective X` anonymization (sort-order keyed). `buildRound2Tasks` excludes own round-1 output and labels others anonymously. `buildRound3Tasks` feeds each target its own round-1 and all other round-2 rebuttals. `parsePosition(in:)` recognizes `POSITION: maintained|updated` case-insensitively at line start.
- `ArgumentExtractor` actor — sends aggregated round-3 responses to Claude for JSON extraction. `parseArgumentsJSON` tolerates fenced code blocks and leading prose via bracket-balanced scan; unknown positions fall back to `.neutral`; empty / malformed input throws.
- `ClusteringEngine` actor — `Embedder` protocol (cloud OpenAI `text-embedding-3-small`, local MLX). k-means++ seeding, elbow selection across k ∈ [2, 8], prominence = cluster size / total, representative text = nearest point to centroid. Deterministic SplitMix64 RNG.
- `CouncilOrchestrator.runDebate(...)` — round-driven flow: round 1 from caller, rounds 2/3 built dynamically via `DebateEngine` using the prior round's completed `ModelRun`s (captured via `CaptureBox` actor).
- Round-3 `position_changed` writeback — orchestrator's `execute` now parses `DebateEngine.parsePosition` on round-3 responses and writes to `model_runs.position_changed`.
- `Argument` gains explicit memberwise initializer for construction in the extractor path.

---

## [0.0.1] — TBD (Phase 0 close)

### Added
- Xcode project, Swift 6, macOS 15+ target
- SPM dependencies (GRDB.swift, KeychainAccess, MLXSwift, swift-markdown)
- Database schema with all 7 tables
- Keychain storage for 4 provider API keys
- Settings skeleton with 7 tabs
- Force-simulation spike results
