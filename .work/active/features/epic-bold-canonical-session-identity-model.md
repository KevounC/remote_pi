---
id: epic-bold-canonical-session-identity-model
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — identity model (riskiest — design first)

## Brief
The `RemoteSession` / `RemotePeer` / `RemotePc` / `RemoteRoom` domain types and
their relationship to relay routing. A canonical `RemoteSession` (stable
session id, owns cwd, room, model, thinking, started_at, working, transcript) is
the single key for relay routing, app Hive boxes, persistence, UI tiles,
cwd-lock identity, working indicator, and transcript.

The riskiest architectural call: does the relay *learn* about sessions, or stay
a room-router that carries `session_id` **opaquely**? This epic's answer is the
latter — opaque carry + endpoint validation — keeping the relay dumb and the
session domain on the endpoints. This feature must prove that posture is
sufficient before the wire-discriminator and relay-targeting children commit to
it.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: riskiest child — the relay's session posture is the architectural
  call the rest of the epic hangs on. Design FIRST.

## Foundation references
- Evidence of the five overlapping identities: Pi SDK runtime
  (`pi-extension/src/index.ts:1550-1625`), relay room key
  (`relay/src/peers/registry.rs:1-70`), cwd-derived room id
  (`pi-extension/src/rooms.ts:43`), app Hive key (`app/lib/data/local/boxes.dart:8`),
  cockpit JSONL path (`cockpit/lib/app/cockpit/domain/entities/session_info.dart:1-22`).

<!-- /agile-workflow:refactor-design pins the identity types + relay posture. -->

## Design decisions
- **Identity issuer**: the Pi-extension endpoint is the authority for a Remote Pi `session_id`. It resolves the value from Pi's SDK session identity (`ctx.sessionManager.getSessionId()`) and only falls back to a locally minted UUIDv7 in tests/legacy seams where the SDK id is unavailable. This makes the discriminator stable for the real Pi session without deriving it from cwd, room, pairing, or relay state.
- **Identity shape**: `session_id` is an opaque, non-empty string. Receivers compare it for equality only. They do not parse timestamp bits, infer cwd, infer room, or expose it as a human label. `session_started_at` remains ordering/high-water metadata and is not an identity key.
- **Rotation**: relay reconnect and `/remote-pi` stop/start keep the same `session_id` for the same Pi SDK session. Pi SDK session replacement (`session_new`, `/new`, `/resume`, `/fork`, `switch_session`, daemon fresh-session restart) rotates the `session_id` and causes endpoints to treat delayed frames from the old session as foreign.
- **Endpoint validation**: app and extension validate fail-closed. Session-scoped server pushes missing or mismatching `session_id` are dropped by the app before touching streaming state, working state, queued text, Hive, or the session index. Session-scoped client commands missing or mismatching `session_id` are rejected by the extension before Pi SDK calls; correlated commands receive a sender-only `error` with `code: "session_mismatch"`.
- **Relay posture**: the relay never learns sessions. App↔Pi `session_id` lives inside the opaque `ct` payload; Pi↔Pi `session_id` lives inside the generic envelope body when a body is session-scoped. Relay routing remains `(peer, room)` / `(to_pc, to_room)` and relay logs/metrics never include `session_id` or payload content.
- **Refactor-tag rationale**: the black-box protocol shape changes, but this item remains in the bold `[refactor]` lane by explicit autopilot/operator direction because it restores a designed-then-dropped invariant in a fork-private clean-room break. The behavior-changing compatibility consequence is logged here and handled by fail-closed acceptance tests rather than silently preserving legacy no-session peers.
- **Generated-protocol coordination**: until `epic-bold-generated-protocol` lands, handwritten TS/Dart/Rust mirrors add a single `SESSION_SCOPED_*` registry. The generated schema should lift these field semantics unchanged; this feature does not choose the schema language.
- **Patchbay migration posture**: the wire exposes only an opaque discriminator and endpoint validation. No fork-specific cwd hashing, room naming, or relay database state becomes the session identity, so patchbay can replace the issuer later without changing relay semantics.

## Refactor Overview
The current system has five overlapping identities: Pi SDK runtime session, relay `(peer_id, room_id)`, cwd/name-derived room id, app Hive key, and Cockpit JSONL path. The absence of a canonical session discriminator lets a foreign `session_history` replace the active app message box via `SyncService._applyHistory`; legacy no-room frames and relay peer-wide cross-PC fanout make that failure mode fail open.

