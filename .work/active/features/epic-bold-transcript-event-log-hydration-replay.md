---
id: epic-bold-transcript-event-log-hydration-replay
kind: feature
stage: done
tags: [refactor, bold, app, pi-extension, cockpit]
parent: epic-bold-transcript-event-log
depends_on: [epic-bold-transcript-event-log-store]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Transcript event log — hydration as replay, not replace

## Brief
`_applyHistory` (`app/lib/data/sync/sync_service.dart:671-760`) stops being a
replace operation and becomes a replay over the event log. A foreign
`session_history` can't overwrite the local transcript because the projection is
recomputed from the local event log — the direct structural fix for "session B
showed only session A's stray turn and none of its own." Session-scoped: a
foreign `session_id` is already rejected by
`epic-bold-canonical-session-app-attribution-hydration`; this feature makes the
box itself tamper-proof by derivation.

## Epic context
- Parent epic: `epic-bold-transcript-event-log`
- Position: consumer of `store`.

## Foundation references
- Evidence: `app/lib/data/sync/sync_service.dart:671-760`, `:762-...`
  (`_convertHistory`).

<!-- /agile-workflow:refactor-design pins the replay semantics. -->

## Design decisions

- **Refactor-lane judgment**: keep this in the bold `[refactor]` lane by explicit operator/autopilot direction. The public wire remains `session_history` / Cockpit `get_messages`; the internal hydration semantics change from destructive replacement to event replay. Behavior-changing fail-closed session attribution is owned by canonical-session; this item assumes the active session id exists and logs a compatibility shim only at adapter boundaries.
- **Replay source**: `session_history` and Cockpit `get_messages` are authoritative snapshots of server/Pi transcript facts, but they are not deletion commands. Hydration converts them into deterministic `TranscriptEvent`s, appends only unseen `eventId`s, and re-derives the projection from the event log.
- **No replace rule**: `_applyHistory` must not compute a `desired` message-box list and delete rows absent from a replay. Projection boxes are rebuildable caches, but deletion/rebuild is driven by the local event log, not by a single replay batch replacing truth.
- **Deterministic event ids**: server replay ids are stable across reconnects and request ids: `server:<session_id>:<history-type>:<stable-key>:<ts>`. The stable key is `id` for user events, `in_reply_to`/message id for assistant events, `tool_call_id` for tool events, and `ts` for compaction when no better id exists. Duplicate replay skips rather than rewrites.
- **Session boundary**: `session_id` is opaque and compared for equality only. `session_started_at` remains a stale-boundary/high-water guard while canonical-session rollout is in flight; it does not identify the transcript and does not authorize replacing the active projection.
- **Empty/truncated replay**: empty history appends no events; it does not clear an existing same-session log. A new session clears by rotating `session_id` (and by explicit action-local cleanup during the transition), not by interpreting an empty replay as destructive state. `truncated: true` means the replay omitted older facts, so it must never delete local earlier events.
- **Patchbay posture**: replay adapters live at app/pi-extension/cockpit edges and feed the canonical event algebra. No Hive box naming, relay room meaning, cwd hash, or Pi SDK message shape becomes the domain contract; patchbay can replace the adapters without changing projection semantics.
- **Dispatch rationale**: direct-read only. The feature is bounded to the current hydration code, protocol replay types, and landed sibling designs. No `.agents/skills/refactor-conventions/` or pattern catalog exists. The scan covered code smells (destructive `_applyHistory`), missing abstractions (history-to-event adapter), naming drift (`SessionHistoryEvent` vs `TranscriptEvent`), and dead-weight replacement comments.

## Refactor Overview

The current hydration path treats one `session_history` response as the whole active transcript. `SyncService._applyHistory` converts history events to `MessageRecord`s, preserves only local pending user rows, then deletes/puts Hive rows until the `msgs` box equals that batch. This made reconnect idempotent after the plan/32 diffing fix, but the core bug remains: an accepted foreign or stale history can still overwrite the active message projection.

The landed siblings define the safe shape:

