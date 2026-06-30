---
id: epic-bold-generated-protocol-dart-codegen-step-4
kind: story
stage: done
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-3]
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation notes

- Files changed: `app/lib/protocol/protocol.dart`, `app/lib/protocol/control_frames.dart`, `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_test.dart`, `tools/protocol-codegen/bin/protocol-codegen.mjs`, `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`.
- Retired the 1313-line handwritten inner protocol mirror: `protocol.dart` is now a small public facade exporting generated DTOs plus a temporary `control_frames.dart` island for relay presence/rooms frames that are deferred from the schema IR.
- Generator-first changes: the Dart emitter now generates session-scoped registries, `typeOfServerMessage`, `sessionIdOfServerMessage`, `SessionHistoryEvent.ts`, constructor defaults needed to preserve app/test call sites, and the `PiHarness.piCodingAgentUnknown` compatibility constant/equality. The app IR marks session-scoped variants and compatibility defaults explicitly; `protocol.g.dart` was regenerated only via `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out app/lib/protocol/generated/protocol.g.dart`.
- `codec.dart` required no code change: its stable `package:app/protocol/protocol.dart` import now resolves `ClientMessage`/`ServerMessage` to generated classes through the facade, preserving JSONL `encodeClient`/`decodeServer` behavior.
- Strengthened `app/test/protocol_test.dart`: fixture files are explicitly classified into server/client/relay-control allowlists; server fixtures must decode; client and control fixtures must throw `UnsupportedTypeException` when decoded as server messages.
- Regen-diff confirmation: `git diff --stat -- app/lib/protocol/generated/protocol.g.dart` reports `app/lib/protocol/generated/protocol.g.dart | 117 ++++++++++++++++++++++++-----` (`1 file changed, 97 insertions(+), 20 deletions(-)`).
- Determinism confirmation: generated twice with the command above; the two generated-file diffs were byte-identical and `sha256sum app/lib/protocol/generated/protocol.g.dart` remained `48445629e75c267189b3762fe838169da5757e013f36733f4bcd0fe73c00cc10`.
- Verification: `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/protocol_test.dart test/protocol/ test/protocol_codegen/` passed (`105` tests). Scoped analyze of `lib test/protocol_test.dart test/protocol test/protocol_codegen` reported only the known `axisAlignment` deprecation info. Full `flutter analyze` is blocked by concurrent/unowned test edits outside this story's file ownership (`test/data/sync/sync_service_test.dart`, `test/ui/chat/chat_viewmodel_test.dart`) plus the same known `axisAlignment` info.
- Discrepancies from design: relay control frames are deferred from the schema IR and remain in the temporary `control_frames.dart` island as allowed by the story.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane; generated-contract invariant verified)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified the generated-contract invariant.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 5e24b69` — generator (`tools/protocol-codegen/bin/protocol-codegen.mjs` + IR fixture), regenerated `protocol.g.dart`, `protocol.dart` (now facade), `control_frames.dart` (control-frame island), `protocol_test.dart` + story. No stray files.
- **REGEN + DETERMINISM CHECK**: regenerated `protocol.g.dart` from the committed generator/IR → diff vs committed = **EMPTY** (no hand-edits). Regenerated twice → two outputs identical (deterministic). Generated-contract invariant holds.
- `protocol.dart` is now a **20-line facade** (`export 'generated/protocol.g.dart'; export 'control_frames.dart';`) — down from 1313 lines. Hand mirror retired; control frames split to `control_frames.dart` as the documented hand-maintained island.
- `cd app && flutter test test/protocol_test.dart test/protocol_codegen/` (PUB_CACHE set) — 55/55 pass (server fixtures parse; client/control allowlist; generated union narrows + round-trips; exhaustive switch; determinism golden).
- `flutter analyze` — only the known-unrelated `axisAlignment` info (a transient `RuntimePresence`-undefined error appeared once from the parallel app-attribution-hydration agent's mid-edit state, then cleared on re-run).
- Acceptance criteria satisfied: existing `package:app/protocol/protocol.dart` imports still compile (facade re-exports); `encodeClient`/`decodeServer` preserve JSONL wire behavior; hand mirror reduced to facade + control-frame island; fixture tests fail if a schema server variant is missing from Dart generation.
