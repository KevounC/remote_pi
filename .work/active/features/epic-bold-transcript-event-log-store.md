---
id: epic-bold-transcript-event-log-store
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app]
parent: epic-bold-transcript-event-log
depends_on: [epic-bold-transcript-event-log-projection-derive]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Transcript event log — append-only store

## Brief
Append-only `TranscriptEvent` store per session — pi-extension as source of
truth (`_messageBuffer` becomes an event log), app as local log (Hive can store
events; today it stores materialized rows). Scoped per session (depends on
`epic-bold-canonical-session`).

## Epic context
- Parent epic: `epic-bold-transcript-event-log`
- Position: consumer of `projection-derive`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:406-424`, `:1446-1470`;
  `app/lib/data/local/boxes.dart:1-68`.

<!-- /agile-workflow:refactor-design pins the store + retention. -->

## Design decisions

- **Refactor-lane judgment**: keep this in the bold `[refactor]` lane by explicit operator/autopilot direction. The public behavior target is the same transcript UI/session sync behavior, but the persistence source-of-truth moves from mutable materialized rows to append-only events. The behavior-changing fail-closed session discriminator is owned by the canonical-session epic; this item designs the store so that discriminator has a safe place to land.
- **Store shape**: the app gets a new Hive-backed append-only event box per `(peer, room, session_id)`. Hive is the right private-fork choice because the app already owns Hive bootstrap and read repositories; this avoids a second mobile persistence stack before patchbay. The pi-extension gets a new process-local `TranscriptEventLog` module replacing `_messageBuffer`; Pi's SDK/session persistence remains the extension's durable transcript source, so no new extension disk store is introduced in this slice.
- **Session scope**: every stored event carries opaque `session_id`. Store APIs require the session id up front and filter by equality only. Compatibility shims may derive a temporary active session id while canonical-session implementation is in flight, but missing session id must not reach the event store core.
- **Append and dedupe rule**: `eventId` is the store key/dedupe key. App Hive records also carry monotonic `seq` for stable replay order. Replayed `session_history`, live events, optimistic submits, timeout failures, and late confirmations all call `appendAll`; duplicates are skipped and never rewritten.
- **Projection status**: `MessageRecord` boxes remain compatibility/materialized projections for the current UI/read repositories. They are explicitly derived and rebuildable; deleting/rebuilding them must not delete transcript truth. Re-sync appends/dedupes events and projects from the event log instead of replacing the message box.
- **Retention**: old `msgs_<epk>__<room>` boxes are not destructively migrated. New session-scoped event boxes are clean-room caches populated by live events and replay; rollback can restore the old row-writer path because old projection boxes remain intact until a later cleanup/release.
- **Patchbay posture**: the store accepts the canonical `TranscriptEvent` algebra and opaque `session_id` without baking in cwd hashes, relay room meanings, or Hive-specific domain types. Patchbay can replace the app adapter and the Pi issuer without changing the domain event contract.
- **Dispatch rationale**: direct-read only. The feature scope was bounded to the listed app/pi-extension store surfaces, no `.agents/skills/refactor-conventions/` or pattern catalog exists, and the prior sibling design already fixed the canonical `TranscriptEvent` unit. No exploratory sub-agent was needed for this design pass.

## Refactor Overview

Current transcript persistence has two mutable truths:

- `pi-extension/src/index.ts` appends SDK-shaped `BufferMsg` objects to `_messageBuffer` and maps them to `SessionHistoryEvent` only at `session_sync` time.
- `app/lib/data/sync/sync_service.dart` writes `MessageRecord` rows directly and `_applyHistory` reconciles the active `msgs_<epk>__<room>` box to a computed replacement list, preserving only local pending rows.

The sibling projection design already defines `TranscriptEvent` as the canonical unit and the optimistic/authoritative reconciliation rule. This store slice makes that unit durable on the app and the source log on the extension. The app adds a Hive event store keyed by canonical session, then makes `SyncService` append events and rebuild the existing `MessageRecord` projection from the log. The extension replaces `_messageBuffer` with a `TranscriptEventLog` module and builds `session_history` as a projection from that log. Hydration-replay can then remove the old `_applyHistory` replacement semantics because replay is now an event append/dedupe operation.

Manual cycle check (no `work-view` binary used): feature `epic-bold-transcript-event-log-store` depends only on `epic-bold-transcript-event-log-projection-derive`; the downstream hydration feature depends on this feature. The emitted stories form a one-way chain: projection feature -> store step 1 -> step 2 -> step 3 -> step 4 -> step 5. No story depends on the parent feature or on hydration, so no frontmatter cycle is introduced.

## Refactor Steps

### Step 1: Add the app Hive `TranscriptEvent` store adapter
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / ports and adapters
**Files**: `app/lib/domain/contracts/transcript_event_store.dart`, `app/lib/data/local/records/transcript_event_record.dart`, `app/lib/data/local/transcript_event_store_hive.dart`, `app/lib/data/local/boxes.dart`, `app/lib/config/dependencies.dart`
**Story**: `epic-bold-transcript-event-log-store-step-1`

**Current State**:
```dart
// app/lib/data/local/boxes.dart
//   DURABLE  msgs_<epk>__<roomId>   key = seq (int)        → MessageRecord
//   DURABLE  sessions_index         key = <epk>:<roomId>   → SessionIndexRecord
Future<Box<dynamic>> msgsBox(String epk, String roomId) =>
    Hive.openBox<dynamic>(msgsBoxName(epk, roomId));