- `epic-bold-transcript-event-log-projection-derive` pins `TranscriptEvent` as the canonical input and states the replay rule: `session_history` / `get_messages` become deterministic events, append/dedupe, and do not replace projections.
- `epic-bold-transcript-event-log-store` pins the append-only app event store and pi-extension `TranscriptEventLog`; `MessageRecord` boxes are disposable projections.
- `epic-bold-canonical-session-identity-model` pins `session_id` as opaque and endpoint-owned; hydration is scoped by equality, not by relay room or timestamp meaning.

This feature completes the transcript epic by making every hydration source use that contract. The app gets a pure `SessionHistory` replay adapter plus a `SyncService` path that appends/dedupes into the store and reprojects. The pi-extension emits replay-compatible deterministic history from its event log and no longer relies on app-side replacement to reset state. Cockpit's `get_messages` mapper follows the same event replay/projection rule so it does not remain a parallel destructive hydration surface.

Cycle check: `.work/bin/work-view` is absent in this checkout, so I ran a manual frontmatter graph check over active items plus the planned story edges. The planned chain is one-way: `epic-bold-transcript-event-log-store` → step 1 → step 2 → step 3 → step 4 → step 5. No existing item depends on these new story ids and no story depends on this feature or on a downstream hydration item, so no cycle is introduced.

## Refactor Steps

### Step 1: Add deterministic app `SessionHistory` replay adapter
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `app/lib/data/sync/session_history_replay.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/domain/transcript/transcript_event.dart`, `app/test/data/sync/session_history_replay_test.dart`
**Story**: `epic-bold-transcript-event-log-hydration-replay-step-1`

**Current State**:
```dart
// app/lib/data/sync/sync_service.dart
case SessionHistory():
  // ignore: discarded_futures
  _applyHistory(msg);

List<MessageRecord> _convertHistory(List<SessionHistoryEvent> events) {
  final out = <MessageRecord>[];
  // Converts directly to mutable projection rows.
}
```

**Target State**:
```dart
// app/lib/data/sync/session_history_replay.dart
List<TranscriptEvent> sessionHistoryToTranscriptEvents({
  required SessionHistory history,
  required String sessionId,
}) => [
  for (final event in history.events)
    switch (event) {
      UserInputEvt() => UserMessageConfirmed(
          eventId: serverReplayEventId(sessionId, 'user_input', event.id, event.ts),
          sessionId: sessionId,
          ts: DateTime.fromMillisecondsSinceEpoch(event.ts),
          clientMessageId: event.id,
          text: event.text,
          image: event.image == null ? null : MessageImage(data: event.image!.data, mime: event.image!.mime),
        ),
      AgentMessageEvt() => AssistantMessageCommitted(
          eventId: serverReplayEventId(sessionId, 'agent_message', event.inReplyTo, event.ts),
          sessionId: sessionId,
          ts: DateTime.fromMillisecondsSinceEpoch(event.ts),
          messageId: 'server:${event.inReplyTo}:${event.ts}',
          replyTo: event.inReplyTo,
          text: event.text,
        ),
      ToolRequestEvt() => ToolRequested(...),
      ToolResultEvt() => ToolFinished(...),
      CompactionEvt() => CompactionRecorded(...),
    },
];
```

**Implementation Notes**:
- Keep the adapter in `data/sync`: protocol DTOs are infrastructure; domain projection consumes only `TranscriptEvent`.
- `serverReplayEventId` must ignore `in_reply_to` request ids and use stable event facts, so identical replay batches dedupe.
- Convert `UserInputEvt` to `UserMessageConfirmed`, not `UserMessageSubmitted`; the server is authoritative and confirms any matching optimistic event.
- Preserve image, tool result/error, compaction token count, and assistant usage if present on the wire.
- Fail fast on missing active `session_id`; use a narrowly named compatibility shim only while canonical-session implementation is in flight.

**Acceptance Criteria**:
- [ ] Adapter returns only `TranscriptEvent` values and imports no Hive/UI/ViewModel code.
- [ ] Identical `SessionHistory` payloads produce identical `eventId`s regardless of request `in_reply_to`.
- [ ] `UserInputEvt` confirms matching optimistic messages by client id.
- [ ] Tests cover user/image, assistant, tool request/result, compaction, duplicate id stability, and unknown/unsupported event handling.
- [ ] Targeted app test passes: `flutter test test/data/sync/session_history_replay_test.dart`.

