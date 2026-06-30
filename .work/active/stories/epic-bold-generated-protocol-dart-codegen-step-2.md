---
id: epic-bold-generated-protocol-dart-codegen-step-2
kind: story
stage: review
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-1]
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 2: Generate Dart client messages and shared value types beside the hand mirror

**Priority**: High  
**Risk**: Medium  
**Source Lens**: duplicated variants / generated contract  
**Files**: `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_codegen/`, `app/lib/protocol/protocol.dart` (read-only reference)

## Current State

Client-side wire DTOs are handwritten in `app/lib/protocol/protocol.dart` as subclasses with manual `toJson` maps, while the same variants are declared in `pi-extension/src/protocol/types.ts`:

```dart
sealed class ClientMessage {
  Map<String, dynamic> toJson();
}

class UserMessage extends ClientMessage {
  final String id;
  final String text;
  final UserMessageStreamingBehavior? streamingBehavior;
  final List<WireImage>? images;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user_message',
    'id': id,
    'text': text,
    if (streamingBehavior != null)
      'streaming_behavior': streamingBehavior!.wireValue,
    if (images != null && images!.isNotEmpty)
      'images': images!.map((i) => i.toJson()).toList(),
  };
}
```

Mirrored shared types include `WireImage`, `ActionName`, `ThinkingLevel`, and `WireModel`.

## Target State

Generate the client half and shared value types beside the existing hand mirror, under a separate generated import used only by tests until the final swap:

```dart
// app/lib/protocol/generated/protocol.g.dart
sealed class ClientMessage {
  const ClientMessage();
  String get type;
  Map<String, dynamic> toJson();
}

final class UserMessage extends ClientMessage {
  const UserMessage({
    required this.id,
    required this.text,
    this.images,
    this.streamingBehavior,
  });

  @override
  String get type => 'user_message';
  final String id;
  final String text;
  final List<WireImage>? images;
  final UserMessageStreamingBehavior? streamingBehavior;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'text': text,
        if (images case final images? when images.isNotEmpty)
          'images': images.map((image) => image.toJson()).toList(),
        if (streamingBehavior case final behavior?)
          'streaming_behavior': behavior.wireValue,
      };
}
```

## Implementation Notes

- Generate exactly the current client wire shape: no new fields, no renamed fields, no changed omission rules.
- Preserve enum wire strings (`session_compact`, `xhigh`, `steer`) exactly.
- Generate equality/hashCode only for value types currently relying on equality (`WireImage`, `WireModel`) unless the schema-source feature standardizes broader equality.
- Keep generated classes in a separate library/import for this step so existing app code continues using the handwritten `protocol.dart` classes.
- Add tests that compare generated `toJson()` output to the existing handwritten `toJson()` output for every `ClientMessage` variant.

## Acceptance Criteria

- [ ] Generated client message classes exist for every current `ClientMessage` variant.
- [ ] Generated `toJson()` output matches the handwritten output for representative payloads, including optional image and streaming fields.
- [ ] Shared generated enums/value types preserve the current public names and wire strings.
- [ ] No production app imports are switched to generated code yet.

## Rollback

Remove the generated client output and tests. The handwritten protocol remains the runtime source.

## Implementation notes
- Files changed: `tools/protocol-codegen/bin/protocol-codegen.mjs`, `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`, `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_codegen/client_messages_codegen_test.dart`.
- Tests added: generator determinism check for the app client IR, generated client registry coverage, generated-vs-handwritten `toJson()` parity for every current client variant, shared value-type wire/equality checks, and representative generated `fromJson()` round trips.
- Discrepancies from design: generated client constructors include the now-current canonical `session_id` fields present in the hand mirror; no production import was switched.
- Adjacent issues parked: none.
- Verification: `HOME=/tmp/pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/protocol/generated/protocol.g.dart test/protocol_codegen/client_messages_codegen_test.dart` passed. Minimal codegen fixture regeneration still matches the checked-in compile fixture. `dart test test/protocol_codegen/client_messages_codegen_test.dart` could not run because pub network access failed with `403 Forbidden`; `flutter analyze` cannot start because `/opt/flutter/bin/cache` is read-only.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- `app/lib/protocol/generated/protocol.g.dart:1` / `tools/protocol-codegen/bin/protocol-codegen.mjs:436`: the committed generated file is stale relative to the current generator output. Regenerating from `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json` produces formatting/content differences, so `protocol.g.dart` is not the exact checked-in output of the tool and the determinism test fails.
- `app/test/protocol_codegen/client_messages_codegen_test.dart:34`: the test intended to prove the committed file matches regenerated output fails for the same mismatch, so the review-requested targeted test and generated-contract proof are not green.

**Verification run**:
- Acceptance criteria: generated client classes exist for every current `ClientMessage` variant — pass by inspection of `generatedClientMessageTypes` and generated classes.
- Acceptance criteria: generated `toJson()` matches handwritten output for representative payloads, including optional image/streaming fields — not fully verified because the targeted test file fails before green completion, though the parity subtest itself passed after the determinism failure.
- Acceptance criteria: shared generated enums/value types preserve current public names and wire strings — not fully verified because the targeted test file fails before green completion, though the shared-value subtest itself passed after the determinism failure.
- Acceptance criteria: no production app imports are switched to generated code yet — pass; grep found no `protocol/generated` imports under `app/lib`.
- `cd /home/agent/forks/remote_pi && node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out /tmp/<temp>/protocol.g.dart && cmp -s /tmp/<temp>/protocol.g.dart app/lib/protocol/generated/protocol.g.dart` — fail; regenerated output differs from committed `protocol.g.dart`.
- `cd /home/agent/forks/remote_pi/app && HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter analyze` — exit 1 with the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` only.
- `cd /home/agent/forks/remote_pi/app && HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter test test/protocol_codegen/client_messages_codegen_test.dart` — exit 1; `generated Dart client protocol generator output is deterministic for the app client IR` fails because regenerated output differs from `lib/protocol/generated/protocol.g.dart`.

## Implementation notes (rework 2026-06-30)
- Files changed: `app/lib/protocol/generated/protocol.g.dart` and this story file.
- Root cause: stale generated file. `tools/protocol-codegen/bin/protocol-codegen.mjs` was deterministic; the checked-in `protocol.g.dart` had been Dart-formatted/otherwise stale relative to raw generator output.
- Generator changes: none.
- Verification:
  - `cd /home/agent/projects/remote_pi && node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out /tmp/_check.g.dart && diff /tmp/_check.g.dart app/lib/protocol/generated/protocol.g.dart && echo 'regeneration diff: empty'` — passed; regeneration diff was empty.
  - `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && FLUTTER=/home/agent/projects/remote_pi/.tools/flutter/bin/flutter && "$FLUTTER" pub get` — passed.
  - `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && FLUTTER=/home/agent/projects/remote_pi/.tools/flutter/bin/flutter && "$FLUTTER" analyze` — exited 1 with only the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802`.
  - `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && FLUTTER=/home/agent/projects/remote_pi/.tools/flutter/bin/flutter && "$FLUTTER" test test/protocol_codegen/client_messages_codegen_test.dart` — passed; 5 tests passed.