static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';
```

**Target State**:
```dart
// app/lib/domain/contracts/transcript_event_store.dart
abstract interface class TranscriptEventStore {
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  );
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key);
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key);
}

final class TranscriptSessionKey {
  const TranscriptSessionKey({
    required this.peerId,
    required this.roomId,
    required this.sessionId,
  });
  final String peerId;
  final String roomId;
  final String sessionId;
}

// app/lib/data/local/records/transcript_event_record.dart
final class TranscriptEventRecord {
  const TranscriptEventRecord({
    required this.eventId,
    required this.seq,
    required this.sessionId,
    required this.kind,
    required this.ts,
    required this.payload,
  });

  final String eventId; // Hive key + dedupe key
  final int seq;        // stable append/replay order
  final String sessionId;
  final String kind;
  final int ts;
  final Map<String, Object?> payload;
}

// app/lib/data/local/boxes.dart
Future<Box<dynamic>> transcriptEventsBox(TranscriptSessionKey key) =>
    Hive.openBox<dynamic>(transcriptEventsBoxName(key));

static String transcriptEventsBoxName(TranscriptSessionKey key) =>
    'transcript_events_${toAppEpk(key.peerId)}__${_safe(key.roomId)}__${_safe(key.sessionId)}';
```

**Implementation Notes**:
- Define the store port outside Hive. Domain/projection code depends on `TranscriptEventStore`, not on `LocalBoxes` or `Hive`.
- Store `eventId` as the Hive key and `seq` in the value. `appendAll` scans/keeps the max seq, skips existing keys, and appends only unseen events.
- `TranscriptEventRecord` is the only app-side JSON codec for the event algebra until generated-protocol replaces hand mirrors. Unknown `kind` fails fast at `fromJson` and never reaches projection.
- Register `HiveTranscriptEventStore` in `config/dependencies.dart` so `SyncService` can receive the port through DI.
- Keep existing `msgs` and `sessions_index` APIs intact; they become projection storage in later steps.

**Acceptance Criteria**:
- [ ] App has a `TranscriptEventStore` port and a Hive adapter with no UI/network imports.
- [ ] Event boxes are keyed by `(peer, room, session_id)` and records require matching `sessionId`.
- [ ] Appending the same `eventId` twice is idempotent and preserves original seq/order.
- [ ] Existing `LocalBoxes.init` behavior still opens common boxes and wipes only `runtime`.
- [ ] Targeted store tests pass (`flutter test` or the nearest Dart/Hive test command available).

**Rollback**: remove the new store port/adapter/DI binding. Existing `msgs` boxes and `SyncService` direct row writes remain untouched.

---

### Step 2: Make app projections rebuildable outputs of the event store
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle convergence
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/local/records/message_record.dart`, `app/lib/data/local/boxes.dart`, `app/test/data/sync/sync_service_test.dart`
**Story**: `epic-bold-transcript-event-log-store-step-2`

