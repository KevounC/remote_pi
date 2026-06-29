---
id: epic-bold-canonical-session-wire-discriminator-step-2
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-canonical-session-wire-discriminator
depends_on: [epic-bold-canonical-session-wire-discriminator-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Stamp and validate session-scoped messages in the Pi-extension

## Current State
```ts
function _broadcastToActive(msg: ServerMessage): void {
  for (const ch of _activePeers.values()) ch.send(msg);
}

case "user_message":
  void _deliverUserMessage(msg, sender);
```

`session_sync` and `cancel` have special early paths before the normal `_disposed`/Pi-binding guard, and no client command checks a canonical session discriminator before mutating queued state or invoking Pi SDK calls.

## Target State
```ts
function withCurrentSession<T extends ServerMessage>(msg: T): T & { session_id: string } {
  return isSessionScopedServerType(msg.type)
    ? { ...msg, session_id: _currentRemoteSessionId(_lastEventCtx ?? _lastCtx) }
    : msg;
}

function _broadcastToActive(msg: ServerMessage): void {
  const stamped = withCurrentSession(msg);
  for (const ch of _activePeers.values()) ch.send(stamped);
}

const gate = validateClientSession(msg, _currentRemoteSessionId(_lastEventCtx ?? _lastCtx));
if (!gate.ok) {
  sender.send({
    type: "error",
    in_reply_to: msg.id,
    code: "session_mismatch",
    message: gate.message,
    session_id: gate.currentSessionId,
  });
  return;
}
```

## Implementation Notes
- Validate before `_deliverUserMessage`, queued-message mutation, approve/cancel, `session_sync`, and typed actions call Pi SDK handlers.
- `cancel` and `session_sync` still keep sender-specific routing, but only after session validation.
- Per-request replies (`session_history`, `cancelled`, `pong`, action replies, models list) must be stamped when session-scoped and sent only to the sender.
- Logs should include type, peer tail, room id, and short session-id tails only; never payload text/tool args/transcript.
- Existing `RemoteSessionIssuer` is the sole issuer; do not derive from cwd/room or relay state.

## Acceptance Criteria
- [ ] All session-scoped outbound server pushes and replies include the current `session_id`.
- [ ] Missing/mismatched session-scoped client commands return sender-only `error{code:"session_mismatch"}`.
- [ ] Rejected stale commands do not call `sendUserMessage`, `ctx.abort`, `ctx.newSession`, `ctx.compact`, model/thinking setters, or queued-message mutation.
- [ ] Tests prove session id is stable across relay reconnect and rotates after Pi SDK session replacement (building on identity-model tests).
- [ ] `corepack pnpm typecheck` and targeted extension router tests pass.

## Risk
High. Incorrect bootstrap/rotation could reject legitimate app commands. Keep validation at the extension boundary and test every command family before Pi SDK calls.

## Rollback
Remove the session gate and server stamping together. Reverting only validation while leaving required fields risks false confidence and legacy contamination.
