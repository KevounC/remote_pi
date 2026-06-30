---
id: epic-bold-generated-protocol-dart-codegen
kind: feature
stage: implementing
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-generated-protocol
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Generated protocol — Dart codegen target (riskiest — design first)

## Brief
The feasibility hinge for the whole generated-protocol epic. Produce clean
Dart sealed `ClientMessage`/`ServerMessage` unions with `fromJson` narrowing
and codec parity with the TS targets, generated from the canonical schema —
absorbing today's 1313-line hand mirror in `app/lib/protocol/protocol.dart`.

The risk: Dart sealed-class codegen is the weak link across the three
languages. If clean generated sealed classes (with exhaustive `switch` and
`fromJson`) aren't feasible, the foundation's shape changes — likely a
schema-driven *hand-maintained* single source with a generated contract test,
which is a weaker (timid) posture the greenfield stance rejects. This feature
must prove the bold posture is actually achievable in Dart before the rest of
the epic commits to it.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: riskiest child — the whole epic's shape depends on this landing
  cleanly. Design FIRST.

## Foundation references
- Evidence: `app/lib/protocol/protocol.dart:410-1180` (hand mirror to replace),
  `pi-extension/src/protocol/types.ts:1-213` (TS source of truth today),
  `pi-extension/src/protocol/codec.ts:3-18` (drifted registry).

## Design decisions

- **Autopilot judgment mode**: no strategic questions asked. This feature is the Dart-codegen feasibility hinge; the design resolves ambiguity by proving the Dart target independently of the sibling schema-source item's final schema language.
- **Misroute check**: keep this as `[refactor]`. The Dart target preserves the current wire shape and import surface while replacing the hand mirror with generated code. Future canonical `session_id` or protocol-shape changes belong to downstream generated-protocol/canonical-session items, not this refactor step.
- **Dispatch rationale**: direct-read only. The scope is bounded to the protocol mirrors, codec, fixture tests, and package version surface. No exploratory subagent was spawned; the subagent adapter is unavailable in this delegated context, and local reads provided concrete file/line evidence.
- **Codegen feasibility verdict**: **achievable**. Dart SDK `^3.11.5` (`app/pubspec.yaml:22`) supports sealed classes and exhaustive object-pattern switches. Clean generated sealed unions are viable when all generated subtypes live in the same generated library and the public `protocol.dart` file becomes a facade/export.
- **Codegen approach chosen**: a **custom deterministic schema/IR → Dart generator** invoked from the protocol-codegen tooling, not Dart annotation codegen.
  - `build_runner` / `source_gen`: good when Dart annotated source is the source of truth; awkward here because the protocol source is external and shared with TS/Rust.
  - `json_serializable`: useful for field serialization, but it does not by itself generate discriminated sealed unions or exhaustive `fromJson` narrowing.
  - Freezed / similar Dart union packages: can generate sealed-ish unions from Dart declarations, but would require a two-stage generator (schema → Dart declarations → package output) and adds package conventions that may fight exact wire names.
  - quicktype-style JSON Schema generators: useful for broad DTO output, but not a clean guarantee of modern Dart sealed unions, app-specific compatibility aliases, or fixture-derived registry parity.
  - Custom generator: emits exactly the app target (`sealed class ClientMessage` / `ServerMessage`, schema-derived variant registries for tests, compatibility aliases) and remains portable to patchbay because the input can be a normalized IR emitted by whatever schema language the sibling feature chooses.
- **Research note**: a live pub.dev API check was attempted, but DNS/network lookup failed in this environment. The decision intentionally depends on local pinned Dart capability and generator architecture rather than unpinned package API assumptions.
- **Cycle check**: read current frontmatter for this feature and searched active items for existing `parent`/`depends_on` references to `epic-bold-generated-protocol-dart-codegen`; none existed. New stories form a backward-only chain: step 1 → step 2 → step 3 → step 4 → step 5, so no dependency cycle is introduced.

## Code-smell scan findings

