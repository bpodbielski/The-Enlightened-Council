---
description: Scan a decision brief for PII patterns and surface suggested redactions
---

# redaction-check

Per SPEC §6.7. Used inside the refinement chat and as a standalone pre-flight check for any brief about to be routed to cloud models.

## Patterns

- **Email:** `\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b`
- **Dollar amounts:** `\$[\d,]+(\.\d{2})?`
- **Person names (heuristic):** capitalized two-word pairs not in a known-places dictionary
- **Custom keywords:** user-configurable list in Settings

## Output

For each hit, produce a `{start, end, type, suggestion}` record. Render in the brief draft as `[REDACTED: <type>]` with approve / dismiss buttons.

## Usage

Paste a brief into the argument and the command returns a list of suggested redactions with line and column offsets. Apply on approval.

## Suppression

If sensitivity class is `confidential`, redaction is not required (air gap enforced anyway). Still surface the list for user awareness.
