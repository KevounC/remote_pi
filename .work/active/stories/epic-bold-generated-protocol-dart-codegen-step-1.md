---
id: epic-bold-generated-protocol-dart-codegen-step-1
kind: story
stage: done
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

## Implementation notes
- Files changed: `tools/protocol-codegen/bin/protocol-codegen.mjs`, `tools/protocol-codegen/fixtures/minimal_dart_ir.json`, `app/test/protocol_codegen/dart_codegen_test.dart`, `app/test/protocol_codegen/generated/minimal_protocol.g.dart`, `app/test/protocol_codegen/goldens/minimal_protocol.g.dart.golden`.
- Tests added: `app/test/protocol_codegen/dart_codegen_test.dart` covers deterministic generator output, golden parity, fixture variant dispatch/type getter coverage, fromJson/toJson behavior, unknown type failure, and an exhaustive Dart switch over the generated sealed union.
- Discrepancies from design: none. No `app/pubspec.yaml` dependency was needed; a small custom Node generator consumes the minimal normalized IR fixture directly and writes deterministic Dart.
- Verification: targeted codegen test passed with a writable Flutter copy (`HOME=/tmp /tmp/flutter-writable/bin/flutter test test/protocol_codegen/dart_codegen_test.dart`); targeted analyzer passed via direct Dart SDK (`HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart analyze test/protocol_codegen/dart_codegen_test.dart test/protocol_codegen/generated/minimal_protocol.g.dart`); generator/golden/compile smoke passed (`node ... && cmp ... && dart /tmp/remote_pi_dart_codegen_compile_check.dart`). Full `flutter analyze` reached one pre-existing unrelated deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` (also recorded in archived work); full `flutter test` still fails in existing app action/sync/chat tests around session identity availability, with no app runtime files touched by this story.
- Adjacent issues parked: none; full-suite failures are outside this generator spike and were not introduced by the changed files.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- The generator does not consume the schema-source Step 5 handoff IR/catalog. `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store list-types` emits the canonical 58-entry generator handoff catalog, including the drift-prone app-pi server types, but `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema /tmp/remote_pi_protocol_catalog.json --out /tmp/remote_pi_from_catalog.g.dart` fails with `schema.unions must be an array`. The current spike proves Dart emission from `tools/protocol-codegen/fixtures/minimal_dart_ir.json`, but not the requested schema-source/list-types handoff path.

**Acceptance criteria status**:
- Minimal IR generates sealed Dart variants, `fromJson`, and `toJson`: met.
- Golden/generator test proves fixture variants appear exactly once: met.
- Dart compile/exhaustive switch smoke: met.
- Existing app tests unchanged apart from new generator tests: targeted new test passes; full app suite remains red on pre-existing action/sync/chat/session-identity failures and `flutter analyze` remains red on the pre-existing `axisAlignment` deprecation info.
- Review-added handoff check: not met; wire this spike to the schema-source Step 5 `list-types` output or add a documented normalization adapter from that catalog/schema refs to the Dart generator IR.

**Verification run**:
- `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/minimal_dart_ir.json --out /tmp/remote_pi_minimal_protocol.g.dart && cmp /tmp/remote_pi_minimal_protocol.g.dart app/test/protocol_codegen/goldens/minimal_protocol.g.dart.golden` — pass.
- `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store list-types` — pass; emitted 58 catalog entries and includes `user_message`, `compaction`, `action_ok`, `action_error`, `models_list`.
- `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema /tmp/remote_pi_protocol_catalog.json --out /tmp/remote_pi_from_catalog.g.dart && HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart analyze /tmp/remote_pi_from_catalog.g.dart` — pass; generator now consumes the schema-source Step 5 list-types catalog and emits valid Dart.
- `HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart test test/protocol_codegen/dart_codegen_test.dart` — blocked by environment/network (`Proxy failed to establish tunnel (403 Forbidden)` while resolving pub packages); no test-green claim for this command in this re-fix.
- Prior review-run context retained: targeted codegen test passed before the bounce with a writable Flutter copy; full app analyze/test had unrelated pre-existing failures noted above.

## Re-fix implementation notes
- Files changed: `tools/protocol-codegen/bin/protocol-codegen.mjs`.
- Tests added: none; added a normalization adapter from the schema-source `list-types` handoff catalog to the existing Dart generator IR.
- Discrepancies from design: the catalog adapter emits variant shells from the handoff catalog for this spike rather than fully resolving every JSON Schema field. This directly fixes the bounced handoff-path proof while leaving full field generation to later Dart-codegen steps.
- Adjacent issues parked: none.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane re-review after prior bounce. Inspected implementation commit `76ff5ff`; the Dart target now normalizes the schema-source `list-types` catalog (not only `minimal_dart_ir.json`) into generator unions. Verified `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store list-types` emitted the 58-entry catalog, `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema /tmp/remote_pi_protocol_catalog.json --out /tmp/remote_pi_from_catalog.g.dart` succeeded, and `HOME=/tmp/pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze /tmp/remote_pi_from_catalog.g.dart` passed. Targeted `HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter test test/protocol_codegen/dart_codegen_test.dart` passed. Full `flutter analyze` is still red on the pre-existing `axisAlignment` deprecation info in `lib/ui/chat/widgets/input_bar.dart:802`; full `flutter test` is still red on unrelated action/sync/chat session-identity failures, matching the implementation notes.
