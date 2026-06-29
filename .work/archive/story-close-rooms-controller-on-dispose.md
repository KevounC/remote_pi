---
id: story-close-rooms-controller-on-dispose
kind: story
stage: done
tags: [app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: app-v1.1.1
gate_origin: null
archived_atop: unbound
archived_ref: 3dba904
created: 2026-06-28
updated: 2026-06-28
---

# Close ConnectionManager rooms stream on dispose

`ConnectionManager.dispose()` closes status and presence controllers but not `_roomsController`.

## Acceptance Criteria

- [x] Dispose closes `_roomsController` and cancels related timers/subscriptions safely.
- [x] Add/adjust a test proving no rooms event can be emitted after dispose.

## Implementation notes

- Files changed:
  - `app/lib/data/transport/connection_manager.dart`
    - Added `_roomsController.close()` with `isClosed` guard in `dispose()`.
  - `app/test/transport/connection_manager_test.dart`
    - Added test: `roomsStream closes and ignores control frames after dispose`.
- Verification:
  - `cd app && /opt/flutter/bin/flutter analyze` (1 existing pre-existing issue in unrelated file: `lib/ui/chat/widgets/input_bar.dart:802`)
  - `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/transport/connection_manager_test.dart` (pass)
  - `cd app && /opt/flutter/bin/flutter test --concurrency=1` (pass, 497 tests)

## Review (2026-06-28)

Verdict: Approve

Findings: none.

Verification:
- Reviewed commit `9049e05` diff against acceptance criteria.
- Ran `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/transport/connection_manager_test.dart test/data/sync/sync_service_test.dart test/main_lifecycle_test.dart` (pass).