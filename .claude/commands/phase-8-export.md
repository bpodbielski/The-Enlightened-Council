---
description: Phase 8 runbook — Markdown and PDF exports with visual parity to on-screen verdict
---

# Phase 8 — Export

Week 13. Full detail: PLAN.md §Phase 8. SPEC cross-refs: §6.10.

## Objectives

- Markdown template per SPEC §6.10
- PDF via PDFKit: same layout, US Letter, system serif body, system monospace for model names
- Header: question + date + lens. Footer: model panel, cost, page number
- Export sheet: Markdown / PDF / Both
- Trigger from Verdict view toolbar and Decision Detail → Verdict tab toolbar
- Default export path from `export_default_path` (default `~/Desktop`)
- Slug function: lowercase, spaces → hyphens, strip special chars, truncate 60 chars
- File naming: `[slugified-question]-[YYYY-MM-DD].md` / `.pdf`

## Definition of done

- Export 3 verdicts to both formats
- Markdown opens cleanly in Typora, Obsidian, Preview
- PDF opens in Preview with correct layout; visual parity with on-screen view
- Files land at configured export path with correct names

## Exit gate

`/spec-check` scoped to §6.10.