**Rollback**: remove the adapter/tests. Existing `_convertHistory` row conversion remains until step 2 swaps callers.

---

### Step 2: Replace `_applyHistory` destructive reconcile with append/dedupe replay
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle convergence
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/local/records/message_record.dart`, `app/lib/domain/contracts/transcript_event_store.dart`, `app/test/data/sync/sync_service_test.dart`
**Story**: `epic-bold-transcript-event-log-hydration-replay-step-2`

**Current State**:
```dart
final rows = _convertHistory(h.events);
final historyIds = {for (final r in rows) _key(r.role, r.id)};
final preserved = <MessageRecord>[];
for (final v in box.values) {
  final r = MessageRecord.fromJson(_coerce(v));
  if (r.role == MsgRole.user && r.pending && !historyIds.contains(_key(r.role, r.id))) {
    preserved.add(r);
  }
}
final desired = <MessageRecord>[
  for (var i = 0; i < rows.length; i++) rows[i].copyWith(seq: i),
  for (var j = 0; j < preserved.length; j++) preserved[j].copyWith(seq: rows.length + j),
];
// Deletes any box key beyond desired.length and rewrites mismatched rows.
```

**Target State**:
```dart
Future<void> _replayHistory(SessionHistory history) async {
  final key = _activeTranscriptKeyOrNull();
  if (key == null) return;
  if (_isStaleHistory(history.sessionStartedAt)) return;

  final replayEvents = sessionHistoryToTranscriptEvents(
    history: history,
    sessionId: key.sessionId,
  );
  await _appendTranscriptEventsAndProject(key, replayEvents);
  _acceptHistoryBoundary(history.sessionStartedAt);
}
```

```dart
Future<void> _appendTranscriptEventsAndProject(
  TranscriptSessionKey key,
  Iterable<TranscriptEvent> events,
) async {
  final result = await _eventStore.appendAll(key, events);
  if (result.appended == 0) return;
  final projection = deriveTranscriptProjection(
    sessionId: key.sessionId,
    events: await _eventStore.readSession(key),
  );
  await _rewriteMessageProjectionFromLog(key, projection);
}
```

**Implementation Notes**:
- `_applyHistory` may remain as a compatibility wrapper named `_replayHistory` during the transition, but it must not call `_convertHistory` or delete rows because a replay omitted them.
- Keep `_writeChain` around event append + projection cache writes; replay is still a serialized persistence operation.
- Update `_acceptedSessionStartedAtHighWater` only after accepting the batch. It rejects stale session boundaries but is not a transcript identity.
- `truncated: true` and empty batches append fewer/no events; they never delete earlier local log entries.
- Pending timeouts become `UserMessageFailed` events from the store sibling; a later `UserMessageConfirmed` from replay wins in projection and suppresses stale failure UI.

**Acceptance Criteria**:
- [ ] `SessionHistory` handling appends/dedupes events in `TranscriptEventStore`; `MessageRecord` rows are only a projection cache.
- [ ] A replay missing an existing local event does not delete that event from the event log or active projection.
- [ ] Duplicate replay appends zero events and emits no message-box churn.
- [ ] Late authoritative replay of a timed-out message confirms it and suppresses the timeout failure projection.
- [ ] Stale `session_started_at` is rejected before store append; same-boundary replay is accepted/idempotent.
- [ ] Targeted app sync tests pass: `flutter test test/data/sync/sync_service_test.dart`.

**Rollback**: restore `_applyHistory` to `_convertHistory` + diffed row reconcile. The event store/adapter from step 1 can remain unused.

---

### Step 3: Make pi-extension `session_history` replay-compatible and independent of app replacement
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / boundary clarity
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_event_log.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/protocol/types.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-transcript-event-log-hydration-replay-step-3`

**Current State**:
```ts
function _buildSessionHistoryMessage(inReplyTo: string, limit: number | undefined) {
  // Mirror semantics: always return the last N events. App SUBSTITUTES its
  // local cache with this response — no delta/since_ts logic.
  const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
  return { type: 'session_history', in_reply_to: inReplyTo, events: slice, eos: true, truncated };
}

function _resetSessionForNew(inReplyTo: string): void {
  _messageBuffer = [];
  _broadcastToActive({ type: 'session_history', in_reply_to: inReplyTo, events: [] });
}
```

