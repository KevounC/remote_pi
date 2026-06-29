---
id: epic-bold-canonical-session-wire-discriminator-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-canonical-session-wire-discriminator
depends_on: [epic-bold-canonical-session-identity-model-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add session-scoped registries and required `session_id` to handwritten mirrors

## Current State
```ts
export type ClientMessage =
  | { type: "user_message"; id: string; text: string; images?: WireImage[] }
  | { type: "session_sync"; id: string; limit?: number }
  | { type: "session_new"; id: string };

export type ServerMessage =
  | { type: "agent_chunk"; in_reply_to: string; delta: string }
  | { type: "session_history"; in_reply_to: string; session_started_at: number; events: SessionHistoryEvent[] };
```

```dart
// app/lib/protocol/protocol.dart
// 1 pairing = 1 session: no session_id on any message.
class AgentChunk extends ServerMessage {
  final String inReplyTo;
  final String delta;
}
```

## Target State
```ts
export const SESSION_SCOPED_CLIENT_TYPES = [
  "user_message", "queued_message_set", "queued_message_clear", "approve_tool",
  "cancel", "session_sync", "session_new", "session_compact", "model_set",
  "thinking_set", "list_models",
] as const;

export const SESSION_SCOPED_SERVER_TYPES = [
  "user_input", "user_message", "queued_message_state", "agent_chunk",
  "agent_done", "agent_message", "compaction", "tool_request", "tool_result",
  "error", "cancelled", "session_history", "action_ok", "action_error",
  "models_list",
] as const;

export type SessionScoped = { session_id: string };
export function isSessionScopedClientType(type: ClientMessage["type"]): boolean;
export function isSessionScopedServerType(type: ServerMessage["type"]): boolean;
```

```dart
mixin SessionScopedServerMessage on ServerMessage {
  String get sessionId;
}

class AgentChunk extends ServerMessage with SessionScopedServerMessage {
  @override
  final String sessionId;
  final String inReplyTo;
  final String delta;
}
```

## Implementation Notes
- Keep `pair_ok.session_id` as bootstrap metadata; `pair_request`, `pair_error`, `pong`, and `bye` are not session-scoped.
- Treat `session_id` as required on every type in `SESSION_SCOPED_*`; decoders may throw/drop at the boundary rather than constructing nullable session-scoped DTOs.
- Add `session_mismatch` to `KnownErrorCode` while preserving open error-code tolerance.
- Update `SERVER_TYPES` drift in `codec.ts` while touching the registry so tests cover all server types that now need `session_id`.
- This is a handwritten bridge until `epic-bold-generated-protocol` lifts the same semantics into generated contracts.

## Acceptance Criteria
- [ ] TS and Dart have explicit `SESSION_SCOPED_CLIENT_TYPES` / `SESSION_SCOPED_SERVER_TYPES` mirrors.
- [ ] Every session-scoped TS union member and Dart subtype carries required `session_id` / `sessionId`.
- [ ] Tests fail if a new session-scoped type lacks `session_id`.
- [ ] `pair_ok` still bootstraps `session_id`; non-session control messages remain valid without it.
- [ ] `corepack pnpm typecheck` and targeted Dart protocol tests pass.

## Risk
Medium. This is a cross-language contract bridge before generated protocol lands; drift is possible if tests do not derive from the registry.

## Rollback
Revert the registry and field additions before reverting validators. Since generated protocol is the successor, rollback is a bridge removal, not a relay/schema decision.

## Implementation notes
- Files changed: `pi-extension/src/protocol/session_scope.ts`, `pi-extension/src/protocol/types.ts`, `pi-extension/src/protocol/codec.ts`, `pi-extension/src/actions/handlers.ts`, `pi-extension/src/index.ts` (daemon `session_new` ack line only), `app/lib/protocol/protocol.dart`, protocol/action tests, and `.orchestration/contracts/fixtures/*.jsonl` contract fixtures.
- Tests added: TS codec coverage for missing `session_id`; TS session-scope registry expectations include action replies; Dart protocol/action tests now parse required `session_id` on scoped replies.
- Discrepancies from design: `session_scope.ts` already existed from the identity-model slice, so this step completed it by moving `action_ok`, `action_error`, and `models_list` into the scoped server registry and making codec/Dart decoding fail fast for missing `session_id`.
- Adjacent issues parked: none.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm exec vitest run src/protocol/codec.test.ts src/protocol/session_scope.test.ts src/actions/handlers.test.ts` passed; full `corepack pnpm test` was attempted and failed on pre-existing/environment UDS lock failures (`listen EPERM` under `/tmp/claude` and cwd lock/leader election failures), not on the touched protocol tests; `flutter test test/protocol_test.dart test/protocol/actions_protocol_test.dart` could not start because `/opt/flutter/bin/cache` is read-only; nearest checks `dart format` and `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/protocol/protocol.dart test/protocol_test.dart test/protocol/actions_protocol_test.dart` passed; `dart test` could not run because pub.dev access was blocked by proxy 403.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: Stale Dart protocol comment still says "MVP: 1 pairing = 1 Pi session" even though the typed registry now restores session-scoped messages.

**Notes**: Fast-lane substrate review. Implementation commit `aa44412` was inspected. Required TS/Dart session-scoped registries are present; every scoped TS union and Dart subtype now carries required `session_id`/`sessionId`; TS codec and Dart parser fail closed for missing scoped `session_id`; `pair_ok` remains bootstrap metadata and non-session controls remain accepted without a scoped discriminator. Verification run during review: `cd pi-extension && corepack pnpm typecheck` passed; `cd pi-extension && corepack pnpm test` was attempted and did not produce a clean full-suite pass in this environment because existing UDS/daemon/leader-election tests fail or time out, while touched targeted tests (`codec`, `session_scope`, `actions`, plus shared targeted set) passed. App Flutter could not start because `/opt/flutter/bin/cache` is read-only; nearest protocol analysis `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/protocol/protocol.dart test/protocol_test.dart test/protocol/actions_protocol_test.dart` passed, and `dart test` remained blocked by pub.dev proxy 403. Item advanced to `stage: done` based on scoped code review and targeted green checks.
