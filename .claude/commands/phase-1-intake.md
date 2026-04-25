---
description: Phase 1 runbook — intake form and Claude-facilitated refinement produce a signed-off brief
---

# Phase 1 — Intake and Refinement

Week 2. Full detail: PLAN.md §Phase 1. SPEC cross-refs: §6.7, §7.3, §7.4.

## Objectives

- Build `IntakeView` with the 7 fields per SPEC §7.3 and validation
- Build `AttachmentView` (file picker + URL field + paste zone)
- Implement `AnthropicClient` with streaming (shared by refinement and council)
- Build `RefinementView` two-pane layout (40% brief / 60% chat)
- Wire refinement system prompt per SPEC §6.7
- Implement redaction pattern matching (email, `$`-amounts, capitalized two-word pairs, custom keywords)
- Render inline `[REDACTED: reason]` with approve/dismiss controls
- Sign-off flow writes `refined_brief`, advances status to `ready`

## Definition of done

- Submit form → refinement chat opens with Claude streaming
- Claude asks 2-4 clarifying questions in one turn
- Redaction suggestions appear for PII and can be approved or dismissed
- Sign-off produces a stored `refined_brief`; status is `ready`

## Notes

- `AnthropicClient` is reused in Phase 2. Design it with a shared protocol now.
- Redaction pattern list is customizable via a user keyword list in Settings.
- Streaming writes to `refinement_chat_log` as a JSON array of `{role, content, timestamp}`.

## Exit gate

`/spec-check` scoped to §6.7 and §7.3.