1. **God protocol file / mixed responsibilities** — `app/lib/protocol/protocol.dart` is 1313 lines and mixes relay control frames (`protocol.dart:11`), room state (`protocol.dart:222`), client messages (`protocol.dart:410`), server messages (`protocol.dart:753`), and nested history events (`protocol.dart:1087`). High value: generated output can split concerns while preserving the stable public import.
2. **Hand-mirrored variant sets** — TS declares `ClientMessage` and `ServerMessage` in `pi-extension/src/protocol/types.ts:9` and `types.ts:93`; Dart repeats them through manual `toJson` methods (`app/lib/protocol/protocol.dart:474`, `protocol.dart:702`, `protocol.dart:746`) and a manual server switch (`protocol.dart:756`). High value: one schema-derived generator removes the mirror.
3. **Known registry drift** — `pi-extension/src/protocol/codec.ts:3` defines a hand `SERVER_TYPES` set, while TS server union variants include `user_message` (`types.ts:128`), `compaction` (`types.ts:140`), and `models_list` (`types.ts:164`) that are not in that set. High value: Dart should not copy this pattern; generated registries must be test-only and schema-derived.
4. **Nested discriminant duplication** — `SessionHistoryEvent.fromJson` repeats a second handwritten type switch at `app/lib/protocol/protocol.dart:1091`. Medium/high value: generate nested unions from the same schema model so top-level and embedded events cannot diverge.
5. **Weak fixture proof** — `app/test/protocol_test.dart:20` accepts either successful decode or `UnsupportedTypeException` for every fixture line, and fixture docs claim each subproject should validate shared JSONL contracts (`.orchestration/contracts/protocol.md:230`, `protocol.md:232`). High value: generated Dart parity tests should distinguish server/client/control fixtures and fail on missing server variants.
6. **No project-specific refactor convention catalog** — `.agents/skills/refactor-conventions/` is absent, so no convention-driven step was added beyond the default refactor-design lenses.

## Refactor Overview

Dart sealed-class codegen is feasible and should be proven before the rest of the generated-protocol epic commits to broad schema/codegen migration. The safe path is a staged, behavior-preserving swap:

1. Build a minimal custom Dart generator spike from schema/IR to sealed unions.
2. Generate client messages and shared value types beside the existing hand mirror.
3. Generate server messages/history events and stronger decode narrowing beside the hand mirror.
4. Swap the app's stable `protocol.dart` import surface to generated code and retire the hand mirror.
5. Add parity checks/handoff notes so omitted schema variants fail tests instead of drifting.

The generated classes should initially preserve current compatibility behavior: `user_input`/`user_message` aliasing, legacy `PairOk` fallbacks, unknown `ByeReason`, and `UnsupportedTypeException` for unknown discriminants. Stricter validation or protocol-shape changes are intentionally deferred to behavior-changing generated-protocol/canonical-session work.

## Refactor Steps

### Step 1: Prove Dart sealed-class generation with a minimal schema IR

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contract / missing abstraction  
**Files**: `tools/protocol-codegen/`, `app/test/protocol_codegen/`, `app/pubspec.yaml` if a dev dependency is unavoidable  
**Story**: `epic-bold-generated-protocol-dart-codegen-step-1`

**Current State**:

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

**Target State**:

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
```

**Implementation Notes**:

- Implement a deterministic `--target dart` path in protocol-codegen tooling.
- Feed it a tiny local schema/IR fixture first; the production schema language remains owned by the sibling schema-source feature.
- Do not switch production app imports in this step.

**Acceptance Criteria**:

- [ ] Minimal IR generates sealed Dart variants, `fromJson`, and `toJson`.
- [ ] Golden/generator test proves fixture variants appear exactly once.
- [ ] A Dart compile test demonstrates exhaustive switching over generated sealed subtypes.
- [ ] Existing app tests remain unchanged apart from new passing generator tests.

**Rollback**: Delete the generator spike and spike tests; no runtime app code depends on it.

---

### Step 2: Generate Dart client messages and shared value types beside the hand mirror

**Priority**: High  
**Risk**: Medium  
**Source Lens**: duplicated variants / generated contract  
**Files**: `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_codegen/`, `app/lib/protocol/protocol.dart` as reference  
**Story**: `epic-bold-generated-protocol-dart-codegen-step-2`

**Current State**:

```dart
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

**Target State**:

