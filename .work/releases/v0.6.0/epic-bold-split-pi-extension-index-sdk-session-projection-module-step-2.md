---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-sdk-session-projection-module-step-1]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Move RemoteSession identity and transcript snapshot into the module

## Current State
```ts
// pi-extension/src/index.ts
let _sessionStartedAt: number | null = null;
const _remoteSessionIssuer = new RemoteSessionIssuer();
let _messageBuffer: BufferMsg[] = [];

function _captureRemoteSession(ctx: unknown): string {
  const sessionId = _remoteSessionIssuer.capture(ctx);
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, session_id: sessionId };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { session_id: sessionId } });
  }
  return sessionId;
}
```

`RemoteSessionIssuer`, `session_started_at`, transcript history, `pair_ok`, and `session_sync` are still smeared across `index.ts`.

## Target State
```ts
// pi-extension/src/session/sdk_session_projection.ts
export interface SessionHistorySnapshot {
  sessionStartedAt: number;
  sessionId: RemoteSessionId;
  queued: Extract<ServerMessage, { type: "queued_message_state" }>;
  history(inReplyTo: string, limit?: number): Extract<ServerMessage, { type: "session_history" }>;
}

export class SdkSessionProjection implements SdkSessionProjectionPort {
  private readonly issuer = new RemoteSessionIssuer();
  private sessionStartedAt: number | null = null;
  private messageBuffer: BufferMsg[] = [];

  captureRemoteSession(ctx: unknown): RemoteSessionId {
    const sessionId = this.issuer.capture(ctx);
    this.opts.outputs.publishRoomMeta({ session_id: sessionId });
    return sessionId;
  }

  recordMessage(message: unknown): void {
    const m = normalizeBufferMessage(message);
    if (m) this.messageBuffer.push(m);
  }

  buildSessionHistory(inReplyTo: string, limit?: number): Extract<ServerMessage, { type: "session_history" }> {
    return buildSessionHistoryMessage(this.messageBuffer, this.sessionStartedAt, inReplyTo, limit);
  }
}
```

## Implementation Notes
- Keep `session/remote_session.ts` as the canonical identity helper; this story moves the runtime issuer instance into the projection module.
- Move `BufferMsg`, `_mapAgentMessagesToEvents`, `session_sync`, compaction history marker, and successful `session_new` reset ownership into the module.
- Preserve relay stop/start semantics: relay reconnect must not clear `sessionStartedAt` or the transcript buffer; Pi SDK session replacement must reset them.
- Keep `session_id` opaque and sourced from `ctx.sessionManager.getSessionId()` where available.

## Acceptance Criteria
- [ ] `RemoteSessionIssuer`, `sessionStartedAt`, and transcript buffer are private to the projection module.
- [ ] `pair_ok`, room metadata, reconnect hello metadata, and `session_sync` obtain `session_id`/history from the module.
- [ ] Tests prove `session_id` is captured from `ctx.sessionManager.getSessionId()`, preserved across relay reconnect, and recaptured on session replacement.
- [ ] Tests prove history is preserved across relay stop/start and reset only after successful `session_new` / replacement.
- [ ] `corepack pnpm typecheck` and targeted `corepack pnpm test -- remote_session extension` pass from `pi-extension/`.

## Risk
Medium. The public wire shape should not change, but history reset/preservation semantics are subtle and must be guarded by tests.

## Rollback
Move `RemoteSessionIssuer`, `sessionStartedAt`, `messageBuffer`, and history helpers back into `index.ts`; remove the module history API.

## Implementation
- Moved the runtime `RemoteSessionIssuer`, `sessionStartedAt`, transcript event log, delivered-user dedupe map, legacy SDK-message mapping adapter, session history builder, and successful `session_new` reset fan-out into `pi-extension/src/session/sdk_session_projection.ts`; `session/remote_session.ts` remains the canonical identity helper.
- Left `index.ts` as a thin integration layer: `pair_ok`, room metadata/reconnect hello, current-session stamping, `session_sync`, late-attach history, compaction/tool/user transcript recording, and tests delegate through `SdkSessionProjection`.
- Preserved relay stop/start and reconnect behavior by not clearing projection-owned session identity/history in `_goIdle` or `_onRelayClose`; successful app `session_new` now recaptures the fresh SDK session id and resets projection-owned history/clock before broadcasting empty `session_history`.
- Tests added/strengthened in `pi-extension/src/extension.test.ts`: SDK `sessionManager.getSessionId()` capture into `pair_ok`, reconnect preservation of `session_id`/`session_started_at`/history, and `session_new` fresh id recapture plus empty-history reset.
- Verification:
  - `corepack pnpm typecheck`: passed.
  - `corepack pnpm build`: passed.
  - Focused vitest (`corepack pnpm exec vitest run src/extension.test.ts --testNamePattern "known peer reconnect|relay reconnect detaches|successful reconnect preserves session_id|pair_ok captures|session_new uses fresh"`): 4 passed, 150 skipped; the existing listener-count invariant tests were not changed and passed with `toBe(1)`/`toBe(2)` and `toBe(2)`/`toBe(0)`/`toBe(1)`/`toBe(2)`.
  - Required targeted command (`corepack pnpm exec vitest run src/extension.test.ts src/session/remote_session.test.ts`): 154 passed, 4 failed, 0 skipped across both files. All session-projection, `session_id`, history, listener-count, delivery, and `paired` state-transition tests passed. The 4 failures are the known environment/fixture false-alarm class, not session-projection regressions: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`.
- Discrepancies from design: the existing codebase already uses transcript events rather than the story's older `BufferMsg` name, so the projection module owns the transcript event buffer/history API instead of reintroducing `BufferMsg`.

## Review

Approved (2026-06-30) after the corrected re-dispatch. Independently re-ran:
`corepack pnpm typecheck` clean; `corepack pnpm build` clean; **full pi-ext suite
656 passed | 3 skipped | 0 failed (44 files)** — fully green (up from 655 — the
agent's new session tests). The 4 failures the agent reported are genuinely the
environment-flake false-alarm signature (`after a clean reset`, `name-assigned`,
`rename:<name>`, same-name `#2`) — a clean orchestrator re-run shows 0 failures.

### Saga note (this was the 2nd attempt)
The 1st attempt (`ed74036`, reverted) was undone by an ORCHESTRATOR-SIDE error:
the orchestrator had committed a wrong test-fixture alignment (transient dirty-tree
observation) on the prior relay-transport-step-5, and that agent copied the wrong
listener-count values into its new tests. The agent's actual code migration was
CORRECT. This re-dispatch was briefed that the original invariant fixtures are
correct (do not touch `toBe(1)`/`toBe(2)` listener-count assertions) and that the
migration was sound — only the reconnect-preservation test needed fixing.

### Verification of this attempt (commit `de2086f`)
- `SdkSessionProjection` class created with private `issuer`/`sessionStartedAt`/
  `messageBuffer` — no longer `index.ts` globals.
- Relay reconnect preserves session_id/sessionStartedAt/history (not cleared in
  `_goIdle`/`_onRelayClose`); `session_new` recaptures fresh SDK id + resets history.
- The previously-failing `successful reconnect preserves session_id, sessionStartedAt,
  and transcript history` test now PASSES (2× consistent) — reconnect→repair path fixed.
- Existing listener-count invariant tests untouched and passing.
- `pair_ok captures opaque Pi SDK session_id` test passing.
- Commit scoped to pi-ext only (sdk_session_projection.ts + index.ts shrunk ~280
  lines + tests); collision guard held.
