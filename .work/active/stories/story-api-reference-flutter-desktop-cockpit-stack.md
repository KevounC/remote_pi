---
id: story-api-reference-flutter-desktop-cockpit-stack
kind: story
stage: done
tags: [cockpit, research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
release_binding: null
gate_origin: null
research_refs: [flutter-desktop-cockpit-skill-base]
research_dials:
  scope_authority: mixed
  verification_rigor: floor
  intent: flutter-desktop-api-reference
  output_kind: skill-reference-or-deferral
created: 2026-06-27
updated: 2026-06-28
---

# API reference for Flutter desktop cockpit stack

Create a platform-style stack reference for `cockpit/` so desktop work does not rely on tribal knowledge or mobile-app assumptions.

## Candidate coverage

- Flutter desktop lifecycle and window management.
- `shadcn_flutter` UI conventions used by cockpit.
- `flutter_modular` module/route/binding patterns.
- Local persistence via Hive.
- Terminal/process/file surfaces: `xterm`, `kyroon_pty`, `file_picker`, `window_manager`, drag/drop/pasteboard packages.
- Markdown/media/file preview packages where they shape UI behavior.
- Notification behavior via `flutter_local_notifications`.
- Test/dev cycle: `flutter analyze`, `flutter test`, desktop run/build commands.

## Known gotchas to include

- Cockpit is a desktop operator surface, not a mobile app; do not copy provider/go_router assumptions from `app/`.
- PTY/process and file-picker surfaces cross OS boundaries and need platform-specific smoke checks.
- Agent-output rendering and terminal surfaces need defensive handling for large logs, ANSI output, and long-running tasks.

## Implementation notes

- Added `.agents/skills/flutter-desktop-cockpit/SKILL.md` as the cockpit stack reference.
- Added source-grounded synthesis at `.research/analysis/briefs/flutter-desktop-cockpit-skill-base.md`.
- Added attestations for local cockpit guidance, local package pins/overrides, module/bootstrap shape, terminal/file surfaces, Flutter desktop support, `flutter_modular`, `shadcn_flutter`, Hive, PTY/xterm, and native package docs.
- Linked the reference from root `AGENTS.md` and `cockpit/CLAUDE.md`.
- Checked current package/API churn: `shadcn_flutter` and `flutter_modular` are current at local pins; several native packages have newer pub.dev releases than the lockfile; `xterm`, `kyroon_pty`, and `gpt_markdown` are git overrides and must follow local refs.
- Citation lint passed with zero broken citations for the synthesis and skill; warnings were limited to version-number/comparative heuristic flags and substrate-confidence deprecation notices.

## Acceptance

- [x] A cockpit reference skill/doc exists or this item records a deferral rationale if cockpit stays out of the near-term refactor.
- [x] Current package APIs are checked for pre-1.0 churn (`shadcn_flutter`, terminal/PTY packages).
- [x] Guidance is linked from root or cockpit-specific agent instructions.
