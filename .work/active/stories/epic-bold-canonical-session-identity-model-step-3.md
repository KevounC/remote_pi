---
id: epic-bold-canonical-session-identity-model-step-3
kind: story
stage: implementing
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: [epic-bold-canonical-session-identity-model-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Enforce endpoint validation fail-closed

## Current State
```dart
// app/lib/data/sync/sync_service.dart
case SessionHistory():
  _applyHistory(msg); // replaces active message box for the current (epk, room)
```

```ts
// pi-extension/src/index.ts
case "user_message":
  void _deliverUserMessage(msg, sender);
```

The app accepts any decoded server message that survived room demux; the extension accepts any known client message from an attached owner. Neither endpoint checks a canonical session discriminator.

## Target State
```dart
// app/lib/data/sync/session_gate.dart
bool accepts(ServerMessage msg, RemoteSessionRef active) {
  if (!isSessionScopedServerType(msg.type)) return true;
  final got = msg.sessionId;
  if (got == null || got != active.sessionId) {
    debugPrint('[session-gate] drop type=${msg.type} room=${active.roomId} reason=session-mismatch');
    return false;
  }
  return true;
}
```

```ts
// pi-extension/src/session/session_gate.ts
export function validateClientSession(msg: ClientMessage, current: RemoteSession): SessionGateResult {
  if (!isSessionScopedClientType(msg.type)) return { ok: true };
  return msg.session_id === current.sessionId
    ? { ok: true }
    : { ok: false, code: "session_mismatch" };
}
```

App-side fail-closed means `SyncService` drops missing/mismatched session-scoped server messages before mutating streaming state, working state, queued text, Hive boxes, or session index. Extension-side fail-closed means stale app commands do not reach Pi SDK actions; correlated commands receive an `error{code:'session_mismatch', in_reply_to:<id>, session_id:<current>}` and a sanitized log.

## Implementation Notes
- Capture the app's active `RemoteSessionRef { epk, roomId, sessionId }` from `pair_ok`/room metadata before any `session_sync` response can apply.
- In `WsTransport`, remove the legacy "no room routes unconditionally" loophole for fork-private clean-room mode; no-room outer frames are dropped unless explicitly running a temporary compatibility test fixture.
- Validate before `_applyHistory`, `_setWorking`, `_emitStreaming`, and `_upsert` paths.
- On extension validation failures, do not broadcast the error to all owners; reply only to the sender channel.
- Logs must not include payload text, tool args, or transcript contents. Use message type, peer tail, room id, and truncated session-id tails only.

## Acceptance Criteria
- [ ] A foreign `session_history` cannot replace the active message box.
- [ ] Foreign `agent_chunk`, `agent_done`, `tool_request`, and `tool_result` do not affect streaming, working, or persisted rows.
- [ ] Missing `session_id` on session-scoped server pushes is dropped fail-closed.
- [ ] Stale app commands with wrong/missing `session_id` do not call Pi SDK methods and return `session_mismatch` to the sender.
- [ ] Tests cover the contamination vector: active room receives foreign `session_history` and state remains unchanged.
- [ ] `flutter test` targeted sync tests and `corepack pnpm test` targeted extension router tests pass.

## Risk
High. A wrong expected-session bootstrap could drop legitimate traffic and make the app look disconnected. This is the architectural hinge and must have deterministic tests.

## Rollback
Disable the session gate behind one internal constant, then revert the validation module and tests. Roll back after Step 4/5 consumers to avoid leaving required fields unused.
