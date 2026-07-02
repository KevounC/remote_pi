---
id: epic-bold-transcript-event-log-projection-derive-step-1
kind: story
stage: done
tags: [refactor, bold, pi-extension, app, cockpit]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: []
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 1: Define the `TranscriptEvent` algebra and projection contract

**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `app/lib/domain/transcript/transcript_event.dart`, `app/lib/domain/transcript/transcript_projection.dart`, `pi-extension/src/session/transcript_event.ts`, `cockpit/lib/app/cockpit/domain/entities/transcript_event.dart`

## Current State

```dart
// app/lib/data/local/records/message_record.dart
enum MsgRole { user, assistant, tool, compaction }

class MessageRecord {
  final String id;
  final int seq;
  final MsgRole role;
  final bool pending;
  ChatMessage toChatMessage() { /* UI projection lives on the row model */ }
}
```

```ts
// pi-extension/src/index.ts
type BufferMsg = { role: "user" | "assistant" | "toolResult" | string; content?: unknown; timestamp?: number };
let _messageBuffer: BufferMsg[] = [];
```

## Target State

Define a canonical event algebra per surface, using the same kind and field names:

```dart
sealed class TranscriptEvent {
  const TranscriptEvent({required this.eventId, required this.sessionId, required this.ts, this.turnId});
  final String eventId;
  final String sessionId;
  final DateTime ts;
  final String? turnId;
}

final class UserMessageSubmitted extends TranscriptEvent { /* clientMessageId, text, image */ }
final class UserMessageConfirmed extends TranscriptEvent { /* clientMessageId, text, image, streamingBehavior */ }
final class UserMessageFailed extends TranscriptEvent { /* clientMessageId, code, message */ }
final class AssistantDeltaReceived extends TranscriptEvent { /* replyTo, delta */ }
final class AssistantMessageCommitted extends TranscriptEvent { /* messageId, replyTo, text, usage */ }
final class AssistantDoneReceived extends TranscriptEvent { /* replyTo, usage */ }
final class ToolRequested extends TranscriptEvent { /* toolCallId, tool, args */ }
final class ToolFinished extends TranscriptEvent { /* toolCallId, result, error */ }
final class CompactionRecorded extends TranscriptEvent { /* summary, tokensBefore */ }
```

Projection contract returns `messages`, `streaming`, and a lightweight `TranscriptTurnView` without importing Hive, widgets, WebSocket, or Pi SDK types.

## Implementation Notes

- `sessionId` is required on every event and is opaque equality-only.
- `eventId` is deterministic for server replay (`server:<sessionId>:<kind>:<stable-key>:<ts>`) and UUIDv7/local for optimistic events.
- Carry `turnId` when available but do not depend on the turn-state-machine sibling landing first.
- Keep app, TS, and cockpit kind names aligned so generated-protocol/patchbay can lift the contract later.
- Add a clearly named compatibility boundary for pre-canonical-session active session ids; do not let missing ids flow into core projection code.

## Acceptance Criteria

- [x] Event kind names and required fields are centralized on each touched surface.
- [x] Every event requires `sessionId`; adapters provide an explicit compatibility shim only at the boundary.
- [x] Projection contract returns `messages`, `streaming`, and `turn` without infrastructure imports.
- [x] No runtime behavior changes yet; this is side-by-side.

## Risk

Medium. Drift between per-language event mirrors would recreate the current protocol-mirror problem.

## Rollback

Delete the new event/projection contract files. No existing runtime should depend on them until later steps.

## Implementation Notes

Implemented inline by the bold-refactor implement-orchestrator because no subagent dispatcher is exposed in this delegated harness. Added side-by-side transcript event algebra files for the app, Pi extension, and Cockpit using aligned kind/field names and required opaque `sessionId`/`sessionId` fields. Added the app projection seam (`deriveTranscriptProjection`) returning `messages`, `streaming`, and `TranscriptTurnView`; it is intentionally a minimal pure side-by-side reducer so later steps can pin the full optimistic/authoritative reconcile semantics without changing current runtime adapters in this story.

Runtime behavior is unchanged: no SyncService, Pi-extension history, or Cockpit session code imports these contracts yet.

Verification:
- `cd pi-extension && corepack pnpm typecheck` passed.
- `cd app && HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/domain/transcript/transcript_event.dart lib/domain/transcript/transcript_projection.dart` passed.
- `cd cockpit && HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/app/cockpit/domain/entities/transcript_event.dart` passed.
- Full `flutter analyze` was skipped because `/opt/flutter/bin/cache` is read-only in this environment; direct Dart analyzer with a writable HOME was the nearest meaningful check.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Verified commit `302afa4`, changed files, and parent projection-derive design. Reviewer reran `cd pi-extension && corepack pnpm typecheck`, the nearest app analyzer check `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/domain/transcript/transcript_event.dart lib/domain/transcript/transcript_projection.dart`, and the nearest cockpit analyzer check `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/app/cockpit/domain/entities/transcript_event.dart`. Full `flutter analyze` was attempted in both `app/` and `cockpit/`, but both failed before analysis because `/opt/flutter/bin/cache` is read-only.
