---
id: epic-bold-split-pi-extension-index-composition-root-step-1
kind: story
stage: review
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Define the runtime port registry

## Current State
`pi-extension/src/index.ts` stores relay, owner, SDK-session, command, and mesh state as shared module globals:

```ts
let _relay: RelayClient | null = null;
const _activePeers = new Map<string, PlainPeerChannel>();
let _sessionStartedAt: number | null = null;
let _messageBuffer: BufferMsg[] = [];
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort" | "ui"> | null = null;
let _messageApi: AgentMessageApi | null = null;
```

## Target State
Add a type-first boundary file such as `pi-extension/src/extension/ports.ts`:

```ts
export interface RuntimeEpoch {
  readonly id: number;
  readonly disposed: boolean;
  isCurrent(): boolean;
  dispose(): void;
}

export interface RelayTransportPort { /* start/stop/status/room-meta/bridge */ }
export interface OwnerMultiplexerPort { /* attach/detach/broadcast/route */ }
export interface SdkSessionProjectionPort { /* bind ctx, wake/send, history/actions */ }
export interface CommandSurfacePort { /* register commands against runtime */ }

export interface RemotePiRuntimePorts {
  relay: RelayTransportPort;
  owners: OwnerMultiplexerPort;
  session: SdkSessionProjectionPort;
  commands: CommandSurfacePort;
}
```

Use concrete imports from existing protocol/transport types; do not create runtime imports back into `index.ts`.

## Implementation Notes
- This is side-effect free and type-first.
- If `RelayConnectivity` currently only lives in `index.ts`, move the type to a neutral `extension/types.ts`-style module instead of importing runtime `index.ts`.
- Keep room-meta fields aligned with the existing relay/app protocol. No new wire fields.

## Acceptance Criteria
- [ ] Boundary file defines the four module ports and runtime epoch contract.
- [ ] File compiles under strict ESM/NodeNext with `.js` imports where required.
- [ ] No runtime behavior changes.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

## Risk
Medium: type imports can accidentally create cycles if they import runtime `index.ts` values.

## Rollback
Delete the new boundary file and any type-only imports added by this step.

## Implementation Notes
Added the type-first runtime boundary under `pi-extension/src/extension/`:

- `extension/types.ts` exports neutral `RelayConnectivity` so future ports do not import runtime `index.ts`.
- `extension/ports.ts` defines `RuntimeEpoch`, `RuntimeUiPort`, `RelayTransportPort`, `OwnerMultiplexerPort`, `SdkSessionProjectionPort`, `CommandSurfacePort`, and `RemotePiRuntimePorts` using existing protocol and transport types.

The new files are side-effect free and not imported by runtime code yet. Public protocol, CLI output, relay behavior, and extension registration are unchanged.

Verification:
- `corepack pnpm typecheck` from `pi-extension/` — passed.
