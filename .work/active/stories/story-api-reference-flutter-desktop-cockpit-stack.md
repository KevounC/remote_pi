---
id: story-api-reference-flutter-desktop-cockpit-stack
kind: story
stage: drafting
tags: [cockpit, research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
created: 2026-06-27
updated: 2026-06-27
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

## Acceptance

- A cockpit reference skill/doc exists or this item records a deferral rationale if cockpit stays out of the near-term refactor.
- Current package APIs are checked for pre-1.0 churn (`shadcn_flutter`, terminal/PTY packages).
- Guidance is linked from root or cockpit-specific agent instructions.
