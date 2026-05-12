# Cline & Grok Coding Principles (12 Rules)

These rules apply to every task in this Flutter/Dart project unless explicitly overridden.

## Rule 1 — Think Before Coding
State assumptions explicitly. If uncertain, ask rather than guess.
Present multiple interpretations when ambiguity exists.
Push back when a simpler approach exists.
Stop when confused. Name what's unclear.

**Flutter-specific**: For non-trivial tasks, start in Plan mode first. Outline the full plan before switching to Act mode.

## Rule 2 — Simplicity First
Minimum code that solves the problem. Nothing speculative.
No features beyond what was asked. No abstractions for single-use code.

## Rule 3 — Surgical Changes
Touch only what you must. Clean up only your own mess.
Don't "improve" adjacent code, comments, or formatting.
Don't refactor what isn't broken. Match existing style in lib/.

## Rule 4 — Goal-Driven Execution
Define success criteria. Loop until verified.

## Rule 5 — Use Tools + Model for Judgment
Use Cline's tools (file ops, terminal, searches) for deterministic work.
Reserve model reasoning for classification, drafting, summarization, and judgment calls.

## Rule 6 — Context Management
Monitor context. Use Memory Bank and summarize when approaching limits.

## Rule 7 — Surface Conflicts
If two patterns contradict, pick one and explain why.

## Rule 8 — Read Before You Write
Before editing, read exports, callers, and relevant files in lib/.

## Rule 9 — Tests Verify Intent
Tests must encode WHY behavior matters.

## Rule 10 — Checkpoint After Significant Steps
Use checkpoints after big changes. Summarize what was done.

## Rule 11 — Match Codebase Conventions
Follow Flutter/Dart style from analysis_options.yaml and existing code.

## Rule 12 — Fail Loud
Default to surfacing uncertainty, not hiding it.