---
id: epic-bold-generated-protocol-dart-codegen-step-1
kind: story
stage: implementing
parent: epic-bold-generated-protocol-dart-codegen
depends_on: []
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Prove Dart sealed-class generation with a minimal schema IR

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contract / missing abstraction  
**Files**: `tools/protocol-codegen/`, `app/test/protocol_codegen/`, `app/pubspec.yaml` (only if a dev dependency is unavoidable)

## Current State

The app hand-authors protocol variants in `app/lib/protocol/protocol.dart`:

```dart
sealed class ClientMessage {
  Map<String, dynamic> toJson();
}

sealed class ServerMessage {
  const ServerMessage();

  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'agent_chunk' => AgentChunk.fromJson(json),
      // ... every variant repeated by hand ...
      _ => throw UnsupportedTypeException(type ?? ''),
    };
  }
}
```

Dart SDK is `^3.11.5`, so generated code may rely on modern sealed classes and exhaustive object-pattern switches. No build-time generator dependency is currently pinned in `app/pubspec.yaml`.

## Target State

Add a deterministic schema-to-Dart generator target, proven against a tiny fixture IR before touching the production hand mirror. The spike should emit one self-contained Dart library with sealed unions, `fromJson` narrowing, `toJson`, and an exhaustiveness smoke test:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
sealed class ServerMessage {
  const ServerMessage();
  String get type;

  static ServerMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'pong' => Pong.fromJson(json),
      'error' => ErrorMessage.fromJson(json),
      final unknown => throw UnsupportedTypeException(unknown ?? ''),
    };
  }

  Map<String, dynamic> toJson();
}

final class Pong extends ServerMessage {
  const Pong({required this.inReplyTo});
  final String inReplyTo;
  @override
  String get type => 'pong';
  factory Pong.fromJson(Map<String, dynamic> json) =>
      Pong(inReplyTo: json['in_reply_to'] as String);
  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'in_reply_to': inReplyTo,
      };
}
```

Generator command shape:

```bash
node tools/protocol-codegen/bin/protocol-codegen.mjs \
  --target dart \
  --schema <canonical-schema-or-normalized-ir.json> \
  --out app/lib/protocol/generated/protocol.g.dart
```

The generator may consume the canonical schema directly or a normalized IR emitted by the sibling schema-source feature; do not lock this story to a schema language.

## Implementation Notes

- Prefer a small custom generator over `build_runner`/`source_gen`/Freezed/quicktype for the first target. Rationale: the source is an external protocol schema, not Dart annotations; direct emission avoids two-stage generation, preserves exact wire names, and keeps the path portable to patchbay.
- Keep the generated output deterministic: stable field ordering, stable imports, trailing newline, and a golden test for the spike output.
- Do not modify existing app imports or runtime protocol behavior in this step.
- If a Dart package is added, keep it dev-only and justify it in this story's implementation notes.

## Acceptance Criteria

- [ ] A minimal schema/IR fixture can generate a Dart file containing a sealed `ServerMessage` union, variant classes, `fromJson`, and `toJson`.
- [ ] A generator test or golden test proves the output contains every fixture variant exactly once.
- [ ] A Dart test compiles an exhaustive `switch` over the generated sealed variants.
- [ ] Existing `flutter analyze` / `flutter test` behavior is unchanged except for the new passing generator tests.

## Rollback

Delete `tools/protocol-codegen/` and the spike tests. No app runtime code should depend on this step yet.
