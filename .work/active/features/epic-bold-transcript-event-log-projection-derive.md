---
id: epic-bold-transcript-event-log-projection-derive
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app, cockpit]
parent: epic-bold-transcript-event-log
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Transcript event log — projection derive (riskiest — design first)

## Brief
Streaming, mobile Hive rows, cockpit entries, and `session_sync` all derive
from the `TranscriptEvent` log. The riskiest part: reconciling optimistic local
sends (pending Hive row + send_timeout watchdog) with server-authoritative
events — the rule that keeps the user's just-sent message visible while
correctly folding in the authoritative transcript. This feature must prove that
reconcile rule before the store and hydration-replay children commit to it.

## Epic context
- Parent epic: `epic-bold-transcript-event-log`
- Position: riskiest child — the projection/reconcile rule is what the rest
  hangs on. Design FIRST.

## Foundation references
- Evidence of the three reducers: pi-extension `_messageBuffer`
  (`pi-extension/src/index.ts:1446-1470`, `:3538`); app `_applyHistory`
  (`app/lib/data/sync/sync_service.dart:671-760`); cockpit `_onEvent`
  (`cockpit/lib/app/cockpit/ui/session/agent_session.dart:436`); optimistic send
  (`app/lib/data/sync/sync_service.dart:170-263`).

<!-- /agile-workflow:refactor-design pins the projection + reconcile rule. -->

## Design decisions

- **Refactor-lane judgment**: keep this item in the bold `[refactor]` lane by explicit autopilot/operator direction. The riskiest behavior-changing enforcement (`session_id` required/fail-closed on the wire) is owned by `epic-bold-canonical-session-*`; this feature designs the transcript projection side-by-side so the current UI behavior is preserved while the storage/hydration children can swap from message-box mutation to log replay.
- **Canonical unit**: `TranscriptEvent` is the only input to transcript UI, Hive rows, `session_sync` compatibility history, and Cockpit entries. Events are append-only; projections may be deleted/rebuilt freely because they are derived.
- **Session scope**: every `TranscriptEvent` carries opaque `session_id`. Until the canonical-session implementation lands, adapters may fill it from the active session shim, but the projection API requires it and filters by equality. The projection never parses or derives meaning from `session_id`, keeping patchbay free to supply a different issuer.
- **Optimistic reconcile rule**: a local optimistic user event is visible immediately. A server-authoritative user event with the same client message id confirms it in place. A send-timeout/failure event marks that id failed only while no authoritative confirmation exists; late authoritative confirmation wins in the derived projection and suppresses the failure row for that id.
- **Replay rule**: `session_history` / `get_messages` are converted to deterministic server-authoritative events and appended/deduped in the event log. They do not replace the active projection. Re-sync is therefore replay, not destructive mutation.
- **Turn coordination**: the transcript projection exposes a lightweight `TranscriptTurnView` (`idle`, `working(replyTo)`, `streaming(replyTo)`, `error(replyTo)`) derived from transcript events as a compatibility view. The sibling turn-state-machine feature may later replace this source with canonical turn transition events; this design only fixes field names (`turnId`, `replyTo`, `status`) and does not block that migration.
- **Dispatch rationale**: direct-read only. The target files and foundation docs were explicit, no `.agents/skills/refactor-conventions/` or pattern skills exist, and this delegated sub-agent harness exposes no subagent tool. The scan still covered code smells, missing abstractions, naming drift, and dead weight across app, pi-extension, and cockpit sources.

## Refactor Overview

The current transcript reducer exists three times and each reducer owns a different truth:

- `pi-extension/src/index.ts` stores SDK `BufferMsg` values in `_messageBuffer` and maps them to `SessionHistoryEvent` only when `session_sync` asks.
- `app/lib/data/sync/sync_service.dart` directly mutates Hive `MessageRecord` rows for live events, but `_applyHistory` computes a replacement `desired` message box from `SessionHistory.events` plus preserved local pending rows.
- `cockpit/lib/app/cockpit/ui/session/agent_session.dart` mutates `_entries` directly while `rpc_data_mapper.dart` maps `get_messages` into a separate mutable `TranscriptMessage` model (`TmTool.done` mutates after creation).

The missing abstraction is a pure append-only event log and projection reducer. The high-value refactor is to create a canonical `TranscriptEvent` algebra and pure projection functions first, then adapt each surface to use that projection without changing user-visible UI or wire shapes. Store migration and hydration replay remain separate children; this design only proves the reconcile rule and creates the projection seam they depend on.