```dart
sealed class ClientMessage {
  const ClientMessage();
  String get type;
  Map<String, dynamic> toJson();
}

final class UserMessage extends ClientMessage {
  const UserMessage({required this.id, required this.text, this.images, this.streamingBehavior});
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

**Implementation Notes**:

- Generate every current `ClientMessage` variant plus `WireImage`, `ActionName`, `ThinkingLevel`, `WireModel`, and streaming behavior.
- Keep generated code under a separate import for tests only until Step 4.
- Compare generated `toJson()` against current hand output for each client variant.

**Acceptance Criteria**:

- [ ] Generated client variants cover the current TS/Dart client union.
- [ ] Generated `toJson()` matches current hand output for representative payloads.
- [ ] Optional omission rules (`images`, `streaming_behavior`, `limit`) are preserved.
- [ ] No production imports are switched yet.

**Rollback**: Remove generated client output and tests; hand mirror remains runtime source.

---

### Step 3: Generate Dart server messages, history events, and decode narrowing

**Priority**: High  
**Risk**: High  
**Source Lens**: duplicated variants / codec drift / generated contract  
**Files**: `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_codegen/`, `.orchestration/contracts/fixtures/`  
**Story**: `epic-bold-generated-protocol-dart-codegen-step-3`

**Current State**:

```dart
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
```

**Target State**:

```dart
const Set<String> generatedServerMessageTypes = {
  'pair_ok', 'pair_error', 'user_input', 'user_message',
  'queued_message_state', 'agent_chunk', 'agent_done', 'agent_message',
  'compaction', 'tool_request', 'tool_result', 'error', 'cancelled',
  'pong', 'bye', 'session_history', 'action_ok', 'action_error', 'models_list',
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

**Implementation Notes**:

- Preserve current compatibility behavior for `user_input`/`user_message`, `PairOk` fallbacks, `ByeReason.unknown`, and unknown-type exceptions.
- Generate nested `SessionHistoryEvent` variants from the same source as top-level messages.
- Add tests that fail if schema server variants and generated Dart variants diverge.

**Acceptance Criteria**:

- [ ] Generated server union covers every current server variant including drift-prone `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.
- [ ] Generated history event union covers every current history event.
- [ ] Unknown discriminants still throw `UnsupportedTypeException`.
- [ ] Fixture tests fail on an omitted server variant.

**Rollback**: Remove generated server output and tests; hand parser remains runtime source.

---

### Step 4: Swap app codec/import surface to generated protocol and retire the hand mirror

**Priority**: High  
**Risk**: High  
**Source Lens**: god file / generated contract / dead-weight removal  
**Files**: `app/lib/protocol/protocol.dart`, `app/lib/protocol/codec.dart`, `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_test.dart`, `app/test/protocol/`  
**Story**: `epic-bold-generated-protocol-dart-codegen-step-4`

**Current State**:

```dart
import 'protocol.dart';

String encodeClient(ClientMessage m) => '${jsonEncode(m.toJson())}\n';

ServerMessage decodeServer(String line) =>
    ServerMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
```

**Target State**:

```dart
// app/lib/protocol/protocol.dart
// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
export 'generated/protocol.g.dart';
export 'generated/control_frames.g.dart'; // if the schema includes relay control frames
```

**Implementation Notes**:

- Keep `package:app/protocol/protocol.dart` as the stable import so app call sites avoid broad churn.
- If schema-source explicitly defers relay control frames, split existing control-frame code into `control_frames.dart` and export it as a temporary hand-maintained island; do not block the inner-message swap on that deferral.
- Delete the handwritten inner protocol DTOs once generated replacements pass tests.
- Run from `app/`: `flutter analyze` and `flutter test`.

**Acceptance Criteria**:

- [ ] Existing imports compile without broad call-site rewrites.
- [ ] `encodeClient` and `decodeServer` preserve JSONL behavior.
- [ ] Handwritten inner protocol mirror is removed or reduced to a facade/control-frame island with a recorded reason.
- [ ] Generated fixtures and app tests pass.

**Rollback**: Revert the swap commit to restore the pre-generated `protocol.dart` hand mirror.

---

### Step 5: Add generated-protocol parity checks and implementation handoff notes

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: contract-test gap / pattern drift  
**Files**: `app/test/protocol_codegen/`, `.orchestration/contracts/fixtures/`, this feature body  
**Story**: `epic-bold-generated-protocol-dart-codegen-step-5`

**Current State**:

```dart
test('all fixture lines parse or throw UnsupportedTypeException', () {
  // Any UnsupportedTypeException is accepted, so an omitted server variant
  // can look identical to an intentionally client-only fixture.
});
```

**Target State**:

```dart
const serverFixtureFiles = {
  'pair_ok.jsonl', 'pair_error.jsonl', 'agent_stream.jsonl', 'user_input.jsonl',
  'agent_message.jsonl', 'tool_request.jsonl', 'tool_result.jsonl',
  'session_history.jsonl', 'error.jsonl', 'cancelled.jsonl', 'pong.jsonl', 'bye.jsonl',
};

test('every server fixture decodes through generated ServerMessage', () {
  for (final file in serverFixtureFiles) {
    for (final line in fixtureLines(file)) {
      expect(decodeServer(line), isA<ServerMessage>());
    }
  }
});
```

**Implementation Notes**:

- Expose schema-derived/generated variant registries for tests only.
- Keep `.orchestration/contracts/fixtures/` until the whole generated-protocol epic retires it.
- Record final implementation feasibility and any deferred control-frame scope in this feature body.

**Acceptance Criteria**:

- [ ] Tests distinguish server, client, and relay-control fixtures instead of swallowing every unsupported type.
- [ ] A schema/generated registry parity check fails when a Dart server variant is omitted.
- [ ] No new hand-maintained protocol variant registry is introduced in Dart.
- [ ] The feature body records final feasibility/deferred-scope notes after implementation.

**Rollback**: Remove parity tests and handoff note changes; runtime generated protocol remains controlled by Step 4.

## Implementation Order

1. `epic-bold-generated-protocol-dart-codegen-step-1` — prove the Dart generator target with a minimal sealed-union spike.
2. `epic-bold-generated-protocol-dart-codegen-step-2` — generate client messages/value types beside the hand mirror.
3. `epic-bold-generated-protocol-dart-codegen-step-3` — generate server messages/history events beside the hand mirror.
4. `epic-bold-generated-protocol-dart-codegen-step-4` — swap the stable app protocol facade to generated code and remove the hand mirror.
5. `epic-bold-generated-protocol-dart-codegen-step-5` — harden generated parity tests and record final feasibility notes.

## Other agent review

- Invoked because: large/risky autopilot design hinge.
- Scope: skipped; no subagent/peer-review adapter is available in this delegated context, and design-time advisory review is non-blocking under autopilot.
- Accepted: direct-read evidence and local codegen feasibility judgment are sufficient to spawn implementation steps; final autopilot completion remains responsible for fresh-context review.

## Implementation handoff

- **Final Dart generator feasibility verdict**: **achievable and implemented**. The custom deterministic IR → Dart target emits clean generated sealed `ClientMessage`, `ServerMessage`, and `SessionHistoryEvent` unions with `fromJson` narrowing, `toJson`, generated test-visible registries, and exhaustive-switch support in tests. No fallback to a hand-maintained schema mirror was needed, so this feature remains `stage: implementing` until normal review advancement.
- **Generated parity guard**: `app/test/protocol_codegen/server_messages_codegen_test.dart` now compares `generatedServerMessageTypes` and `generatedSessionHistoryEventTypes` against the schema IR fixture, exercises every generated server dispatch case, and classifies the legacy cross-language JSONL fixtures as server, client-only, or relay-control. Omitting a Dart server variant from generated output now fails the schema/generated registry parity check and fixture coverage check instead of being swallowed as `UnsupportedTypeException`.
- **Deferred control-frame scope**: relay control, presence, and room frames remain intentionally outside the generated inner-protocol IR. They are still exported through the temporary hand-maintained `app/lib/protocol/control_frames.dart` island and covered as relay-control fixtures. Keep `.orchestration/contracts/fixtures/` as the legacy cross-language fixture suite until the broader generated-protocol epic retires it.