**Target State**:
```ts
function _buildSessionHistoryMessage(
  inReplyTo: string,
  limit: number | undefined,
): Extract<ServerMessage, { type: 'session_history' }> {
  const projection = projectSessionHistory({
    sessionId: _remoteSessionIssuer.current(),
    events: _transcriptLog.forSession(_remoteSessionIssuer.current()),
    limit: Math.min(limit ?? _getSyncLimit(), _getSyncLimit()),
  });
  return {
    type: 'session_history',
    in_reply_to: inReplyTo,
    session_started_at: _sessionStartedAt ?? 0,
    events: projection.events,
    eos: true,
    truncated: projection.truncated,
  };
}
```

**Implementation Notes**:
- Remove comments and tests that rely on the app substituting its cache wholesale; `session_history` is a replay payload.
- Build history from the store sibling's `TranscriptEventLog` / projection adapter when present. If `_messageBuffer` is still in a legacy seam, its only job is to feed transcript events; it must not own replay semantics.
- Keep outgoing wire shape stable until generated-protocol/canonical-session changes land.
- `_resetSessionForNew` rotates/resets the extension event log for the new session and may broadcast an empty history as a compatibility notification, but correctness must not depend on app-side destructive replacement.
- Ensure per-request `session_sync` still goes only to the requesting owner; broadcast remains only for global new-session compatibility.

**Acceptance Criteria**:
- [ ] `session_history` output is derived from session-scoped `TranscriptEvent`s, not from mutable projection rows or app replacement assumptions.
- [ ] Identical server facts produce stable history events across reconnects and different `session_sync` request ids.
- [ ] Empty history on new session does not have to delete old app rows; session rotation/event-log reset provides the boundary.
- [ ] Existing limit/truncated, image replay, compaction replay, tool result stringification, and late-attach sync tests remain green.
- [ ] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

**Rollback**: restore `_messageBuffer` / `_mapAgentMessagesToEvents` as the direct `session_history` source and the old replacement-oriented comments/tests. App replay work remains local.

---

### Step 4: Convert Cockpit `get_messages` hydration to event replay projection
**Priority**: Medium
**Risk**: Medium
**Source Lens**: pattern drift / missing abstraction
**Files**: `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/domain/entities/transcript_event.dart`, `cockpit/lib/app/cockpit/domain/entities/transcript_message.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/test/`
**Story**: `epic-bold-transcript-event-log-hydration-replay-step-4`

**Current State**:
```dart
// cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart
List<TranscriptMessage> transcriptMessages(Object? data) {
  // Maps get_messages {messages:[AgentMessage]} directly to mutable
  // TranscriptMessage rows; TmTool is later completed by mutation.
}

// AgentSession._populateTranscript clears _entries and loads mapped rows.
```

**Target State**:
```dart
final events = getMessagesToTranscriptEvents(
  data,
  sessionId: activeSessionIdOrLocalPath,
);
_transcriptLog.appendAll(events);
final projection = deriveCockpitTranscriptProjection(
  sessionId: activeSessionIdOrLocalPath,
  events: _transcriptLog.forSession(activeSessionIdOrLocalPath),
);
_entries
  ..clear()
  ..addAll(projection.entries.map(toAgentEntry));
```

**Implementation Notes**:
- This keeps Cockpit local-only. It does not add relay pairing, mobile routing, or remote session authority.
- `get_messages` is a server/Pi snapshot source like `session_history`; convert it to deterministic events and dedupe by event id before projecting.
- Clearing `_entries` is acceptable only as clearing a derived UI list immediately before repopulating from the event log; it must not clear transcript truth.
- Retire `TmTool` mutation as the hydration truth. A local reducer can mutate while deriving immutable projection output, but published domain messages should be value objects.
- Use the same event kind names as app/pi-extension to keep generated-protocol/patchbay migration straightforward.

**Acceptance Criteria**:
- [ ] Cockpit `get_messages` and live `_onEvent` append to the same local transcript event log or reducer seam.
- [ ] Duplicate `get_messages` hydration is idempotent and does not duplicate entries.
- [ ] Tool call/result hydration produces one projected tool entry without mutating a persisted domain object after publish.
- [ ] Session/path switch filters old events out of the active projection.
- [ ] Targeted Cockpit mapper/projection tests pass, or `flutter test` blockers are recorded.