Manual cycle check: the child stories below form a one-way chain (`step-1 → step-2 → step-3 → step-4 → step-5 → step-6`) and no existing item references these new ids, so no frontmatter dependency cycle is introduced.

## Refactor Steps

### Step 1: Define the `TranscriptEvent` algebra and projection contract
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `app/lib/domain/transcript/transcript_event.dart`, `app/lib/domain/transcript/transcript_projection.dart`, `pi-extension/src/session/transcript_event.ts`, `cockpit/lib/app/cockpit/domain/entities/transcript_event.dart`
**Story**: `epic-bold-transcript-event-log-projection-derive-step-1`

**Current State**:
```dart
// app/lib/data/local/records/message_record.dart
enum MsgRole { user, assistant, tool, compaction }

class MessageRecord {
  final String id;
  final int seq;
  final MsgRole role;
  final bool pending;
  ChatMessage toChatMessage() { /* UI projection lives on the row model */ }
}
```

```ts
// pi-extension/src/index.ts
type BufferMsg = { role: "user" | "assistant" | "toolResult" | string; content?: unknown; timestamp?: number };
let _messageBuffer: BufferMsg[] = [];
```

**Target State**:
```dart
sealed class TranscriptEvent {
  const TranscriptEvent({
    required this.eventId,
    required this.sessionId,
    required this.ts,
    this.turnId,
  });

  final String eventId;
  final String sessionId; // opaque; equality only
  final DateTime ts;
  final String? turnId;
}

final class UserMessageSubmitted extends TranscriptEvent {
  const UserMessageSubmitted({required super.eventId, required super.sessionId, required super.ts, required this.clientMessageId, required this.text, this.image});
  final String clientMessageId;
  final String text;
  final MessageImage? image;
}

final class UserMessageConfirmed extends TranscriptEvent { /* same clientMessageId + authoritative payload */ }
final class UserMessageFailed extends TranscriptEvent { /* clientMessageId + code/message */ }
final class AssistantDeltaReceived extends TranscriptEvent { /* replyTo + delta */ }
final class AssistantMessageCommitted extends TranscriptEvent { /* messageId + replyTo + text */ }
final class AssistantDoneReceived extends TranscriptEvent { /* replyTo + usage */ }
final class ToolRequested extends TranscriptEvent { /* toolCallId + tool + args */ }
final class ToolFinished extends TranscriptEvent { /* toolCallId + result/error */ }
final class CompactionRecorded extends TranscriptEvent { /* summary + tokensBefore */ }
```

```ts
export type TranscriptEvent =
  | { kind: "user_submitted"; eventId: string; sessionId: string; ts: number; clientMessageId: string; text: string; images?: WireImage[] }
  | { kind: "user_confirmed"; eventId: string; sessionId: string; ts: number; clientMessageId: string; text: string; images?: WireImage[]; streamingBehavior?: StreamingBehavior }
  | { kind: "user_failed"; eventId: string; sessionId: string; ts: number; clientMessageId: string; code: string; message: string }
  | { kind: "assistant_delta"; eventId: string; sessionId: string; ts: number; replyTo: string; delta: string }
  | { kind: "assistant_committed"; eventId: string; sessionId: string; ts: number; messageId: string; replyTo: string; text: string; usage?: Usage }
  | { kind: "assistant_done"; eventId: string; sessionId: string; ts: number; replyTo: string; usage?: Usage }
  | { kind: "tool_requested"; eventId: string; sessionId: string; ts: number; toolCallId: string; tool: string; args: Record<string, unknown> }
  | { kind: "tool_finished"; eventId: string; sessionId: string; ts: number; toolCallId: string; result?: unknown; error?: string }
  | { kind: "compaction_recorded"; eventId: string; sessionId: string; ts: number; summary: string; tokensBefore?: number };
```

**Implementation Notes**:
- Keep domain event definitions infrastructure-free; adapters translate to Hive rows, ServerMessages, and Cockpit entries.
- `eventId` is deterministic for server replay (`server:<sessionId>:<kind>:<stable-key>:<ts>`) and UUIDv7/local for optimistic events.
- Carry `turnId` when available but do not require the turn-state-machine sibling to land first.
- Do not make app, TS, and cockpit event files independent inventions. Use the same kind names and field names so generated-protocol/patchbay can lift the contract later.

