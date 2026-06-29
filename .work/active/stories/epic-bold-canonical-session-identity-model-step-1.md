---
id: epic-bold-canonical-session-identity-model-step-1
kind: story
stage: implementing
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
- [ ] Pi-extension has one `RemoteSession`/issuer module and no duplicated session-id derivation.
- [ ] `pair_ok` and room metadata include the current opaque `session_id`.
- [ ] Relay reconnect keeps the same `session_id` for the same Pi SDK session.
- [ ] Session replacement rotates `session_id` and resets `_sessionStartedAt`/message-buffer state consistently.
- [ ] Tests cover stable-across-reconnect and rotates-on-session-replacement.
- [ ] `corepack pnpm typecheck` and targeted Pi-extension tests pass.

## Risk
Medium. The risky edge is incorrectly rotating on reconnect/reload and splitting one real session, or failing to rotate on session replacement and preserving the contamination class.

## Rollback
Revert the identity module and the `pair_ok`/room-meta additions. Existing room-based behavior resumes; app-side validation stories must be reverted in reverse dependency order.
