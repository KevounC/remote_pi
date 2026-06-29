---
id: epic-bold-generated-protocol-dart-codegen-step-4
kind: story
stage: implementing
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-3]
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Swap app codec/import surface to generated protocol and retire the hand mirror

**Priority**: High  
**Risk**: High  
**Source Lens**: god file / generated contract / dead-weight removal  
**Files**: `app/lib/protocol/protocol.dart`, `app/lib/protocol/codec.dart`, `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_test.dart`, `app/test/protocol/`

## Current State

`app/lib/protocol/protocol.dart` is a 1313-line hand mirror that mixes relay control frames, rooms, client messages, server messages, history events, value DTOs, and compatibility comments. `app/lib/protocol/codec.dart` imports that file and delegates decoding:

```dart
import 'dart:convert';

import 'protocol.dart';

String encodeClient(ClientMessage m) => '${jsonEncode(m.toJson())}\n';

ServerMessage decodeServer(String line) =>
    ServerMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
```

## Target State

Keep `package:app/protocol/protocol.dart` as the stable public import, but make it a small generated-protocol facade. Existing app call sites should not need broad import churn:

```dart
// app/lib/protocol/protocol.dart
// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
export 'generated/protocol.g.dart';
export 'generated/control_frames.g.dart'; // if the canonical schema includes relay control frames
```

`codec.dart` continues to expose the same functions but now uses the generated classes through the facade:

```dart
String encodeClient(ClientMessage message) => '${jsonEncode(message.toJson())}\n';

ServerMessage decodeServer(String line) =>
    ServerMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
```

If the sibling schema-source feature explicitly defers relay control frames, split the existing control-frame code into `app/lib/protocol/control_frames.dart` and export it from `protocol.dart` as a temporary hand-maintained island with a TODO in the story implementation notes; do not let that defer the inner `ClientMessage`/`ServerMessage` swap.

## Implementation Notes

- Run a mechanical import-preserving swap: keep class names and constructor signatures stable wherever possible.
- Delete the handwritten inner protocol DTOs after generated replacements pass tests; avoid leaving two sources of truth.
- Strengthen `app/test/protocol_test.dart` so server fixtures must parse and client/control fixtures are named in an allowlist. The current catch-all `UnsupportedTypeException` allowance should be removed or narrowed.
- Run from `app/`: `flutter analyze` and `flutter test`.
- Run the generator determinism check (generate twice and assert no diff) before committing implementation.

## Acceptance Criteria

- [ ] Existing app imports of `package:app/protocol/protocol.dart` continue to compile.
- [ ] `encodeClient` and `decodeServer` preserve JSONL wire behavior.
- [ ] The handwritten inner protocol mirror is removed or reduced to a facade/control-frame island with a recorded reason.
- [ ] Fixture tests fail if a schema server variant is missing from Dart generation.
- [ ] `flutter analyze` and `flutter test` pass from `app/`.

## Rollback

Revert `protocol.dart`, `codec.dart`, generated outputs, and protocol tests to the pre-swap hand mirror. Since Steps 1-3 generated beside the hand code, rollback should be a single commit revert of this swap step.
