---
id: epic-bold-generated-protocol-dart-codegen-step-3
kind: story
stage: implementing
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-2]
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Generate Dart server messages, history events, and decode narrowing

**Priority**: High  
**Risk**: High  
**Source Lens**: duplicated variants / codec drift / generated contract  
**Files**: `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_codegen/`, `.orchestration/contracts/fixtures/`

## Current State

Server-side decoding is a handwritten discriminant switch in `app/lib/protocol/protocol.dart`:

```dart
sealed class ServerMessage {
  const ServerMessage();

  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'agent_chunk' => AgentChunk.fromJson(json),
      'agent_done' => AgentDone.fromJson(json),
      // ... hand-maintained list ...
      'models_list' => ModelsList.fromJson(json),
      _ => throw UnsupportedTypeException(type ?? ''),
    };
  }
}
```

Nested history events repeat the same pattern:

```dart
sealed class SessionHistoryEvent {
  final int ts;
  const SessionHistoryEvent({required this.ts});

  factory SessionHistoryEvent.fromJson(Map<String, dynamic> j) {
    final ts = (j['ts'] as num).toInt();
    return switch (j['type'] as String?) {
      'user_input' => UserInputEvt(...),
      'compaction' => CompactionEvt(...),
      final t => throw UnsupportedTypeException(t ?? ''),
    };
  }
}
```

The TS codec has already drifted from the TS union (`SERVER_TYPES` omits live variants), which proves hand registries are the failure mode this step eliminates.

## Target State

Generate the complete `ServerMessage` and `SessionHistoryEvent` unions from the schema/IR, including a generated type registry used for tests rather than manually edited codec lists:

```dart
const Set<String> generatedServerMessageTypes = {
  'pair_ok',
  'pair_error',
  'user_input',
  'user_message',
  'queued_message_state',
  'agent_chunk',
  'agent_done',
  'agent_message',
  'compaction',
  'tool_request',
  'tool_result',
  'error',
  'cancelled',
  'pong',
  'bye',
  'session_history',
  'action_ok',
  'action_error',
  'models_list',
};

sealed class ServerMessage {
  const ServerMessage();
  String get type;

  static ServerMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'agent_chunk' => AgentChunk.fromJson(json),
      // generated from schema, not handwritten
      final unknown => throw UnsupportedTypeException(unknown ?? ''),
    };
  }
}
```

## Implementation Notes

- Preserve current permissive/compatibility behavior intentionally encoded in the hand mirror:
  - `user_input` and `user_message` both narrow to the same app-side user-input payload until canonical session work changes the contract.
  - `PairOk` still tolerates missing `session_started_at` and `room_id` during transition.
  - `Bye` keeps an `unknown` enum value with `rawReason` for forward-compatible logging.
  - Unknown top-level message types still throw `UnsupportedTypeException`.
- Keep field parsing behavior wire-equivalent for this refactor. Do not introduce a new public decode error taxonomy in this step; stricter validation can be a later behavior-changing item if desired.
- Add fixture-derived tests that assert every server fixture parses as a generated `ServerMessage` and every client-only/control fixture is explicitly classified, not silently swallowed.
- Add a generator test that fails if schema server variants and `generatedServerMessageTypes` diverge.

## Acceptance Criteria

- [ ] Generated `ServerMessage.fromJson` covers every current server variant, including `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.
- [ ] Generated `SessionHistoryEvent.fromJson` covers every current history event variant.
- [ ] Unknown top-level and nested types still throw `UnsupportedTypeException`.
- [ ] Fixture tests are stronger than the current "parse or throw" smoke and fail on an omitted server variant.

## Rollback

Revert the generated server output and tests. The hand mirror remains the runtime parser until Step 4.
