---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Introduce the SDK session projection module shell

## Current State
```ts
// pi-extension/src/index.ts
let _pi: ExtensionAPI | null = null;
let _messageApi: AgentMessageApi | null = null;
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort" | "ui"> | null = null;
const _noopCtx = { ui: { notify: () => undefined }, abort: () => undefined };
```

`index.ts` owns SDK capability freshness directly. The future composition root has a `SdkSessionProjectionPort`, but there is no concrete session module to satisfy it.

## Target State
```ts
// pi-extension/src/session/sdk_session_projection.ts
export interface SdkSessionProjectionOutputs {
  broadcast(message: ServerMessage): void;
  sendTo(sender: PeerChannel, message: ServerMessage): void;
  publishRoomMeta(patch: { session_id?: string; model?: string; thinking?: ThinkingLevel; working?: boolean }): void;
  activeOwnerIds(): readonly string[];
  lateAttachTargets(): readonly { peerId: string; channel: PeerChannel }[];
}

export class SdkSessionProjection implements SdkSessionProjectionPort {
  private epoch = 0;
  private commandCtx: ActionCtx | null = null;
  private eventCtx: ActionCtx | null = null;
  private messageApi: AgentMessageApi | null = null;
  private actionApi: FreshActionApi | null = null;

  bindApi(pi: ExtensionAPI): void { this.bindCapabilities(pi); }
  bindCommandContext(ctx: ExtensionCommandContext): void { this.commandCtx = ctx; this.bindCapabilities(ctx); }
  bindSessionContext(ctx: ExtensionContext): void { this.eventCtx = ctx; this.captureRemoteSession(ctx); }
  clearStaleContexts(): void { this.epoch++; this.commandCtx = null; this.eventCtx = null; this.messageApi = null; this.actionApi = null; }
}
```

## Implementation Notes
- Add `pi-extension/src/session/sdk_session_projection.ts` and route only capability-binding helpers through it first.
- If `pi-extension/src/extension/ports.ts` has not landed yet, define a local structural `SdkSessionProjectionPort` type and replace it with the composition-root import when available.
- Keep this step behavior-preserving: no protocol changes, no command-output changes, no relay lifecycle changes.
- Use `unknown` + narrowing for capability detection; do not introduce `any`.

## Acceptance Criteria
- [ ] `SdkSessionProjection` exists under `pi-extension/src/session/` and satisfies the composition-root session port shape.
- [ ] `index.ts` delegates fresh-context/message/action API binding to the module or a thin singleton adapter.
- [ ] Prompt delivery, custom message, compact, cancel, model/thinking, and list-models behavior remains unchanged.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

## Risk
Medium. This adds a new seam around high-risk SDK contexts, but the first step is wrapper-only.

## Rollback
Delete `sdk_session_projection.ts` and restore the context/API binding globals and helper functions in `index.ts`.

## Implementation notes
- Files changed: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/index.ts`.
- Tests added: none (capability-binding shell; existing stale-context tests remain the behavior guard).
- Verification: `corepack pnpm typecheck` passed from `pi-extension/`; `corepack pnpm test` was run and failed on pre-existing/environment UDS lock/listen failures (`EPERM` under `/tmp/claude/...`, cwd lock/leader-election suites). Targeted extension run reached extension tests without new stale-context unhandled errors before the same UDS-gated suites timed out.
- Discrepancies from design: the landed composition-root port is narrower than the drafted shell, so this step binds capabilities through `SdkSessionProjection` while legacy routing remains in `index.ts` until later steps.
- Adjacent issues parked: none.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Implementation commit `dbbc80f` inspected. `SdkSessionProjection` exists under `pi-extension/src/session/`, implements the landed `SdkSessionProjectionPort` shape, uses `unknown` structural narrowing for message API binding, exposes `clearStaleContexts()` with an epoch increment, and drops a stale message API binding when Pi reports `stale after session replacement or reload`. `index.ts` binds the singleton from `bindApi`, `bindCommandContext`, `bindSessionContext`, and clears it on `session_shutdown`; deeper session-id/history ownership remains with legacy `RemoteSessionIssuer` until the next feature step. Verification: `corepack pnpm typecheck` passed. `corepack pnpm test` was attempted and failed in unrelated environment-sensitive UDS suites (`listen EPERM` / cwd-lock / leader-election under `/tmp/claude/...`); targeted extension stale/command smoke was also blocked by one UDS join test, while non-UDS command-registration and stale-shutdown checks passed.
