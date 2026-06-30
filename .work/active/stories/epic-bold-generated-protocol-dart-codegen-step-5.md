---
id: epic-bold-generated-protocol-dart-codegen-step-5
kind: story
stage: review
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-4]
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 5: Add generated-protocol parity checks and implementation handoff notes

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: contract-test gap / pattern drift  
**Files**: `app/test/protocol_codegen/`, `.orchestration/contracts/fixtures/`, `.work/active/features/epic-bold-generated-protocol-dart-codegen.md`

## Current State

The existing app fixture smoke test accepts either a parsed message or `UnsupportedTypeException` for every fixture line:

```dart
test('all fixture lines parse or throw UnsupportedTypeException', () {
  final files = fixtureDir.listSync().whereType<File>().toList();
  for (final file in files) {
    final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
    for (final line in lines) {
      try {
        final msg = decodeServer(line);
        expect(msg, isNotNull);
      } on UnsupportedTypeException {
        // client-only types (user_message, approve_tool, etc.) — expected
      }
    }
  }
});
```

That catches gross parser crashes but does not prove server variant coverage or TS/Dart codec parity.

## Target State

Add explicit parity tests around the generated Dart target so the generated schema becomes the contract test:

```dart
const serverFixtureFiles = {
  'pair_ok.jsonl',
  'pair_error.jsonl',
  'agent_stream.jsonl',
  'user_input.jsonl',
  'agent_message.jsonl',
  'tool_request.jsonl',
  'tool_result.jsonl',
  'session_history.jsonl',
  'error.jsonl',
  'cancelled.jsonl',
  'pong.jsonl',
  'bye.jsonl',
};

test('every server fixture decodes through generated ServerMessage', () {
  for (final file in serverFixtureFiles) {
    for (final line in fixtureLines(file)) {
      expect(decodeServer(line), isA<ServerMessage>());
    }
  }
});

test('generated server type registry matches schema variants', () {
  expect(generatedServerMessageTypes, schemaServerMessageTypes);
});
```

## Implementation Notes

- Keep `.orchestration/contracts/fixtures/` as the legacy cross-language fixture suite until the whole generated-protocol epic retires it.
- The Dart target should expose generated variant registries for tests only; production dispatch must still narrow through `fromJson`, not use ad-hoc sets.
- Record in the feature body any generator limitations discovered during implementation (for example: a control frame deferred because sibling schema does not model relay frames yet).
- If implementation proves the selected custom generator cannot maintain clean sealed classes, stop and bounce the parent feature to `drafting` with the concrete failure. Do not silently fall back to a schema-driven hand mirror.

## Acceptance Criteria

- [x] Tests distinguish server, client, and relay-control fixtures instead of swallowing every unsupported type.
- [x] A schema/generated registry parity check fails when a Dart server variant is omitted.
- [x] The feature body records the final feasibility verdict and any deferred control-frame scope.
- [x] No new hand-maintained protocol variant registry is introduced in Dart.

## Implementation

- Added generated-protocol parity coverage in `app/test/protocol_codegen/server_messages_codegen_test.dart`: the test now compares generated server/history registries against `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`, narrows every server variant through generated `ServerMessage.fromJson`, and classifies every legacy JSONL fixture as server, client-only, or relay-control instead of accepting `UnsupportedTypeException` for all lines.
- Fixture classification counts: 18 server fixture files, 5 client-only fixture files, 13 relay-control fixture files; observed server fixture types must equal `generatedServerMessageTypes`.
- Feasibility verdict recorded in the parent feature: the custom Dart generator remains feasible and implemented with clean generated sealed unions; no hand-maintained schema mirror fallback was used.
- Deferred scope recorded in the parent feature: relay control/presence/rooms frames remain in the temporary hand-maintained `control_frames.dart` island and in `.orchestration/contracts/fixtures/` until the broader generated-protocol epic retires that legacy suite.
- Verification: `flutter pub get` completed; `flutter analyze` reported only the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` (command exits non-zero on that info); `flutter test test/protocol_codegen/` passed 15 tests from `app/` with `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache`.

## Rollback

Remove the new parity tests and handoff note changes. Runtime generated protocol remains controlled by Step 4.