**Current State**:
```dart
// app/lib/data/sync/sync_service.dart
await _upsert(MsgRole.user, id, (seq, _) => MessageRecord(
  id: id,
  seq: seq,
  role: MsgRole.user,
  text: text,
  pending: true,
  ts: now,
));

case SessionHistory():
  _applyHistory(msg); // computes desired rows and mutates/deletes the msgs box
```

**Target State**:
```dart
Future<void> _appendTranscriptEvents(Iterable<TranscriptEvent> events) async {
  final key = _activeTranscriptKeyOrNull();
  if (key == null) return;
  final result = await _eventStore.appendAll(key, events);
  if (result.appended == 0) return;
  final log = await _eventStore.readSession(key);
  final projection = deriveTranscriptProjection(
    sessionId: key.sessionId,
    events: log,
  );
  await _rewriteMessageProjection(key, projection);
}

Future<void> _rewriteMessageProjection(
  TranscriptSessionKey key,
  TranscriptProjection projection,
) async {
  // `msgs` is a cache/projection: safe to diff, clear, or rebuild from events.
}
```

**Implementation Notes**:
- Live paths (`sendMessage`, `UserInput`, `AgentChunk`, `AgentDone`, tool request/result, cancelled/error, compaction) append the sibling-defined `TranscriptEvent` variants first. `MessageRecord` writes happen only through projection materialization.
- Pending-send timers become event producers: timeout appends `UserMessageFailed`; a late `UserMessageConfirmed` with the same client id wins in the projection per the sibling reconcile rule.
- `SessionHistory` is converted to deterministic server-authoritative events and passed to `appendAll`; it does not compute a replacement `desired` list itself. The hydration-replay child may rename/remove `_applyHistory`, but this store step must already make re-sync an append/dedupe operation.
- Keep `_writeChain` around event append + projection writes. Projection purity does not remove ordering hazards around Hive writes and timers.
- Store-derived projection may rewrite or diff the `msgs` box, but that box is explicitly disposable. Tests should prove deleting it and re-projecting from events recovers the visible transcript.

**Acceptance Criteria**:
- [ ] `SyncService` no longer treats `MessageRecord` boxes as transcript truth; they are derived from `TranscriptEventStore`.
- [ ] `session_history` replay appends/dedupes events and does not delete local unseen events from the event log.
- [ ] Duplicate replay produces zero new events and no visible message churn.
- [ ] Deleting/rebuilding the `msgs` projection from the stored event log recovers the same ordered messages.
- [ ] Working/streaming convergence tests cover success, timeout, late confirm after timeout, cancel/error, compaction, reconnect replay, and session switch filtering.
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

**Rollback**: restore `SyncService` direct `_upsert`/`_applyHistory` writes and leave the event store unused. Because projection boxes were not deleted as part of rollback, the old row-based cache remains available.

---

### Step 3: Replace pi-extension `_messageBuffer` with `TranscriptEventLog`
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_event.ts`, `pi-extension/src/session/transcript_event_log.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-transcript-event-log-store-step-3`

**Current State**:
```ts
// pi-extension/src/index.ts
type BufferMsg = { role: "user" | "assistant" | "toolResult" | string; content?: unknown; timestamp?: number };
let _messageBuffer: BufferMsg[] = [];

pi.on("message_end", (event) => {
  const m = event?.message;
  if (m.role === "user" || m.role === "assistant" || m.role === "toolResult") {
    _messageBuffer.push(m as BufferMsg);
  }
});

const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
```

**Target State**:
```ts
// pi-extension/src/session/transcript_event_log.ts
export class TranscriptEventLog {
  private readonly events: TranscriptEvent[] = [];
  private readonly seen = new Set<string>();

  append(event: TranscriptEvent): boolean {
    if (this.seen.has(event.eventId)) return false;
    this.seen.add(event.eventId);
    this.events.push(event);
    return true;
  }

  appendAll(events: Iterable<TranscriptEvent>): number { /* append unseen */ }

