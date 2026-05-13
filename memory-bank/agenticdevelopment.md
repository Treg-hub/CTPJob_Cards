# Agentic Development Loop v2 — CTP Job Cards

**Purpose**: Defines the exact workflow the AI agent (Grok / Cline / future agents) must follow when building or modifying the CTP Job Cards app.  
**Goal**: Maximize autonomous building capability while staying 100% compliant with AGENTS.md, .clinerules/, and Memory Bank rules.  
**Last Updated**: 2026-05-13

---

## Core Principles (Non-Negotiable)

- Always start every task by reading **ALL** files in `memory-bank/`.
- Never suggest direct pushes to `master`. Always use feature branches.
- Every change must be **surgical** (Rule 3), **simple** (Rule 2), and **goal-driven** (Rule 4).
- Full code only — no placeholders.
- Hand-holding: Always provide exact GitHub paths and precise placement instructions.
- Future scaling first: Every plan must consider pagination, multi-site, Genkit AI embedding, web/desktop, and agent scalability.

---

## The Agentic Development Loop (6 Steps)

### Step 1: Memory Sync (Mandatory)
Re-read every file in `memory-bank/`:
- projectbrief.md
- productContext.md
- activeContext.md
- progress.md
- systemPatterns.md
- techContext.md
- dependencies.md (new)
- This file (agenticDevelopment.md)

### Step 2: Plan Mode (Before Any Code)
Output must include:
- Explicit assumptions
- Success criteria (measurable)
- Affected files with full GitHub URLs
- Scaling impact analysis
- Risks & simpler alternatives considered
- Confirmation that `dependencies.md` was read for correct parameters

### Step 3: Act Mode (Only After User Approval)
- Provide **complete, full code** (no placeholders)
- Exact placement instructions with surrounding context
- Reference to `dependencies.md` for any package usage

### Step 4: Verification
Always suggest:
```bash
flutter analyze
flutter test (when applicable)
```
Update `progress.md` and `activeContext.md` with results.

### Step 5: Commit Preparation (Per AGENTS.md)
Provide:
- Recommended feature branch name
- Full commit message
- PR description with testing steps
- Link to this workflow

### Step 6: Memory Bank Update (Always End Here)
Update at minimum:
- `activeContext.md` — add what was done
- `progress.md` — mark completed items
- This file if workflow improved

---

## Future Scaling Guardrails (Apply to Every Plan)

1. **Performance** — Never add full `StreamBuilder` rebuilds on large lists. Use pagination + query limits.
2. **Genkit / AI** — Leverage existing `.agents/skills/firebase-ai-logic` and `developing-genkit-dart` for future smart features (predictive assignment, recurring issue detection).
3. **Multi-platform** — All new UI must be responsive (mobile + web + desktop).
4. **Testing** — Every new feature must include basic unit/widget test scaffolding.
5. **Agent Scalability** — This workflow must support multiple agents working in parallel without conflict.

---

## How to Use This Workflow (For Agents)

1. User gives high-level request.
2. Agent reads all Memory Bank files (including this one + dependencies.md).
3. Agent outputs **Plan Mode** response.
4. User replies “Proceed to Act Mode” or gives adjustments.
5. Agent delivers full code + placement instructions.
6. Agent ends with Memory Bank updates + commit prep.

---

## Current Status (2026-05-13)

- Dependencies Reference file created (`dependencies.md`)
- This workflow file created
- Project is in Beta/Production Ready phase (see progress.md)
- Next major focus: Performance optimization + Genkit integration readiness

---

**This file is now mandatory reading for every coding task.**