**Acceptance Criteria**:
- [ ] Event kind names and required fields are centralized on each touched surface.
- [ ] Every event requires `sessionId`; adapters provide an explicit compatibility shim only at the boundary.
- [ ] Projection contract returns `messages`, `streaming`, and `turn` without importing UI widgets, Hive, WebSocket, or Pi SDK.
- [ ] No runtime behavior changes yet; this is side-by-side.

**Rollback**: delete the new event/projection contract files. No existing runtime should depend on them until later steps.

---

### Step 2: Prove the app reconcile projection with deterministic tests
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle convergence
**Files**: `app/lib/domain/transcript/transcript_projection.dart`, `app/test/domain/transcript/transcript_projection_test.dart`, `app/lib/data/local/records/message_record.dart`
**Story**: `epic-bold-transcript-event-log-projection-derive-step-2`

**Current State**:
```dart
// app/lib/data/sync/sync_service.dart
await _upsert(MsgRole.user, id, (seq, existing) => existing != null
    ? existing.copyWith(pending: false)
    : MessageRecord(id: id, seq: seq, role: MsgRole.user, text: text, ts: DateTime.now()));

// _applyHistory builds `desired` and deletes/puts Hive keys to match it.
```

**Target State**:
```dart
final projection = deriveTranscriptProjection(
  sessionId: activeSessionId,
  events: eventLog,
);

expect(projection.messages, [
  ProjectedUserMessage(id: 'cli_1', text: 'hello', pending: false),
  ProjectedAssistantMessage(replyTo: 'cli_1', text: 'done'),
]);
expect(projection.turn.status, TranscriptTurnStatus.idle);
```

Reconcile rules pinned by tests:

```dart
// local pending remains visible while absent from authoritative replay
submitted('cli_1', 'hello'),
serverReplay(user('server_old', 'older')),
=> [older confirmed, hello pending]

// authoritative same id confirms in place
submitted('cli_1', 'hello'), confirmed('cli_1', 'hello')
=> [hello confirmed]

// timeout is suppressed by later authoritative confirmation
submitted('cli_1', 'hello'), failed('cli_1', 'send_timeout'), confirmed('cli_1', 'hello')
=> [hello confirmed] // no stale warning row
```

**Implementation Notes**:
- Keep this pure and deterministic; no Hive boxes, timers, `ConnectionManager`, or Flutter `BuildContext`.
- Projection orders by event-log append order, with server replay events forming the authoritative prefix and still-unconfirmed local submitted events retained after that prefix when they are absent from replay.
- Tool request/result collapse into one projected tool row.
- Streaming deltas project into `streaming` until an `AssistantMessageCommitted`, `AssistantDoneReceived`, `Error`, `Cancelled`, or `UserMessageFailed` event closes the turn.
- `working` must converge false after `assistant_done`, `user_failed`, cancellation/error events added in adapters, compaction completion, reconnect replay with an idle turn, and session switch via `sessionId` filtering.

**Acceptance Criteria**:
- [ ] Unit tests cover optimistic submit, echo confirm, timeout, late confirm after timeout, foreign device message, tool request/result collapse, streaming finalize, compaction row, duplicate server replay idempotence, and session-id filtering.
- [ ] `MessageRecord.toChatMessage()` remains a projection target, not the source of reconciliation rules.
- [ ] `flutter test test/domain/transcript/transcript_projection_test.dart` passes.

**Rollback**: revert the projection reducer/tests. Existing `SyncService` continues to mutate rows directly.

---

### Step 3: Route `SyncService` live writes through the projection seam
**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/local/records/message_record.dart`, `app/test/data/sync/sync_service_test.dart`
**Story**: `epic-bold-transcript-event-log-projection-derive-step-3`

**Current State**:
```dart
case AgentChunk(:final inReplyTo, :final delta):
  _chunkBuffer.write(delta);
  _setWorking(true, replyTo: inReplyTo);

case SessionHistory():
  _applyHistory(msg); // computes desired rows and reconciles the Hive box
```

**Target State**:
```dart
void _appendTranscriptEvent(TranscriptEvent event) {
  if (event.sessionId != _activeSessionId) return;
  _eventBuffer = appendDeduped(_eventBuffer, event);
  final next = deriveTranscriptProjection(sessionId: _activeSessionId, events: _eventBuffer);
  _writeProjectionDiff(next);
}

case AgentChunk(:final inReplyTo, :final delta):
  _appendTranscriptEvent(AssistantDeltaReceived(...));

