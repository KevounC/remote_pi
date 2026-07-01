---
id: epic-bold-canonical-session-wire-discriminator
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app, relay, security, bug]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-identity-model, epic-bold-generated-protocol]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — wire discriminator (absorbs feature-session-isolation)

## Brief
The migrated session-isolation bugfix: required canonical `session_id` on every
chat-bearing ServerMessage (`user_message`, `agent_chunk`, `agent_done`,
`session_history`, `queued_message_state`, tool surfaces), fail-closed
validation at every receiver. This is the **absorption** of
`feature-session-isolation-wire-discriminator` — that feature's brief, root
cause, and diagnosis become this feature's bugfix slice. It lands as a child of
the canonical-session epic rather than a parallel track, and it depends on the
generated-protocol epic (the `session_id` field is generated, not hand-added).

Strategic decisions inherited from the absorbed feature: canonical `session_id`
(not room reuse); required + fail-closed (clean-room posture); absorb
`relay-cross-pc-room-targeting` as the relay half.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: the bugfix slice of the reconception — first user-visible win,
  lands before the full identity model reshapes every consumer.

## Foundation references
- Absorbed: `feature-session-isolation-wire-discriminator` (brief, root cause,
  reproduction) and `relay-cross-pc-room-targeting`.
- Evidence: `pi-extension/src/protocol/types.ts:93-154` (no discriminator),
  `app/lib/data/sync/sync_service.dart:671-760` (`_applyHistory` replaces box),
  `app/lib/data/transport/ws_transport.dart:63-103` (legacy fail-open),
  `relay/src/handlers/pi_forward.rs:128-173` + `relay/src/peers/registry.rs:369-384`
  (cross-PC fanout).

<!-- /agile-workflow:refactor-design fills in the field shape, validation sites,
and the cross-language contract test. -->

## Design decisions
- **Per-feature route despite behavior change**: this slice intentionally stays in the bold `[refactor]` lane even though it changes the black-box wire contract. The operator/autopilot explicitly scoped it as the fork-private bugfix slice for a designed-then-dropped invariant. Clean-room behavior is fail-closed rather than legacy-compatible because preserving no-session peers would preserve the contamination class.
- **Bridge before generated protocol**: `epic-bold-generated-protocol` remains the long-term owner of the schema. This feature adds the `session_id` field and `SESSION_SCOPED_*` registries to the handwritten TS/Dart mirrors as a temporary bridge, then generated code can lift the same semantics without changing relay posture.
- **Endpoint-owned discriminator**: Pi-extension stamps the opaque `session_id` resolved by `RemoteSessionIssuer` onto every session-scoped server push. The app compares equality only. The relay never parses or routes by `session_id`.
- **Fail-closed mutation boundary**: app validation happens before `SyncService` mutates streaming buffers, working/queued state, Hive message boxes, or session-index records. Foreign or missing `session_id` converges to dropped, not overwrite.
- **Fail-closed command boundary**: Pi-extension rejects session-scoped app commands with missing/mismatched `session_id` before Pi SDK calls. Correlated requests get sender-only `error{code:"session_mismatch"}`; no broadcast and no payload logging.
- **Relay targeting minimum**: this slice fixes the live `forward_to_peer` fanout vector by adding explicit room targeting for cross-PC delivery while keeping the relay session-blind. The later relay-opaque-targeting sibling can reshape naming/API further, but must not reintroduce peer-wide fanout.
- **Patchbay posture**: the only new durable identity is an opaque discriminator emitted by the endpoint. No cwd hash, room naming rule, relay DB key, or fork-specific path becomes the session identity, so patchbay can replace the issuer later.

## Refactor Overview
The contamination path is currently fail-open: the relay can fan out cross-PC frames to every live room for a peer, `WsTransport` accepts legacy no-room app frames unconditionally, and `SyncService._applyHistory` treats any decoded `session_history` as authoritative for the active `(epk, room)` box. A delayed or foreign history therefore replaces the viewed session.

The target architecture makes the bug impossible by construction. A single session-scoped message registry defines which client and server messages require `session_id`; the Pi-extension stamps and validates that discriminator at its boundary; the app decodes it into typed messages and drops mismatches before mutation; relay cross-PC routing targets `(to_pc, to_room)` while carrying opaque payloads unchanged.

Scope probe: direct-read only. The target files were bounded and explicitly named (`pi-extension/src/protocol/types.ts`, `pi-extension/src/index.ts`, `app/lib/protocol/protocol.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/data/transport/ws_transport.dart`, `relay/src/handlers/pi_forward.rs`, `relay/src/peers/registry.rs`), so no exploratory sub-agent fanout was used.

Cycle check: `.work/bin/work-view --blocking` is unavailable in this checkout (`No such file or directory`). Manual dependency check found no cycle: step 1 depends on `epic-bold-canonical-session-identity-model-step-1`; steps 2-4 form a linear chain from step 1; the identity-model stories do not depend on this feature or its children.

