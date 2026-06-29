---
id: epic-bold-reachability-contract-state-machine-step-1
kind: story
stage: implementing
tags: [refactor, bold, pi-extension, app, relay]
parent: epic-bold-reachability-contract-state-machine
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Pin the interim canonical Reachability contract artifact

**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / pattern drift
**Files**: `.orchestration/contracts/reachability.json`, `.orchestration/contracts/reachability.md` (optional explanatory companion)

## Current State

The contract exists only as prose and scattered constants:

```ts
// pi-extension/src/index.ts
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
```

```ts
// pi-extension/src/session/mesh_node.ts
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
```

```dart
// app/lib/data/transport/connection_manager.dart
sealed class ConnectionStatus { const ConnectionStatus(); }
class StatusConnecting extends ConnectionStatus { const StatusConnecting(); }
class StatusOnline extends ConnectionStatus { final IChannel channel; const StatusOnline(this.channel); }
class StatusRetrying extends ConnectionStatus { final Duration nextRetry; final int attempt; const StatusRetrying({required this.nextRetry, required this.attempt}); }
class StatusOffline extends ConnectionStatus { final String reason; final bool canRetry; const StatusOffline({required this.reason, this.canRetry = true}); }
const _kBackoff = [1, 2, 5, 10, 30];
```

## Target State

Create an interim repo-level contract artifact that generated-protocol can absorb later:

```json
{
  "name": "Reachability",
  "version": 1,
  "states": ["connecting", "online", "degraded", "offline", "retrying"],
  "displayNames": {
    "connecting": "Connecting",
    "online": "Online",
    "degraded": "Degraded",
    "offline": "Offline",
    "retrying": "Retrying"
  },
  "backoffSeconds": [1, 2, 5, 10, 30],
  "heartbeat": {
    "appProtocolPingSeconds": 25,
    "relayWsPingSeconds": 25,
    "extensionLivenessCheckSeconds": 20,
    "extensionLivenessTimeoutSeconds": 70,
    "degradedAfterMissedAppPongs": 3
  },
  "transitions": [
    { "from": "offline", "event": "connect_requested", "to": "connecting" },
    { "from": "connecting", "event": "connect_succeeded", "to": "online" },
    { "from": "connecting", "event": "connect_failed_retryable", "to": "retrying" },
    { "from": "connecting", "event": "connect_cancelled", "to": "offline" },
    { "from": "online", "event": "app_protocol_silence", "to": "degraded" },
    { "from": "online", "event": "transport_closed", "to": "retrying" },
    { "from": "online", "event": "stop_requested", "to": "offline" },
    { "from": "degraded", "event": "fresh_app_frame_or_room_snapshot", "to": "online" },
    { "from": "degraded", "event": "transport_closed", "to": "retrying" },
    { "from": "degraded", "event": "stop_requested", "to": "offline" },
    { "from": "retrying", "event": "retry_timer_fired", "to": "connecting" },
    { "from": "retrying", "event": "stop_requested", "to": "offline" },
    { "from": "retrying", "event": "retry_disabled", "to": "offline" }
  ]
}
```

Optional markdown companion should state: this file is the temporary source until `epic-bold-generated-protocol` moves Reachability into the canonical schema; language modules are projections and must not invent states/backoffs.

## Implementation Notes

- Use lower-case wire/code identifiers in the artifact; UI/display labels derive from `displayNames`.
- Do not change production behavior in this story.
- Preserve current heartbeat timings: app protocol ping 25s, relay WS ping 25s, extension liveness check 20s, extension timeout 70s.
- Treat `degraded` as “transport is up but app↔Pi room liveness is stale”; this matches existing `_markActiveRoomOffline()` behavior without forcing the relay WS down.
- Rationale: a small canonical artifact avoids blocking future patchbay/generated-schema migration while giving the app/pi/relay projections a single reviewable contract today.

## Acceptance Criteria

- [ ] `.orchestration/contracts/reachability.json` contains exactly the five states: `connecting`, `online`, `degraded`, `offline`, `retrying`.
- [ ] The only retry schedule in the artifact is `[1, 2, 5, 10, 30]` seconds.
- [ ] The artifact records the 25s/25s/20s/70s heartbeat/liveness timings.
- [ ] The transition table includes the Online → Degraded and Degraded → Online recovery paths.
- [ ] No production adapter imports or behavior change in this step.

## Risk

Low. This adds an inert contract artifact. The main risk is future drift if language modules do not test against it.

## Rollback

Delete the new reachability contract artifact(s). No production code depends on them after this step.