**Rollback**: restore direct `TranscriptMessage` mapping and `_entries` population. App/pi-extension replay semantics remain unaffected.

---

### Step 5: Add replay regression fixtures and remove replacement assumptions
**Priority**: Medium
**Risk**: Low
**Source Lens**: testing integrity / dead weight
**Files**: `app/test/data/sync/sync_service_test.dart`, `app/test/domain/transcript/`, `pi-extension/src/extension.test.ts`, `cockpit/test/`, `.orchestration/contracts/` or equivalent fixture location
**Story**: `epic-bold-transcript-event-log-hydration-replay-step-5`

**Current State**:
```text
Tests prove identical SessionHistory causes no Hive churn, but the accepted
history batch is still treated as the desired active message box. Comments in
pi-extension still say the app substitutes its cache wholesale.
```

**Target State**:
```json
{
  "name": "reconnect-history-is-replay-not-replace",
  "session_id": "sess-replay-fixture",
  "local_events": [
    { "kind": "user_submitted", "eventId": "local:cli_1", "clientMessageId": "cli_1", "text": "still visible" }
  ],
  "server_replay": [
    { "type": "user_input", "ts": 10, "id": "srv_1", "text": "authoritative older row" }
  ],
  "assertions": [
    "server replay appends deterministic events",
    "local event remains visible",
    "duplicate replay appends zero events",
    "foreign session is ignored before projection",
    "truncated or empty replay does not delete local log"
  ]
}
```

**Implementation Notes**:
- Add regression tests from the contract outward: deterministic replay adapter, store append/dedupe, projection after replay, and visible message rows.
- Cover lifecycle convergence from `.agents/rules/testing-integrity.md`: success, error, abort/cancel, compaction, reconnect replay, shutdown/session replacement, and session switch filtering.
- Replace code comments that describe `session_history` as substitution with comments that describe append/dedupe replay.
- If shared fixtures are too heavy before generated-protocol lands, mirror the same fixture content in app/pi-extension/cockpit tests and mark it as future generated-contract coverage.

**Acceptance Criteria**:
- [ ] A regression proves replay does not delete local events absent from the server batch.
- [ ] A regression proves duplicate replay is idempotent at the event store and projection cache.
- [ ] A regression proves empty/truncated replay is non-destructive.
- [ ] A regression proves foreign-session replay is ignored before touching event log, projection rows, streaming, or working state.
- [ ] Replacement-oriented comments/tests are removed or rewritten to the replay model.
- [ ] Verification commands for app, pi-extension, and Cockpit targeted tests are recorded in story implementation notes.

**Rollback**: remove the new replay fixtures/tests only if the replay implementation is rolled back. Do not weaken existing session-sync, pending-send, or compaction tests.

## Implementation Order

1. `epic-bold-transcript-event-log-hydration-replay-step-1` (depends on `epic-bold-transcript-event-log-store`)
2. `epic-bold-transcript-event-log-hydration-replay-step-2` (depends on step 1)
3. `epic-bold-transcript-event-log-hydration-replay-step-3` (depends on step 2)
4. `epic-bold-transcript-event-log-hydration-replay-step-4` (depends on step 3)
5. `epic-bold-transcript-event-log-hydration-replay-step-5` (depends on step 4)

## Atomic / rollback notes

No step is intentionally irreversible. Step 2 is the risky app switchover: keep it isolated so rollback can restore the existing diffed `_applyHistory` replacement path while leaving the event adapter/store unused. Step 3 preserves the current `session_history` wire shape and is rollback-local to the extension. Step 4 is Cockpit-local. The replay contract intentionally avoids destructive migration; old projection boxes and existing session-sync behavior remain rollback safety nets until a later cleanup removes them.

## Review — advanced to done (2026-06-30)

All 5 child steps `done` (app deterministic replay adapter → app append/dedupe replay
→ pi-ext session_history replay-compatibility → cockpit transcript hydration seam →
cross-surface regression fixtures). Transcript hydration is now replay-not-replace
across app/pi-ext/cockpit, keyed by canonical session, with shared contract fixtures
proving non-destructive/idempotent/session-isolated replay. Epic complete.
