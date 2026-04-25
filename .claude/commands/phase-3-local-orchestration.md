---
description: Phase 3 runbook — air gap mode runs Qwen and Mistral sequentially with zero cloud traffic
---

# Phase 3 — Local Model Orchestration

Weeks 5-6. Full detail: PLAN.md §Phase 3. SPEC cross-refs: §6.1, §6.5 (local block), §8.2.

## Objectives

- Implement `MLXRunner` sequential load → run → unload for Qwen 2.5 32B (4-bit) then Mistral Small 22B (4-bit)
- Memory pressure gate: poll `mach_host_self()` and `ProcessInfo.thermalState`; proceed only when nominal and ≥ 10 GB free
- Qwen 32B fallback to Qwen 14B class on load failure (user confirmation dialog)
- Thermal throttle banner: pause inference, resume automatically when thermal state returns
- Implement `OllamaClient` as optional HTTP bridge to `http://localhost:11434`
- Build local model download manager (Settings → Air Gap tab): download, checksum, unload, delete, directory picker
- Patch `URLSession` shared configuration to block AI hostnames per SPEC §6.1; re-apply before every council run
- Air gap toggle + `confidential` sensitivity auto-enables
- Title-bar "Air Gap Active" indicator

## Definition of done

- Air gap on → run a 3-round decision with Qwen then Mistral; both complete, outputs stored
- Sequential RAM handoff verified: model 2 does not load until model 1 fully unloads
- Zero outbound connections to AI hostnames during air gap run (verify via proxy)
- Confidential decision auto-routes to local with no cloud option available

## Exit gate

Run `/airgap-verify` and `/spec-check` scoped to §6.1, §8.2.