case SessionHistory():
  for (final event in historyToTranscriptEvents(msg, sessionId: _activeSessionId)) {
    _appendTranscriptEvent(event);
  }
```

**Implementation Notes**:
- This is an adapter refactor, not the append-only Hive store. Keep the current `msgs:<epk>:<room>` materialized boxes for now, but make their rows a projection output.
- `_applyHistory` should stop owning reconciliation semantics. It may remain as a compatibility adapter that converts history events and calls `_appendTranscriptEvent` until the hydration-replay child removes the old name.
- Preserve existing pending-send timers as event producers (`UserMessageFailed`) until the store child persists timer-origin events.
- Keep `_writeChain` serialization around projection diff writes; projection purity does not remove Hive write ordering concerns.
- Use active `session_id` from canonical-session when available; use a clearly named compatibility shim while that sibling is in flight.

**Acceptance Criteria**:
- [ ] Existing `app/test/data/sync/sync_service_test.dart` remains green.
- [ ] New tests prove `_applyHistory` replay does not delete local pending events and duplicate replay emits no Hive churn.
- [ ] New tests prove late authoritative echo after timeout converges to a confirmed user projection (or, if implementation preserves current failure-row behavior for compatibility, the rationale is logged in this story before review).
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

**Rollback**: revert `SyncService` to direct `_upsert` / `_applyHistory` mutation. Projection contract/tests from steps 1-2 can remain unused.

---

### Step 4: Make pi-extension session history a projection from transcript events
**Priority**: Medium
**Risk**: Medium
**Source Lens**: missing abstraction / generated-contract preparation
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_event.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-transcript-event-log-projection-derive-step-4`

**Current State**:
```ts
let _messageBuffer: BufferMsg[] = [];

function _buildSessionHistoryMessage(inReplyTo: string, limit: number | undefined) {
  const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
  return { type: "session_history", in_reply_to: inReplyTo, events: slice, eos: true, truncated };
}
```

**Target State**:
```ts
let _transcriptEvents: TranscriptEvent[] = [];

function _buildSessionHistoryMessage(inReplyTo: string, limit: number | undefined) {
  const projection = projectSessionHistory({ sessionId: _remoteSession.sessionId, events: _transcriptEvents, limit });
  return {
    type: "session_history",
    in_reply_to: inReplyTo,
    session_started_at: _remoteSession.startedAt,
    events: projection.events,
    eos: true,
    truncated: projection.truncated,
  } satisfies ServerMessage;
}
```

**Implementation Notes**:
- Keep the outgoing wire shape unchanged until generated-protocol/canonical-session flip it.
- Convert SDK `message_end`, live `tool_execution_*`, `session_compact`, and `_deliverUserMessage` echo paths to append transcript events. If store migration is not ready, `_messageBuffer` may remain as a legacy input adapter but must no longer be the place where projection rules live.
- Use the same deterministic event-id convention as the app to make replay idempotent.
- Preserve per-sender `session_sync` behavior: queued state first, history only to the requester.

**Acceptance Criteria**:
- [ ] Existing extension session-sync tests pass, including limit/truncated, image replay, compaction replay, and late-attach sync.
- [ ] Tests prove `_mapAgentMessagesToEvents` is either retired or reduced to a legacy adapter into `TranscriptEvent`.
- [ ] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

**Rollback**: restore `_messageBuffer` as the direct `session_history` input and leave app/cockpit projection work intact.

---

### Step 5: Make Cockpit transcript entries immutable projection outputs
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / naming inconsistency
**Files**: `cockpit/lib/app/cockpit/domain/entities/transcript_message.dart`, `cockpit/lib/app/cockpit/domain/entities/transcript_event.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`
**Story**: `epic-bold-transcript-event-log-projection-derive-step-5`

**Current State**:
```dart
final class TmTool extends TranscriptMessage {
  TmTool({required this.callId, required this.name, required this.args});
  bool done = false;
  bool isError = false;
  String resultText = '';
}

// AgentSession._populateTranscript clears _entries and maps Tm* directly.
```

**Target State**:
```dart
sealed class CockpitTranscriptEvent { /* same kind names as TranscriptEvent */ }

final class ProjectedToolMessage extends ProjectedTranscriptMessage {
  const ProjectedToolMessage({required this.callId, required this.name, required this.args, required this.status, this.resultText = ''});
  final ToolProjectionStatus status;
}

final projection = deriveCockpitTranscript(events);
_entries
  ..clear()
  ..addAll(projection.entries.map(toAgentEntry));
```