## Refactor Steps

### Step 1: Add session-scoped registries and required `session_id` to handwritten mirrors
**Priority**: High
**Risk**: Medium
**Source Lens**: single-source-of-truth / generated-contract preparation
**Files**: `pi-extension/src/protocol/types.ts`, `pi-extension/src/protocol/codec.ts`, `app/lib/protocol/protocol.dart`, `pi-extension/src/protocol/codec.test.ts`, app protocol tests
**Story**: `epic-bold-canonical-session-wire-discriminator-step-1`

**Current State**:
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

**Target State**:
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

**Implementation Notes**:
- Keep `pair_ok.session_id` as bootstrap metadata; `pair_request`, `pair_error`, `pong`, and `bye` are not session-scoped.
- Treat `session_id` as required on every type in `SESSION_SCOPED_*`; decoders may still throw/drop at the boundary rather than constructing nullable session-scoped DTOs.
- Add `session_mismatch` to `KnownErrorCode` while preserving open error-code tolerance.
- Update `SERVER_TYPES` drift in `codec.ts` while touching the registry so tests cover all server types that now need `session_id`.

**Acceptance Criteria**:
- [ ] TS and Dart have explicit `SESSION_SCOPED_CLIENT_TYPES` / `SESSION_SCOPED_SERVER_TYPES` mirrors.
- [ ] Every session-scoped TS union member and Dart subtype carries required `session_id` / `sessionId`.
- [ ] Tests fail if a new session-scoped type lacks `session_id`.
- [ ] `pair_ok` still bootstraps `session_id`; non-session control messages remain valid without it.
- [ ] `corepack pnpm typecheck` and targeted Dart protocol tests pass.

**Rollback**: Revert the registry and field additions before reverting validators. Since generated protocol is the successor, rollback is a bridge removal, not a relay/schema decision.

---

### Step 2: Stamp and validate session-scoped messages in the Pi-extension
**Priority**: High
**Risk**: High
**Source Lens**: fail-fast boundary / lifecycle ownership
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/session_gate.ts`, `pi-extension/src/session/remote_session.ts`, `pi-extension/src/protocol/types.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-canonical-session-wire-discriminator-step-2`

**Current State**:
```ts
function _broadcastToActive(msg: ServerMessage): void {
  for (const ch of _activePeers.values()) ch.send(msg);
}

case "user_message":
  void _deliverUserMessage(msg, sender);
```

**Target State**:
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
  sender.send({ type: "error", in_reply_to: msg.id, code: "session_mismatch", message: gate.message, session_id: gate.currentSessionId });
  return;
}
```

**Implementation Notes**:
- Validate before `_deliverUserMessage`, queued-message mutation, approve/cancel, `session_sync`, and typed actions call Pi SDK handlers.
- `cancel` and `session_sync` currently bypass the strict Pi-binding guard; after this step they still get their special routing, but only after session validation.
- Per-request replies (`session_history`, `cancelled`, `pong`, action replies, models list) must be stamped when session-scoped and sent only to the sender.
- Logs should include type, peer tail, room id, and short session-id tails only; never payload text/tool args/transcript.
- Existing `RemoteSessionIssuer` is the sole issuer; do not derive from cwd/room or relay state.

**Acceptance Criteria**:
- [ ] All session-scoped outbound server pushes and replies include the current `session_id`.
- [ ] Missing/mismatched session-scoped client commands return sender-only `error{code:"session_mismatch"}`.
- [ ] Rejected stale commands do not call `sendUserMessage`, `ctx.abort`, `ctx.newSession`, `ctx.compact`, model/thinking setters, or queued-message mutation.
- [ ] Tests prove session id is stable across relay reconnect and rotates after Pi SDK session replacement (building on identity-model tests).
- [ ] `corepack pnpm typecheck` and targeted extension router tests pass.

**Rollback**: Remove the session gate and server stamping together. Reverting only validation while leaving required fields risks false confidence and legacy contamination.

---

### Step 3: Drop foreign server messages in the app before any state mutation
**Priority**: High
**Risk**: High
**Source Lens**: fail-fast boundary / lifecycle convergence
**Files**: `app/lib/protocol/protocol.dart`, `app/lib/data/sync/session_gate.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/data/transport/ws_transport.dart`, `app/test/data/sync/sync_service_test.dart`
**Story**: `epic-bold-canonical-session-wire-discriminator-step-3`

**Current State**:
```dart
case SessionHistory():
  // ignore: discarded_futures
  _applyHistory(msg);

Future<void> _applyHistory(SessionHistory h) async {
  final epk = _activeEpk;
  if (epk == null) return;
  final box = await _boxes.msgsBox(epk, _activeRoomId);
  // reconciles active box to h.events
}
```