  forSession(sessionId: string): readonly TranscriptEvent[] {
    return this.events.filter((event) => event.sessionId === sessionId);
  }

  resetSession(sessionId: string): void { /* drop only this session's events */ }
}

// pi-extension/src/index.ts
const _transcriptLog = new TranscriptEventLog();
pi.on("message_end", (event) => {
  for (const transcriptEvent of sdkMessageToTranscriptEvents(event.message, _currentRemoteSessionId())) {
    _transcriptLog.append(transcriptEvent);
  }
});
```

**Implementation Notes**:
- Do not add extension disk persistence in this slice. The old `_messageBuffer` was process-local; the new log is process-local but typed, session-scoped, append-only, and deduped. Pi SDK session persistence remains the durable transcript owner.
- Convert user, assistant text/tool blocks, tool results, compaction markers, provider errors, and `agent_done` into `TranscriptEvent`s at their boundary hooks.
- Build outgoing `session_history` from a projection of `_transcriptLog.forSession(sessionId)`, preserving the existing wire shape until generated-protocol/canonical-session changes land.
- Export test seams mirroring `_setMessageBufferForTest` only as event-log seams (`_setTranscriptEventsForTest`, `_getTranscriptEventsForTest`) to retire buffer-shaped tests.
- `session_new`/session replacement resets or rotates by session id; relay stop/start/reconnect preserves the active session log.

**Acceptance Criteria**:
- [ ] `_messageBuffer` is removed or reduced to a temporary SDK-message adapter with no projection responsibility.
- [ ] `session_sync` output, limit/truncation, image replay, compaction replay, tool result stringification, and late-attach sync are preserved.
- [ ] Reconnect preserves the transcript event log for the same session; session replacement does not replay old events into the new session id.
- [ ] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

**Rollback**: restore `_messageBuffer` and `_mapAgentMessagesToEvents` as the `session_history` source. The app Hive event store can remain unused while extension rollback is applied.

---

### Step 4: Re-key transcript retention by canonical session and keep projections disposable
**Priority**: Medium
**Risk**: High
**Source Lens**: naming inconsistency / persistence key consolidation
**Files**: `app/lib/data/local/boxes.dart`, `app/lib/data/local/records/session_index_record.dart`, `app/lib/data/repositories/session_read_repository.dart`, `app/lib/data/repositories/home_read_repository.dart`, `app/lib/data/sync/sync_service.dart`, `pi-extension/src/session/remote_session.ts`
**Story**: `epic-bold-transcript-event-log-store-step-4`

**Current State**:
```dart
static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';
static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

**Target State**:
```dart
final class TranscriptSessionKey {
  final String peerId;
  final String roomId;
  final String sessionId;
  String get durableKey => '$peerId:$roomId:$sessionId';
}

// Event truth:
transcript_events_<peer>__<room>__<session>

// Rebuildable projection cache:
msgs_<peer>__<room>__<session>

// Room reachability/runtime remains room-scoped:
runtime key = '$peerId:$roomId'
```

**Implementation Notes**:
- Use the canonical-session `session_id` for event and message-projection boxes. If canonical-session step 5 is not fully landed at implementation time, isolate the fallback in `_activeTranscriptKeyOrNull` and name it as compatibility-only.
- `sessions_index` may need session-scoped durable transcript rows while `runtime` stays `(peer, room)` because reachability is relay-room state, not transcript identity.
- Old peer+room projection boxes and old session-index rows are abandoned/ignored, not deleted. Re-sync/replay repopulates the new event box and derived projection for the active session.
- Read repositories should open projection boxes through the same `TranscriptSessionKey` or an explicit compatibility overload; avoid spreading loose `(epk, roomId, sessionId)` triples.
- Keep the event store append-only. Projection caches may be diffed, cleared, or rebuilt from the event log.

**Acceptance Criteria**:
- [ ] Two `session_id`s on the same `(peer, room)` do not share transcript events or projected rows.
- [ ] Runtime reachability/working room snapshots remain keyed by `(peer, room)` unless the canonical-session feature explicitly changes them.
- [ ] Old peer+room boxes are preserved for rollback and not destructively migrated.
- [ ] Read repositories document whether they consume session-scoped keys or temporary compatibility keys.
- [ ] Targeted app persistence tests pass.

