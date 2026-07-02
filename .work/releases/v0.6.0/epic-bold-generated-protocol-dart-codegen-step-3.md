---
id: epic-bold-generated-protocol-dart-codegen-step-3
kind: story
stage: done
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-2]
tags: [refactor]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
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

## Implementation notes

- Files changed: `tools/protocol-codegen/bin/protocol-codegen.mjs`, `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`, `app/lib/protocol/generated/protocol.g.dart`, `app/lib/protocol/protocol.dart`, `app/test/protocol_codegen/server_messages_codegen_test.dart`, `.orchestration/contracts/fixtures/{action_error,action_ok,compaction,models_list,queued_message_state}.jsonl`.
- Generator changes: the Dart emitter now supports schema/IR aliases, generated adapter decoders for existing hand DTOs, server/history field codecs, and generated registries for `ServerMessage` and `SessionHistoryEvent`.
- Runtime narrowing: `ServerMessage.fromJson` and `SessionHistoryEvent.fromJson` now delegate discriminant narrowing to generated schema-derived dispatch while preserving the existing hand DTO classes until the Step 4 facade swap.
- Tests added: server/message codegen tests prove registry parity, generated server/history variant narrowing, unknown top-level/nested rejection, hand-protocol generated dispatch delegation, and explicit server/client/control fixture classification.
- Regen-diff confirmation: reran `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out app/lib/protocol/generated/protocol.g.dart`; `git diff --stat -- app/lib/protocol/generated/protocol.g.dart` reported only `app/lib/protocol/generated/protocol.g.dart | 898 +++++++++++++++++++++++++++++` (`1 file changed, 898 insertions(+)`). No hand edits were made to the generated file.
- Verification: `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/protocol_codegen/` passed; `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze` reported only the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` and exited 1.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane; generated-contract invariant verified)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified the generated-contract invariant.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 4ba0339` — exactly the right file set: generator (`tools/protocol-codegen/bin/protocol-codegen.mjs` + IR fixture `app_pi_client_dart_ir.json`), regenerated `app/lib/protocol/generated/protocol.g.dart`, `app/lib/protocol/protocol.dart`, codegen test `server_messages_codegen_test.dart`, + 5 new contract fixtures. No stray files; no collision with other app agents (ws_transport/connection_manager untouched).
- **REGEN CHECK**: ran `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema .../app_pi_client_dart_ir.json --out /tmp/regen_protocol.g.dart` and `diff` against the committed `protocol.g.dart` → **EMPTY DIFF**. The generated file matches generator output exactly — no hand-edits. Generated-contract invariant holds (change is in the generator, not the generated file).
- `cd app && flutter test test/protocol_codegen/` (PUB_CACHE set) — 15/15 pass (server fixtures decode + classified; generator output deterministic + matches golden; union narrows fromJson + round-trips toJson; exhaustive switch supported; unknown/nested types covered).
- `flutter analyze` — only the known-unrelated `axisAlignment` info.
- Acceptance criteria satisfied: handwritten discriminant switch replaced by schema-derived generated decoding; generator-extended, regenerated, regen-diff clean.
