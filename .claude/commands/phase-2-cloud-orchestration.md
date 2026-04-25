---
description: Phase 2 runbook — four cloud models run in parallel with error handling and cost tracking
---

# Phase 2 — Cloud Model Orchestration

Weeks 3-4. Full detail: PLAN.md §Phase 2. SPEC cross-refs: §6.1, §6.5, §7.5, §7.6, §8.1.

## Objectives

- Implement `OpenAIClient`, `GeminiClient`, `GrokClient` (streaming)
- Load 8 lens templates from `Resources/LensTemplates/`
- Load 10 persona prompts from `Resources/Personas/`
- Build `CouncilOrchestrator` with `withThrowingTaskGroup` parallel execution per SPEC §6.5
- Implement round gate (round N+1 waits for all round N to complete or fail)
- Per-run cost tracking writes `tokens_in`, `tokens_out`, `cost_usd`
- Live cost accumulation published to `ExecutionView`
- Cost guardrails: soft warn at $2 (non-blocking), hard pause at $5 (blocking override)
- 429 exponential backoff (2s start, ×2, max 5 retries, max 64s)
- All other errors per SPEC §8.1
- `ExecutionView`: timeline, per-model status chips, live counter, cancel (saves partial)
- `CouncilConfigurationView`: chips, steppers, estimated cost display

## Definition of done

- Single-round run with frontier set (4 models) completes; all outputs stored
- Cost tracked live and matches DB sum
- Simulated 429 degrades gracefully; other models continue; failed run marked `error`
- Cancel mid-run saves partial results and advances to Synthesis Map with warning banner

## Exit gate

`/spec-check` scoped to §6.1, §6.5, §8.1.