This design crystallizes `RemoteSession` as the endpoint-owned domain identity while keeping relay routing session-blind. The design uses direct-read evidence only; no exploratory sub-agent was dispatched because this delegated worker has a bounded target and the key files/docs were explicit. Advisory review was not run from this nested sub-agent context because no subagent/peer tool is exposed here; the item records the rationale and concrete acceptance tests for the riskiest call.

Cycle check: the emitted stories form a linear chain (`step-1 -> step-2 -> step-3 -> step-4 -> step-5`). The parent feature has `depends_on: []`; downstream sibling features depend on this feature, not on its children. No frontmatter cycle is introduced.

## Refactor Steps

### Step 1: Define `RemoteSession` and Pi-extension session-id issuance
**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / naming inconsistency  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/remote_session.ts`, `pi-extension/src/protocol/types.ts`, `app/lib/protocol/protocol.dart`  
**Story**: `epic-bold-canonical-session-identity-model-step-1`

**Current State**:
```ts
let _sessionStartedAt: number | null = null;
const roomId = roomIdFor(cwd, sessionName);
if (_sessionStartedAt === null) _sessionStartedAt = Date.now();
```

**Target State**:
```ts
export type RemoteSessionId = string;

export interface RemoteSession {
  sessionId: RemoteSessionId;
  peerId: string;
  roomId: string;
  cwd: string;
  name: string;
  startedAt: number;
  model?: string;
  thinking?: ThinkingLevel;
  working: boolean;
}

export function resolveRemoteSessionId(ctx: Pick<ExtensionContext, 'sessionManager'>): RemoteSessionId {
  const sdkId = ctx.sessionManager.getSessionId();
  if (typeof sdkId === 'string' && sdkId.length > 0) return sdkId;
  return uuid7();
}
```

**Implementation Notes**:
- Put identity issuance behind one Pi-extension module; do not add more module-level identity globals in `index.ts`.
- Bootstrap the app with `session_id` in `pair_ok` and room metadata.
- Preserve across relay reconnect; rotate on Pi SDK session replacement.

**Acceptance Criteria**:
- [ ] Pi-extension has one `RemoteSession`/issuer module.
- [ ] `pair_ok` and room metadata include `session_id`.
- [ ] Tests prove stable-across-reconnect and rotates-on-session-replacement.
- [ ] `corepack pnpm typecheck` and targeted Pi-extension tests pass.

**Rollback**: Revert the identity module and `pair_ok`/room-meta field additions.

---

### Step 2: Centralize session-scoped wire field semantics
**Priority**: High  
**Risk**: Medium  
**Source Lens**: single-source-of-truth / generated-contract preparation  
**Files**: `pi-extension/src/protocol/types.ts`, `pi-extension/src/protocol/codec.ts`, `app/lib/protocol/protocol.dart`, future generated schema inputs  
**Story**: `epic-bold-canonical-session-identity-model-step-2`

**Current State**:
```dart
// app/lib/protocol/protocol.dart
// 1 pairing = 1 session: no session_id on any message.
```

**Target State**:
```ts
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
```

**Implementation Notes**:
- Every session-scoped message in those registries carries required `session_id`.
- `pair_ok` carries `session_id` for bootstrap; `pair_request`, `pair_error`, `pong`, `bye`, and relay presence/rooms controls remain non-session-scoped.
- Add `session_mismatch` to known error codes while preserving open error-code tolerance.

**Acceptance Criteria**:
- [ ] TS/Dart mirrors derive validation tests from one session-scoped registry.
- [ ] A new session-scoped type without `session_id` fails tests.
- [ ] Generated-protocol sibling can lift these semantics unchanged.
- [ ] `corepack pnpm typecheck` and `flutter analyze` pass or blockers are reported.

**Rollback**: Revert the registry/field additions before reverting validation steps.

---

### Step 3: Enforce endpoint validation fail-closed
**Priority**: High  
**Risk**: High  
**Source Lens**: fail-fast boundary / lifecycle convergence  
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/transport/ws_transport.dart`, `app/lib/protocol/protocol.dart`, `pi-extension/src/index.ts`, `pi-extension/src/session/session_gate.ts`  
**Story**: `epic-bold-canonical-session-identity-model-step-3`

**Current State**:
```dart
case SessionHistory():
  _applyHistory(msg); // replaces active message box for current (epk, room)
```

