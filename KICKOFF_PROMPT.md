# Kickoff Prompt for Claude Code

Paste the prompt below as your first message in Claude Code after opening this directory.

## How to use

1. Open Terminal and `cd` into this folder.
2. Run `claude` to start Claude Code.
3. Claude Code will auto-load CLAUDE.md from the project root.
4. Paste the prompt below.
5. Review the read-back and answer clarifying questions before saying "go".
6. Checkpoint at the end of each phase.

---

## The prompt

```
I'm building The Council, a native macOS app for multi-model AI decision
debate. The project is scaffolded in this directory. CLAUDE.md has the full
orientation; PRD.md, SPEC.md, PLAN.md, TASKS.md, STYLE.md, and TESTING.md
are the reference docs. The .claude/ directory holds slash commands
(/phase-0-foundation through /phase-10-ship, /spec-check, /force-graph-spike,
/redaction-check, /airgap-verify) and five subagents (swift-engineer,
test-writer, spec-reviewer, graph-performance-specialist, security-reviewer).

Do the following, in order:

1. Read CLAUDE.md, SPEC.md, PLAN.md, and TASKS.md end to end. Skim STYLE.md
   and TESTING.md for conventions.

2. Confirm back to me, in under 200 words: the project name, target platform,
   current phase from PLAN.md, that phase's definition of done, and the first
   three pending tasks in TASKS.md for that phase.

3. Ask any clarifying questions you have about scope, tooling, or intent. Do
   not write code yet. I want to align before Phase 0 begins.

4. Once I say "go", start Phase 0 by running /force-graph-spike first. The
   spike is the non-negotiable Week 1 de-risking prerequisite for Phase 5.
   Record results in Spike/results.md and update TASKS.md with the outcome
   before proceeding.

5. After the spike, work Phase 0 tasks from TASKS.md one at a time. Use the
   swift-engineer subagent for feature code, test-writer for tests. Write
   tests first for parsers, migrations, and orchestration code. Run
   swiftformat, swiftlint, and the scoped test suite before every commit.
   Keep commits small and scoped.

6. Before closing Phase 0, invoke the spec-reviewer subagent and run
   /spec-check scoped to Phase 0 tasks. Also run security-reviewer to confirm
   no telemetry, key leaks, or prohibited dependencies slipped in.

7. When Phase 0 closes, stop and ask me before starting Phase 1. I want a
   checkpoint between every phase.

Hard rules (non-negotiable; full list in CLAUDE.md):
- No telemetry, analytics, or crash-reporting SDKs
- API keys in Keychain only (service names per SPEC §5)
- No SPM dependencies beyond SPEC §2
- Swift 6 strict concurrency, no Combine in new code
- Never mutate a shipped migration; append a new one
- Air gap enforcement verified before every council run when enabled
- SPEC is authoritative for schema, model IDs, hostnames, paths, performance
  budgets, and acceptance criteria

When SPEC is silent or ambiguous on an implementation question, stop and ask
me rather than guess. Log the question in TASKS.md before pausing.

Begin with step 1.
```

---

## Per-phase re-entry prompts

After Phase 0 closes and you want to resume for Phase N:

```
Phase N-1 is closed. Confirm the phase close was reviewed by spec-reviewer
and security-reviewer (paste their pass reports). Then start Phase N.

1. Read PLAN.md §Phase N and SPEC cross-refs.
2. Open the corresponding slash command (/phase-N-<name>) and follow the
   runbook.
3. Work tasks one at a time. Update TASKS.md as you go.
4. Checkpoint with me before closing the phase.
```

## When you hit a blocker

If Claude Code flags an ambiguity, a performance risk, or a hard-rule
conflict, reply with one of:

- "Decision: <answer>. Log it in TASKS.md under Decisions."
- "Pause here. I'll think about it and come back."
- "Escalate to the spec-reviewer subagent and return with its recommendation."

Keep the decision log in TASKS.md so future sessions inherit the context.
