---
id: story-fix-room-switch-snapshot-adoption
kind: story
stage: done
tags: [app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Prevent room snapshots from undoing explicit same-peer room switches

Adversarial review found `_maybeAdoptLegacyRoom` can treat a legitimate same-peer room switch as legacy room discovery and reset outbound routing to the first room in a later snapshot.

## Scope

- Distinguish legacy discovery for peers without a persisted room from explicit user room switches.
- Ensure snapshots refresh metadata without changing `_activeRoomId` after `switchRoom()`.

## Acceptance Criteria

- [x] Switching to a second room on the same peer survives a later `RoomsSnapshot` whose first room is `main`.
- [x] Legacy peers with no persisted room still adopt the discovered room once.
- [x] Add `ConnectionManager` tests for both cases.

## Implementation discovery

- Preserved existing legacy discovery behavior for peers with `PeerRecord.roomId == null` by using an explicit-switch guard in addition to persisted room detection.
- Introduced an in-memory session flag (`_activeRoomExplicitlySet`) so explicit user room switches are not overwritten by snapshot/announcement discovery.
- `RoomsSnapshot` continues to refresh room metadata via `_maybeAdoptLegacyRoom` while skipping room-id override after explicit switch.

## Implementation notes

- Kept `_maybeAdoptLegacyRoom` logic constrained to `_activeRoomExplicitlySet` and non-null persisted room checks; no behavior for room metadata merging was changed.
- Added two regression tests in `app/test/transport/connection_manager_test.dart` using deterministic `roomsStream.first.timeout(...)` waits:
  - `same-peer switchRoom survives a RoomsSnapshot whose first room is main`
  - `legacy peer with no persisted room adopts first snapshot room once`
- Updated `_ControllableChannel` test double to track `setActiveRoom` calls for transport-level assertions.

## Review (2026-06-28)

Verdict: Approve

Findings: none.

Notes:
- Read the implementation discovery. The `_activeRoomExplicitlySet` guard plus persisted `PeerRecord.roomId` check is sound for the stated compatibility split: explicit user switches are protected, while legacy peers with no persisted room still adopt once and persist the discovered room.

Verification:
- Reviewed commit `ae6d5be` diff against acceptance criteria.
- Ran `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/transport/connection_manager_test.dart test/data/sync/sync_service_test.dart test/main_lifecycle_test.dart` (pass).
