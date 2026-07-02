---
id: epic-bold-cockpit-workspace-projection-agent-session-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-agent-session
depends_on: [epic-bold-cockpit-workspace-projection-agent-session-step-1, epic-bold-transcript-event-log-projection-derive-step-5]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Feed AgentSession from the transcript event-log projection

## Current State

```dart
// cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart
final out = <TranscriptMessage>[];
final toolsById = <String, TmTool>{};
...
case 'toolCall':
  final tool = TmTool(callId: id, name: block['name'] as String? ?? '?', args: _asStringMap(block['arguments']));
  toolsById[id] = tool;
  out.add(tool);
case 'toolResult':
  final tool = toolsById[raw['toolCallId'] as String? ?? ''];
  if (tool != null) {
    tool.done = true;
    tool.isError = raw['isError'] == true;
    tool.resultText = _contentText(raw['content']);
  }
```

```dart
// cockpit/lib/app/cockpit/ui/session/agent_session.dart
final List<AgentEntry> _entries = <AgentEntry>[];
AssistantTextEntry? _openText;
ThinkingEntry? _openThinking;
final Map<String, ToolEntry> _openTools = <String, ToolEntry>{};

void _appendText(String delta) {
  final open = _openText ??= _add(AssistantTextEntry());
  open.text += delta;
}

void _finishTool(String id, bool isError, String resultText) {
  final entry = _openTools.remove(id);
  if (entry == null) return;
  entry.done = true;
  entry.isError = isError;
  entry.resultText = resultText;
}
```

## Target State

```dart
// AgentSession stores events and asks the transcript sibling projection to derive entries.
final List<CockpitTranscriptEvent> _transcriptEvents = <CockpitTranscriptEvent>[];

void _appendTranscriptEvent(CockpitTranscriptEvent event) {
  _transcriptEvents.add(event);
  _projection = _projection.copyWith(
    transcript: deriveCockpitTranscriptProjection(
      sessionId: _projection.sessionId,
      events: _transcriptEvents,
    ),
  );
}

case RpcTextDelta(:final delta):
  _appendTranscriptEvent(AssistantDeltaReceived(..., delta: delta));
case RpcToolStart(:final toolCallId, :final toolName, :final args):
  _appendTranscriptEvent(ToolRequested(...));
case RpcToolEnd(:final toolCallId, :final isError, :final resultText):
  _appendTranscriptEvent(ToolFinished(...));
```

```dart
// get_messages replay is event replay, not a separate mutable message model.
final events = _dataMapper.transcriptEvents(response['data'], sessionId: sessionId);
return deriveCockpitTranscriptProjection(sessionId: sessionId, events: events).entries;
```

## Implementation Notes

- Consume the `CockpitTranscriptEvent` / `deriveCockpitTranscriptProjection` seam from `epic-bold-transcript-event-log-projection-derive-step-5`; this story removes `AgentSession`'s parallel fold rather than re-defining the event log.
- Replace mutable `TmTool` / `ToolEntry` mutation with immutable projected tool output. If `AgentEntry` remains mutable for UI compatibility, isolate mutation to a final UI adapter (`ProjectedTranscriptMessage -> AgentEntry`) and keep the domain projection immutable.
- Convert `get_messages` to replay transcript events through the same projection used by live `_onEvent`. History load should clear local events for that Pi session and append replay events, then derive once.
- Preserve local optimistic send dedupe: `send()` appends a local user-submitted event and the subsequent `RpcUserMessage` echo confirms or suppresses the duplicate by the transcript sibling's reconcile rule.
- Keep `InfoEntry`, `NoticeEntry`, and `UiRequestEntry` out of the assistant transcript event log unless the transcript sibling explicitly models them; they are Cockpit control/lifecycle entries in the `AgentSessionProjection` presenter.

## Acceptance Criteria

- [ ] Live `RpcTextDelta`, `RpcTextEnd`, `RpcThinkingDelta`, `RpcUserMessage`, `RpcToolStart`, and `RpcToolEnd` are converted to transcript events and projected through the same reducer as `get_messages` replay.
- [ ] `TmTool.done`, `ToolEntry.done`, and open text/thinking/tool buffers are no longer the source of domain truth; any remaining mutable UI object is a compatibility adapter output.
- [ ] `loadHistory()` / `_populateTranscript()` replaces the event-log input for the selected Pi session and re-projects, rather than hand-populating `_entries`.
- [ ] Tests cover get-messages replay, live streaming delta accumulation, tool start/result collapse, local user echo dedupe, and history reload clearing old open buffers.
- [ ] `flutter test` targeted cockpit projection/mapper tests and `flutter analyze` pass, or tooling blockers are recorded.

## Risk

Medium. This touches transcript display behavior, but the public UI output is intended to stay identical. The highest risk is duplicate or missing user/tool rows during the transition from mutable buffers to event replay.

## Rollback

Restore `TranscriptMessage` / `TmTool` mutation and the direct `_entries` / `_openText` / `_openThinking` / `_openTools` fold in `AgentSession`. Keep Step 1's projection contract if it remains unused and side-by-side.

## Implementation

- Removed the `get_messages` projected-message replay path from `AgentSession`; `RpcProcessGateway.getMessages` now returns `CockpitTranscriptEvent`s, and `_populateTranscript()` replaces `_transcriptEvents` for the selected Pi session before deriving the UI transcript once.
- Added `RpcDataMapper.transcriptEvents(...)` so history replay emits the same user/thinking/text/tool request/tool finish events as live RPC handling. The compatibility `transcriptMessages(...)` helper now derives from those events instead of owning a separate fold.
- Kept mutable `AgentEntry`/`ToolEntry` objects as UI compatibility adapter output only; live and replay domain truth comes from `deriveCockpitTranscript(...)`, and `ToolEntry.done` is populated from the immutable projected tool status.
- Preserved optimistic local-send dedupe: `send()` still appends a local submitted event immediately, and the matching `RpcUserMessage` echo is suppressed so the projected UI keeps a single user row.
- Added/updated tests for get-messages event replay, live streaming delta accumulation, tool start/result collapse, optimistic echo dedupe, and history reload clearing prior projected text/tool rows.
- Verification confirms the refactor preserves public transcript UI behavior: `flutter analyze` reports zero issues and full `flutter test` passes.

## Review

Approved (2026-06-30). Independently re-ran: whole-cockpit `flutter analyze` →
No issues found; full `flutter test` → 216/216 (incl. 6 new tests). Commit
`677d999` scoped to cockpit only (agent_session + rpc_data_mapper + the
rpc_process_gateway contract + pi_rpc_process so getMessages returns events +
tests + story .md); no cross-subproject collision. The two extra adapter/
contract files are legitimate (getMessages now returns transcript events).

Single-reducer unification verified directly: `AgentSession` stores
`_transcriptEvents`; both live RPC events (via `_appendTranscriptEvent`) AND
`get_messages` replay (clear + append + derive) flow through the shared
`deriveCockpitTranscript` — no parallel fold. Mutable open buffers
(`_openText`/`_openThinking`/`_openTools`/`TmTool`) fully removed from
agent_session.dart; `AgentEntry`/`ToolEntry` remain only as UI compat adapter
output. Optimistic-send dedupe preserved (test `local optimistic user send
suppresses matching rpc echo`). Tests cover replay, streaming, tool collapse,
dedupe, history-reload clearing.