**Rollback**: switch read/write paths back to peer+room keys. Because old projection boxes were preserved, rollback restores the previous cache behavior; event boxes can remain orphaned until cleanup.

---

### Step 5: Add cross-surface store/replay regression tests
**Priority**: Medium
**Risk**: Low
**Source Lens**: testing integrity / lifecycle convergence
**Files**: `app/test/data/local/transcript_event_store_hive_test.dart`, `app/test/data/sync/sync_service_test.dart`, `pi-extension/src/extension.test.ts`, `.orchestration/contracts/` or equivalent fixture location
**Story**: `epic-bold-transcript-event-log-store-step-5`

**Current State**:
```text
Existing tests prove row-granular message boxes and session_sync behavior, but
no test asserts that the append-only event log is the durable truth while
message rows are disposable projections.
```

**Target State**:
```json
{
  "session_id": "sess-store-fixture",
  "events": [
    { "kind": "user_submitted", "eventId": "local:cli_1", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "user_confirmed", "eventId": "server:cli_1", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "assistant_delta", "eventId": "server:chunk_1", "replyTo": "cli_1", "delta": "done" },
    { "kind": "assistant_done", "eventId": "server:done_1", "replyTo": "cli_1" }
  ],
  "assertions": [
    "duplicate append is ignored",
    "projection rows rebuild after deletion",
    "foreign session_id is ignored",
    "late confirmation suppresses timeout failure in projection"
  ]
}
```

**Implementation Notes**:
- Add app tests for append idempotence, stable order, per-session isolation, projection rebuild after deleting `msgs`, duplicate replay with no churn, and late authoritative confirmation after timeout.
- Add extension tests proving `_buildSessionHistoryMessage` reads from `TranscriptEventLog`, not `_messageBuffer`, while preserving existing wire output.
- Include convergence cases from `.agents/rules/testing-integrity.md`: success, error, abort/cancel, compaction, reconnect replay, shutdown/session replacement, and session switch filtering.
- If shared fixtures are too heavy before generated-protocol lands, mirror the same fixture content in app and extension tests and record the future generated-contract migration note in test comments.

**Acceptance Criteria**:
- [ ] App event-store and sync tests prove event log is append-only/deduped and projections are rebuildable.
- [ ] Pi-extension tests prove session history derives from the event log and preserves current wire behavior.
- [ ] Convergence tests cover false/idle after success, error, cancel/abort, compaction, reconnect, and session replacement.
- [ ] Verification commands are recorded in each story's implementation notes.

**Rollback**: remove the new tests/fixtures only if the event-store implementation is also rolled back. Do not weaken existing row/session-sync tests to make the refactor pass.

## Implementation Order

1. `epic-bold-transcript-event-log-store-step-1` (depends on `epic-bold-transcript-event-log-projection-derive`)
2. `epic-bold-transcript-event-log-store-step-2` (depends on step 1)
3. `epic-bold-transcript-event-log-store-step-3` (depends on step 2)
4. `epic-bold-transcript-event-log-store-step-4` (depends on step 3)
5. `epic-bold-transcript-event-log-store-step-5` (depends on step 4)

## Atomic / rollback notes

No step is intentionally irreversible. The highest-risk step is step 2 because it changes the mobile writer's source of truth; keep it isolated so rollback can restore direct `_upsert`/`_applyHistory` writes while leaving the side-by-side store unused. Step 3 is an internal extension source swap but preserves the outgoing `session_history` wire, so rollback is local to the extension. Step 4 must not delete old boxes; old projection caches are the rollback safety net until release cleanup explicitly removes them.

## Review — advanced to done (2026-06-30)

All 5 child steps `done` (pi-ext `TranscriptEventLog` → app canonical-session re-keying
→ cross-surface store/replay regression tests). Transcript retention is now keyed by
canonical `(peer, room, session_id)` across both pi-ext and app; old peer+room boxes
preserved for rollback. Epic complete — unblocks `transcript-event-log-hydration-replay`
(app arc, steps 1-5).