**Implementation Notes**:
- Cockpit remains local-only; do not add relay, pairing, mobile session routing, or crypto.
- Retire mutable `TmTool` as the domain model. Mutation can still happen inside a local reducer while building immutable projected output.
- `_onEvent` should append local transcript events and re-project open text/tool buffers instead of owning a parallel fold unrelated to `get_messages`.
- Keep session-path naming separate from remote `session_id`; if canonical-session has landed, store it as an optional opaque field, not a relay dependency.

**Acceptance Criteria**:
- [ ] `rpc_data_mapper.transcriptMessages` and live `_onEvent` use the same projection rules for user/text/thinking/tool messages.
- [ ] Tool start/result cannot leave a mutable domain object half-updated after projection.
- [ ] Existing Cockpit transcript tests pass; add focused mapper/projection tests if coverage is absent.
- [ ] `flutter test` targeted cockpit tests pass or platform/tooling blockers are recorded.

**Rollback**: restore `TmTool` mutation and direct `_entries` folding. App/pi-extension event projection remains unaffected.

---

### Step 6: Add cross-surface projection fixtures and convergence checks
**Priority**: Medium
**Risk**: Low
**Source Lens**: testing integrity / generated-contract preparation
**Files**: `.orchestration/contracts/`, `app/test/domain/transcript/`, `pi-extension/src/extension.test.ts`, `cockpit/test/`
**Story**: `epic-bold-transcript-event-log-projection-derive-step-6`

**Current State**:
```text
Each surface tests its own reducer shape. There is no shared fixture proving that
"optimistic send → echo → chunks → tool → done → replay" derives the same
messages in app, pi-extension history, and cockpit.
```

**Target State**:
```json
{
  "name": "optimistic-send-authoritative-replay",
  "session_id": "sess-fixture",
  "events": [
    { "kind": "user_submitted", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "user_confirmed", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "assistant_delta", "replyTo": "cli_1", "delta": "done" },
    { "kind": "assistant_done", "replyTo": "cli_1" }
  ],
  "projection": {
    "messages": [
      { "role": "user", "id": "cli_1", "status": "confirmed", "text": "hello" },
      { "role": "assistant", "replyTo": "cli_1", "text": "done" }
    ],
    "turn": { "status": "idle" }
  }
}
```

**Implementation Notes**:
- Use fixtures to pin the projection semantics until generated-protocol replaces hand mirrors.
- Include negative/convergence cases: foreign `session_id` ignored, duplicate replay idempotent, failed send clears working, late confirm after timeout, cancel/error clears streaming, compaction produces a system row.
- Keep fixtures content-only and free of local paths/secrets.

**Acceptance Criteria**:
- [ ] App, pi-extension, and cockpit tests consume at least one shared fixture or mirrored fixture with identical expected projection.
- [ ] Convergence tests cover `working` false after success, error, abort/cancel, compaction, reconnect replay, and session switch/filtering.
- [ ] Contract notes identify which fixture becomes generated-protocol schema coverage later.

**Rollback**: remove the new fixtures/tests. Runtime projection code from earlier steps remains in place.

## Implementation Order

1. `epic-bold-transcript-event-log-projection-derive-step-1`
2. `epic-bold-transcript-event-log-projection-derive-step-2` (depends on step 1)
3. `epic-bold-transcript-event-log-projection-derive-step-3` (depends on step 2)
4. `epic-bold-transcript-event-log-projection-derive-step-4` (depends on step 3)
5. `epic-bold-transcript-event-log-projection-derive-step-5` (depends on step 4)
6. `epic-bold-transcript-event-log-projection-derive-step-6` (depends on step 5)

## Atomic / rollback notes

No step is intentionally irreversible. Step 3 is the riskiest runtime switchover because it changes the app writer from direct row mutation to projection-diff writes; keep it in a single commit so rollback can restore the current `_upsert` / `_applyHistory` path without reverting the event algebra. Step 4 similarly keeps the public `session_history` wire unchanged while moving pi-extension internals, so rollback is local to the extension projection adapter.

## Review — advanced to done (2026-06-30)

All 6 child stories `done`. Decomposition realized as designed; rollback notes
documented. Epic complete. (Advancing unblocks downstream stories that
depended on this epic-level completion.)
