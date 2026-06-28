---
id: story-adversarial-state-protocol-review
kind: story
stage: done
tags: [pi-extension, app, relay, workflow]
parent: feature-adversarial-codebase-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# State-machine/protocol adversarial review

Run the state-machine/protocol correctness pass for `feature-adversarial-codebase-review`.

## Scope

Review `PROTOCOL.md`, `pi-extension/src/protocol/`, `pi-extension/src/session/`, `pi-extension/src/transport/`, `relay/src/handlers/`, `relay/src/peers/`, `relay/src/rooms.rs`, and `app/lib/protocol/` / `app/lib/data/transport/`.

Bias toward failure modes around `/new`, session replacement, stale SDK contexts, room metadata, queued messages, ACK/delivery semantics, reconnect hydration, late attach, dropped or duplicated turn state, and cross-PC envelope forwarding.

## Output schema

```markdown
### <short title>
- **Severity**: critical|high|medium|low
- **Confidence**: high|medium|low
- **Evidence**: `path:line` plus quoted/summarized code behavior
- **Failure scenario**: concrete event sequence that breaks user-visible or protocol behavior
- **Suggested routing**: patch|refactor|test-only|uncertain
```

## Acceptance Criteria

- [x] Findings cite file paths and failure scenarios, not generic smells.
- [x] Review explicitly distinguishes verified bugs from uncertain risks.
- [x] Review calls out any assumptions that need orchestrator verification.

## Reviewer output — 2026-06-28

Read-only pass completed by subagent `855d5cf0-7e69-4d1`. No files were edited by the reviewer.

### Late attach during an active turn can miss the whole reply
- **Severity**: high
- **Confidence**: high
- **Evidence**: `pi-extension/src/index.ts` only creates `_currentTurnId` for terminal/RPC input when an owner is already active; assistant deltas and `agent_done` are dropped when `_currentTurnId` is null; disconnect paths clear `_currentTurnId`.
- **Failure scenario**: phone disconnects or no owner is attached; a local/RPC/daemon turn starts; room metadata shows `working:true`; phone reconnects mid-turn and receives only initial `session_sync`; later chunks/done are suppressed because `_currentTurnId` is null. The final answer may exist only in `_messageBuffer` until another manual/reconnect sync.
- **Suggested routing**: patch.

### Queued-message protocol is exposed by the app but ignored by the Pi extension
- **Severity**: high
- **Confidence**: high
- **Evidence**: `PROTOCOL.md` defines `queued_message_set`, `queued_message_clear`, drain, and `session_sync` replay. App sends/consumes these in `app/lib/data/sync/sync_service.dart`. `pi-extension/src/protocol/types.ts` includes the message types, but the live dispatcher in `pi-extension/src/index.ts` does not handle them.
- **Failure scenario**: user queues a follow-up while the agent is working; app sends `queued_message_set`; Pi silently drops it, never broadcasts `queued_message_state`, and never drains after the turn. The queued prompt is lost or becomes stale local UI.
- **Suggested routing**: patch.

### Cross-PC transport errors are synthesized with non-UUID envelope IDs and get dropped locally
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `relay/src/handlers/pi_forward.rs` creates relay error envelope IDs with a 32-char hex string, while `pi-extension/src/session/envelope.ts` requires UUID-shaped IDs; `SessionPeer` drops `EnvelopeError`; `BrokerRemote` injects relay transport errors into the local broker.
- **Failure scenario**: agent sends to offline/not-authorized cross-PC peer; relay synthesizes `_relay` `transport_error`; local `SessionPeer` rejects the frame before handlers see it. Operator gets generic timeout instead of the explicit reason promised by protocol.
- **Suggested routing**: patch.

### Room snapshot can undo an intentional same-peer room switch
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `app/lib/data/transport/connection_manager.dart` user room switch updates `_activeRoomId`, but later room snapshots call `_maybeAdoptLegacyRoom`; if the first snapshot room differs from the selected active room, `_maybeAdoptLegacyRoom` can overwrite `_activeRoomId` and transport routing.
- **Failure scenario**: user switches from persisted `main` room to second cwd room `work`; next rooms snapshot lists `main` first; manager resets outbound routing to `main`; next prompt is sent to the wrong Pi cwd/session.
- **Suggested routing**: patch.

## No-finding notes from reviewer

- Ordinary attached-turn `working` convergence looked sound.
- Compaction working-state bracketing looked sound.
- Stale SDK context handling for typed `session_new` / `session_compact` looked deliberately guarded.
- Cross-PC anti-spoof looked conceptually sound once sibling cache is populated.

## Orchestrator verification targets

1. Reproduce late attach: start a turn with no app attached, attach before completion, and confirm whether chunks/done/final answer appear without a second sync.
2. Add or inspect a focused extension test for `queued_message_set` / drain semantics; current dispatcher appears to drop it.
3. Add or inspect a relay/extension test for cross-PC `offline` transport_error reaching `SessionPeer`; assert the synthesized envelope ID parses as UUID.
