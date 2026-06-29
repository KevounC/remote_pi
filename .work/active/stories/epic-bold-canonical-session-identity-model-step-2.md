---
id: epic-bold-canonical-session-identity-model-step-2
kind: story
stage: review
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: [epic-bold-canonical-session-identity-model-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Centralize session-scoped wire field semantics

## Current State
```ts
// pi-extension/src/protocol/types.ts
| { type: "agent_chunk"; in_reply_to: string; delta: string }
| { type: "agent_done"; in_reply_to: string; usage?: Usage }
| { type: "tool_request"; tool_call_id: string; tool: string; args: Record<string, unknown> }
| { type: "tool_result"; tool_call_id: string; result?: unknown; error?: string }
| { type: "session_history"; in_reply_to: string; session_started_at: number; events: SessionHistoryEvent[]; ... }
```

```dart
// app/lib/protocol/protocol.dart
// 1 pairing = 1 session: no session_id on any message.
```

The set of session-scoped messages is implicit and duplicated. The handwritten mirrors do not say which messages must carry `session_id`.

## Target State
```ts
// pi-extension/src/protocol/session_scope.ts
export const SESSION_SCOPED_SERVER_TYPES = [
  'user_input', 'user_message', 'queued_message_state',
  'agent_chunk', 'agent_done', 'agent_message', 'compaction',
  'tool_request', 'tool_result', 'error', 'cancelled', 'session_history',
] as const;

export const SESSION_SCOPED_CLIENT_TYPES = [
  'user_message', 'queued_message_set', 'queued_message_clear',
  'approve_tool', 'cancel', 'session_sync',
  'session_new', 'session_compact', 'model_set', 'thinking_set', 'list_models',
] as const;

export type SessionScopedServerType = typeof SESSION_SCOPED_SERVER_TYPES[number];
export type SessionScopedClientType = typeof SESSION_SCOPED_CLIENT_TYPES[number];
```

Every session-scoped message carries required `session_id: RemoteSessionId`. `pair_ok` also carries `session_id` to bootstrap the app's expected session. Non-session messages (`pair_request`, `pair_error`, `pong`, `bye`, relay control frames, presence/rooms snapshots) do not validate by session.

## Implementation Notes
- Make the session-scoped type registry the source of truth for validators and tests until `epic-bold-generated-protocol` replaces handwritten mirrors with generated output.
- Update TS and Dart handwritten mirrors in the same commit so the current app/extension continue to compile before generated schema lands.
- Add `session_id` to `SessionHistoryEvent` only if an embedded event can cross session boundaries independently. The default design keeps `session_id` on the enclosing `session_history`, not duplicated on every event.
- `session_started_at` remains in `session_history` as ordering metadata/high-water protection, not as identity.
- Error code `session_mismatch` is added to known error codes but receivers still tolerate unknown error strings.

## Acceptance Criteria
- [x] TS and Dart have a single registry/list of session-scoped message types.
- [x] All session-scoped `ClientMessage` and `ServerMessage` variants carry required `session_id`.
- [x] `pair_ok` carries `session_id`; `pair_request` does not.
- [x] Tests fail if a new session-scoped type is added without the field/validator.
- [x] Generated-protocol sibling can lift the registry/field semantics without changing the chosen meaning.
- [x] `corepack pnpm typecheck` and `flutter analyze` pass or are reported with environment blockers.

## Implementation Notes
- Added `pi-extension/src/protocol/session_scope.ts` as the temporary handwritten source of truth for session-scoped client/server wire type sets until generated protocol output replaces the mirrors.
- Threaded `session_id` through TS protocol types, outgoing Pi session events, app protocol DTOs, app command sends, and app incoming session filtering. `pair_ok` now bootstraps the app-side active room session id; `pair_request`, pings, pairing errors, bye, and action replies remain non-session-scoped.
- Kept the design migration-friendly: the registry shape matches the intended generated schema semantics and does not introduce patchbay-specific routing assumptions.

## Verification
- `cd pi-extension && corepack pnpm typecheck` passed.
- `cd pi-extension && corepack pnpm vitest run src/protocol/codec.test.ts src/protocol/session_scope.test.ts src/session/remote_session.test.ts` passed.
- `cd pi-extension && corepack pnpm test` was attempted; it still fails in this sandbox on pre-existing/local-environment UDS lock and leader-election tests (`listen EPERM`, lock acquisition failures). A codec fixture failure exposed by this story was fixed and covered by the targeted protocol run above.
- `cd app && HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart analyze` completed with only the existing `axisAlignment` deprecation info in `lib/ui/chat/widgets/input_bar.dart`.
- `cd app && HOME=/tmp /opt/flutter/bin/flutter test` could not run because the Flutter install attempts to write `/opt/flutter/bin/cache/engine.*` on a read-only filesystem.
- `cd app && HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart test --no-pub ...` could not run because build hooks attempted to reach `pub.dev` and the proxy returned 403.

## Risk
Medium. This is a clean-room fork-private breaking wire change. Existing legacy no-session peers will fail closed once validation lands.

## Rollback
Revert the registry and field additions before reverting validation steps. Because this story only centralizes field semantics, rollback returns the wire mirrors to the current no-`session_id` shape.