**Target State**:
```dart
if (!_sessionGate.accepts(msg, activeSessionRef)) {
  debugPrint('[session-gate] drop type=${msg.type} room=${activeSessionRef.roomId} reason=session-mismatch');
  return;
}
```

**Implementation Notes**:
- Validate before `_applyHistory`, streaming mutation, working mutation, queued state, and any Hive write.
- Remove the app transport's legacy no-room unconditional routing in the clean-room path.
- Extension rejects stale commands before Pi SDK calls and replies only to the sender.

**Acceptance Criteria**:
- [ ] Foreign `session_history` cannot replace the active message box.
- [ ] Foreign chunks/done/tool messages do not affect active streaming, working, or persisted rows.
- [ ] Stale app commands return `session_mismatch` and do not call Pi SDK.
- [ ] Targeted app sync and extension router tests pass.

**Rollback**: Disable and revert the session gate after rolling back dependent consumers.

---

### Step 4: Preserve relay opacity and route only by peer/room
**Priority**: High  
**Risk**: Medium  
**Source Lens**: boundary clarity / dead-weight legacy compatibility  
**Files**: `relay/src/protocol/outer.rs`, `relay/src/handlers/peer.rs`, `relay/src/handlers/pi_forward.rs`, `relay/src/peers/registry.rs`  
**Story**: `epic-bold-canonical-session-identity-model-step-4`

**Current State**:
```rust
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}

pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool { /* every room */ }
```

**Target State**:
```rust
pub struct OuterEnvelope {
    pub peer: String,
    pub room: String,
    pub ct: String, // opaque; may contain endpoint-owned session_id
}
// Cross-PC routes by explicit room/to_room, never by session_id.
```

**Implementation Notes**:
- Relay tests should prove `session_id` inside `ct` or generic envelope bodies is carried unchanged and uninspected.
- Missing room should fail closed or be isolated behind a temporary compatibility seam.
- Long-term cross-PC fix is explicit room targeting; relay never uses `session_id` for routing.

**Acceptance Criteria**:
- [ ] Relay has no session-id registry key, DB field, or routing branch.
- [ ] Opaque payload tests prove verbatim carry.
- [ ] Peer-wide fanout is rejected as the long-term targeting posture.
- [ ] `cargo fmt --check` and targeted relay tests pass.

**Rollback**: Restore default-room parsing and peer-wide forwarding, knowingly reopening the fanout risk.

---

### Step 5: Re-key endpoint projections by canonical session
**Priority**: Medium  
**Risk**: High  
**Source Lens**: naming inconsistency / persistence key consolidation  
**Files**: `app/lib/data/local/boxes.dart`, `app/lib/data/local/records/session_index_record.dart`, `app/lib/routing/adaptive.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `cockpit/lib/app/cockpit/domain/entities/session_info.dart`  
**Story**: `epic-bold-canonical-session-identity-model-step-5`

**Current State**:
```dart
static String msgsBoxName(String epk, String roomId) => 'msgs_${toAppEpk(epk)}__$roomId';
static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

**Target State**:
```dart
class RemoteSessionRef {
  final String peerId;
  final String roomId;
  final String sessionId;
  String get storageKey => '$peerId:$roomId:$sessionId';
}
```

**Implementation Notes**:
- App transcript boxes/session index use `(peer, room, session_id)`; room reachability remains `(peer, room)`.
- Old peer+room boxes are ignored or clean-room re-synced, not destructively deleted.
- Cockpit stays local-only; align naming so Pi JSONL session id/path is a projection of the same concept, not a relay dependency.

**Acceptance Criteria**:
- [ ] Two `session_id`s on the same `(peer, room)` do not share messages.
- [ ] Reachability still works by `(peer, room)`.
- [ ] Cockpit naming distinguishes local JSONL path from canonical session id without adding remote behavior.
- [ ] Targeted app persistence tests pass.

**Rollback**: Restore app keys to `(epk, roomId)`; old boxes remain intact for recovery.

## Implementation Order
1. `epic-bold-canonical-session-identity-model-step-1`
2. `epic-bold-canonical-session-identity-model-step-2` (depends on step 1)
3. `epic-bold-canonical-session-identity-model-step-3` (depends on step 2)
4. `epic-bold-canonical-session-identity-model-step-4` (depends on step 3)
5. `epic-bold-canonical-session-identity-model-step-5` (depends on step 4)

