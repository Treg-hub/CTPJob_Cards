# AGENTS.md — Rules for Grok & Cline on CTPJob_Cards

These rules apply whenever working on code that will be committed or pushed to this repository.

## Core Principles
- Follow the 12 coding principles in .clinerules/02-coding-principles.md
- Follow the Memory Bank system
- Stay consistent with existing Flutter/Dart code style

## Repository Workflow
- Never suggest direct pushes to master without approval.
- Always work on a feature branch.
- Before suggesting a push, provide: clear summary + exact git commands + good commit message.
- For PRs, provide complete description including testing steps.

## Build Number (automatic)
- Every commit **auto-bumps** the Flutter build number (`pubspec.yaml` `+N` suffix) via `githooks/pre-commit`.
- **Do not** manually bump the build number in commits — the hook handles it.
- After clone (or if hooks are missing), run once:
  - Windows: `pwsh scripts/setup-githooks.ps1`
  - macOS/Linux: `sh scripts/setup-githooks.sh`

## Code Quality
- All generated code must pass analysis_options.yaml checks.
- Suggest running `flutter analyze` and tests before push.
- Keep changes surgical.
- Update relevant Memory Bank files after significant work.

## Communication
- Be explicit about assumptions.
- Clearly state what the user still needs to do.
- Prefer simplest solution.

## Safety
- Flag any security-sensitive changes.
- Recommend review for production-affecting changes.