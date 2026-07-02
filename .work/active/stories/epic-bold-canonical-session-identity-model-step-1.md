---
id: epic-bold-canonical-session-identity-model-step-1
kind: story
stage: done
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: []
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 1: Define `RemoteSession` and Pi-extension session-id issuance

## Current State
```ts
// pi-extension/src/index.ts
let _sessionStartedAt: number | null = null;
// `room_id` is derived from (cwd, name) and reused across Pi sessions.
const roomId = roomIdFor(cwd, sessionName);
if (_sessionStartedAt === null) _sessionStartedAt = Date.now();
```

```dart
// app/lib/data/local/boxes.dart
static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

No endpoint owns a canonical `RemoteSession` identity. `room_id`, `session_started_at`, Hive keys, and Cockpit JSONL ids each act like identity in different places.

## Target State
```ts
// pi-extension/src/session/remote_session.ts
export type RemoteSessionId = string;

export interface RemoteSession {
  sessionId: RemoteSessionId; // opaque; never derived from cwd/room/pairing
  peerId: string;             // Pi public key / relay peer id
  roomId: string;             // relay routing projection
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
  return uuid7(); // legacy/test fallback only
}
```

`session_id` is minted by the Pi-extension endpoint from Pi SDK session identity (`ctx.sessionManager.getSessionId()`), with a UUIDv7 fallback only when the SDK id is unavailable in tests/legacy seams. `session_started_at` remains metadata; it is not a validation key. `room_id` remains a relay routing projection and may be reused by future sessions.

## Implementation Notes
- Add a small Pi-extension identity module rather than spreading `_sessionStartedAt` / `roomIdFor` logic further through `index.ts`.
- Re-capture the current `RemoteSession` on `session_start`, `withSession` replacement, and `_cmdStart` bootstrap.
- Preserve the same `session_id` across relay reconnects and `/remote-pi stop` / start cycles for the same Pi SDK session.
- Rotate `session_id` when the Pi SDK session changes (`session_new`, `/new`, `/resume`, `/fork`, `switch_session`, or daemon fresh-session restart).
- Expose `session_id` in `pair_ok` and `room_meta` as the bootstrap value app/cockpit surfaces use for attribution.
- Do not persist fork-specific assumptions into the id. The wire treats it as opaque, which keeps a future patchbay migration free to use its own issuer.

## Acceptance Criteria
- [x] Pi-extension has one `RemoteSession`/issuer module and no duplicated session-id derivation.
- [x] `pair_ok` and room metadata include the current opaque `session_id`.
- [x] Relay reconnect keeps the same `session_id` for the same Pi SDK session.
- [x] Session replacement rotates `session_id` and resets `_sessionStartedAt`/message-buffer state consistently.
- [x] Tests cover stable-across-reconnect and rotates-on-session-replacement.
- [x] `corepack pnpm typecheck` and targeted Pi-extension tests pass.

## Risk
Medium. The risky edge is incorrectly rotating on reconnect/reload and splitting one real session, or failing to rotate on session replacement and preserving the contamination class.

## Rollback
Revert the identity module and the `pair_ok`/room-meta additions. Existing room-based behavior resumes; app-side validation stories must be reverted in reverse dependency order.

## Implementation Notes

Implemented inline by the bold-refactor implement-orchestrator because no subagent dispatcher is exposed in this delegated harness. Added `pi-extension/src/session/remote_session.ts` as the single identity issuer module, deriving `session_id` from `ctx.sessionManager.getSessionId()` when present and falling back to a local UUIDv7 helper for tests/legacy seams. `RemoteSessionIssuer` preserves the id across reconnect/stop-start reads and rotates when a fresh Pi SDK session context is captured.

Wired the current `session_id` into Pi-extension `pair_ok` and `room_meta` hello/update payloads. The relay carries `session_id` as opaque room metadata without routing by it. The mobile protocol parses `session_id` from `pair_ok`, room announcements/snapshots, and room metadata updates so later attribution/hydration stories can consume it.

Verification:
- `cd pi-extension && corepack pnpm typecheck` passed.
- `cd pi-extension && corepack pnpm exec vitest run src/session/remote_session.test.ts` passed (4 tests).
- A broader filtered `extension.test.ts` run exercised pair/session tests but failed 3 existing mesh/relay lifecycle tests unrelated to the new identity assertions; the new targeted identity tests passed.
- `cd relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed.
- `flutter analyze` could not run because `/opt/flutter/bin/cache` is read-only in this environment. Nearest check run: `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/protocol/protocol.dart lib/data/transport/connection_manager.dart`, passed with no issues.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Verified commit `ca9176c`, changed files, and parent identity-model design. Reviewer reran `cd pi-extension && corepack pnpm typecheck`, `cd pi-extension && corepack pnpm exec vitest run src/session/remote_session.test.ts`, `cd relay && cargo fmt --check && cargo test`, `cd relay && cargo clippy -- -D warnings`, and the nearest app analyzer check `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/protocol/protocol.dart lib/data/transport/connection_manager.dart`. Full `cd app && flutter analyze` was attempted but failed before analysis because `/opt/flutter/bin/cache` is read-only.