**Target State**:
```dart
final gate = _sessionGate.accepts(msg, _activeSessionRef());
if (!gate.accepted) {
  debugPrint('[session-gate] drop type=${msg.type} room=${_activeRoomId} reason=${gate.reason}');
  return;
}

case SessionHistory():
  _applyHistory(msg); // only current-session history reaches here
```

**Implementation Notes**:
- Track active expected session id from `PairOk.sessionId` and `RoomInfo.sessionId` for the active `(epk, roomId)`. If the active room has no session id yet, session-scoped server messages are unsafe and should be dropped except for `pair_ok` bootstrap.
- Gate at the top of `_onServerMessage`, before `AgentChunk`, `AgentDone`, `QueuedMessageState`, `UserInput`, tool messages, `ErrorMessage`, `Compaction`, `_setWorking`, `_setQueuedText`, `_upsert`, `_writeCompaction`, or `_applyHistory` run.
- Remove `WsTransport`'s legacy no-room unconditional route in the clean-room path; no-room envelopes should not bypass session attribution.
- High-water `session_started_at` remains useful for replay ordering inside the same session, but it is not an identity check.

**Acceptance Criteria**:
- [ ] Regression test: active session A has rows; a foreign session B `session_history` arrives with a different `session_id`; A's Hive box and session index remain unchanged.
- [ ] Missing `session_id` on `session_history` is dropped and does not clear/overwrite the active box.
- [ ] Foreign chunks/done/tool/queued/error/compaction messages do not affect streaming, working, queued text, persisted rows, or session index.
- [ ] Legitimate same-session reconnect replay with equal `session_id` still hydrates idempotently.
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

**Rollback**: Disable the app gate via one internal seam, then revert the protocol fields and SyncService call sites. Rolling back reopens contamination and should be treated as an emergency-only fork-private regression.

---

### Step 4: Replace cross-PC peer-wide fanout with explicit room targeting while preserving relay opacity
**Priority**: High
**Risk**: Medium
**Source Lens**: boundary clarity / dead-weight compatibility removal
**Files**: `relay/src/handlers/pi_forward.rs`, `relay/src/peers/registry.rs`, `relay/src/protocol/outer.rs`, `pi-extension/src/transport/pi_forward_client.ts`, relay forwarding tests
**Story**: `epic-bold-canonical-session-wire-discriminator-step-4`

**Current State**:
```rust
// relay/src/handlers/pi_forward.rs
if registry.forward_to_peer(to_pc, msg) {
    PiForwardResult::Forwarded
}

// relay/src/peers/registry.rs
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
    for ((p, _), v) in lock.iter() {
        if p == peer_id { /* sends to every live room */ }
    }
}
```

**Target State**:
```rust
let to_room = frame.get("to_room").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
let Some(to_room) = to_room else {
    return PiForwardResult::TransportError(make_transport_error(Some(envelope), "bad_envelope"));
};

if registry.forward_to_room(to_pc, to_room, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

**Implementation Notes**:
- `pi_envelope` adds required `to_room`; `pi_envelope_in` still carries the inner envelope verbatim plus authenticated `from_pc`.
- Relay must not inspect `session_id` in `ct` or generic envelope bodies, must not store it, and must not log it.
- Keep control-frame broadcasts (`peer_online`, `room_announced`, `room_meta_updated`) on their existing subscriber fanout paths; only cross-PC Pi envelope delivery loses peer-wide room fanout.
- `OuterEnvelope` app↔Pi room defaulting is a separate compatibility seam. For this bugfix, no-room app envelopes in `WsTransport` are dropped before app state mutation; future generated-protocol work can remove `default_room` at the schema boundary.

**Acceptance Criteria**:
- [ ] A `pi_envelope` missing `to_room` returns `transport_error: bad_envelope`.
- [ ] A `pi_envelope` for `to_room=room-b` reaches only room B, not every live room for `to_pc`.
- [ ] Relay tests prove `session_id` inside opaque payload/body is carried unchanged and uninspected.
- [ ] Existing presence/rooms subscriber broadcasts still fan out as before.
- [ ] `cargo fmt --check` and targeted relay tests pass.

**Rollback**: Restore `forward_to_peer` use and client omission of `to_room`, knowingly re-opening the cross-room fanout vector. Do not roll back by teaching the relay to parse `session_id`.

## Implementation Order
1. `epic-bold-canonical-session-wire-discriminator-step-1` (depends on `epic-bold-canonical-session-identity-model-step-1`)
2. `epic-bold-canonical-session-wire-discriminator-step-2` (depends on step 1)
3. `epic-bold-canonical-session-wire-discriminator-step-3` (depends on step 2)
4. `epic-bold-canonical-session-wire-discriminator-step-4` (depends on step 3)

## Run notes
- No project-specific `.agents/skills/refactor-conventions/` catalog exists; default refactor-design lenses plus loaded stack references were used.
- `work-view --blocking` is absent, so dependency cycle prevention was checked manually from frontmatter.
- This design is intentionally fork-private and clean-room: fail-closed drops are expected, not compatibility regressions.
