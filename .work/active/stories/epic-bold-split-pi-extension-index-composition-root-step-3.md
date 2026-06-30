---
id: epic-bold-split-pi-extension-index-composition-root-step-3
kind: story
stage: review
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: [epic-bold-split-pi-extension-index-composition-root-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 3: Build legacy adapters for the four future modules

## Current State
Free functions in `index.ts` mutate shared globals directly:

```ts
function _broadcastToActive(msg: ServerMessage): void { /* _activePeers */ }
function _publishWorking(working: boolean): void { /* _myRoomMeta + _relay */ }
function _attachBridgeIfReady(): void { /* _meshNode + _relay + _cachedEd25519 */ }
function _routeClientMessageFrom(sender: PlainPeerChannel, msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void { /* many globals */ }
```

## Target State
Create a legacy adapter layer that satisfies the new ports while still delegating to current `index.ts` helper bodies:

```ts
// pi-extension/src/extension/legacy_ports.ts
export function createLegacyIndexPorts(deps: LegacyIndexDeps): RemotePiRuntimePorts {
  return {
    relay: createLegacyRelayTransport(deps),
    owners: createLegacyOwnerMultiplexer(deps),
    session: createLegacySdkSessionProjection(deps),
    commands: createLegacyCommandSurface(deps),
  };
}
```

```ts
// pi-extension/src/index.ts
function createIndexDeps(): LegacyIndexDeps {
  return {
    relay: () => _relay,
    setRelay: (relay) => { _relay = relay; },
    activePeers: _activePeers,
    broadcastToActive: _broadcastToActive,
    routeClientMessageFrom: _routeClientMessageFrom,
    publishWorking: _publishWorking,
    cmdRoot: _cmdRoot,
    cmdStart: _cmdStart,
    cmdStop: _cmdStop,
    cmdPair: _cmdPair,
  };
}
```

## Implementation Notes
- Wrapper-only: do not move large bodies yet.
- `legacy_ports.ts` receives callbacks/state accessors from `index.ts`; it must not import mutable god-file globals directly.
- Group dependencies by future module ownership so sibling features can replace one port at a time.
- Preserve current `unknown` + narrow behavior for inbound JSON; no validation semantics change.

## Acceptance Criteria
- [ ] Four legacy adapters satisfy `RemotePiRuntimePorts`.
- [ ] Adapter dependency object is the only place composition-root wiring knows today's god-file globals.
- [ ] Pairing, reconnect, session sync, app actions, and commands still route through existing implementations.
- [ ] `corepack pnpm typecheck` passes.

## Risk
High: accidental circular imports or wrapper omissions can drop command/app paths.

## Rollback
Inline adapter wiring back into `index.ts` and remove `legacy_ports.ts`; no protocol or module internals should need rollback.

## Implementation notes
- Files changed: `pi-extension/src/extension/legacy_ports.ts`.
- Tests added: none; this is a type-level wrapper seam.
- Discrepancies from design: the existing `index.ts` still contains legacy globals and has not yet been rewired through the new adapter in this story; the adapter seam is grouped by future module ownership so sibling extraction stories can replace one port at a time without importing god-file globals.
- Adjacent issues parked: none.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- `pi-extension/src/index.ts:1405`: the default extension factory still owns the inline god-file wiring and never imports or calls `createLegacyIndexPorts` / constructs a `LegacyIndexDeps` object (repo grep found no `createLegacyIndexPorts` or `LegacyIndexDeps` usage outside `legacy_ports.ts`). This fails the acceptance criterion that the adapter dependency object is the composition-root wiring point for today's globals; the new adapters exist only as an unused type-level seam.
- Acceptance criteria check: four adapters satisfy `RemotePiRuntimePorts` — pass by `legacy_ports.ts:63` and typecheck; dependency object as the only composition-root wiring point for god-file globals — fail because no concrete index/composition-root wiring exists; pairing/reconnect/session sync/app actions/commands still route through existing implementations — pass only because runtime behavior is unchanged and the adapters are unused; `corepack pnpm typecheck` — pass.

**Verification run**:
- `cd /home/agent/forks/remote_pi/pi-extension && corepack pnpm typecheck` — passed (`tsc --noEmit`; pnpm warned about unreadable `/home/agent/.npmrc` and ignored legacy package `pnpm` field).
- `cd /home/agent/forks/remote_pi/pi-extension && corepack pnpm test` — failed, apparently pre-existing/environmental UDS issues: 5 files failed, 98 tests failed, 522 passed, 3 skipped; representative failures are `listen EPERM` on `/tmp/claude/.../supervisor.sock`, cwd-lock first-acquire expectations false, and leader-election failures under `/tmp/claude/.../broker.sock`.
- `cd /home/agent/forks/remote_pi/pi-extension && corepack pnpm build` — passed (`tsc`; same pnpm warnings).

## Implementation notes (rework 2026-06-30)
- Files changed: `pi-extension/src/index.ts`, `.work/active/stories/epic-bold-split-pi-extension-index-composition-root-step-3.md`.
- What changed: imported `createLegacyIndexPorts` and `LegacyIndexDeps` into the default extension factory, constructed `createIndexDeps()` as the composition-root dependency object for today's index globals, and registered the existing command surface through the legacy runtime ports. The current inline Pi hook bodies remain in place for the follow-on routing story, but SDK binding and command-surface registration now pass through the adapter dependency object instead of the ad hoc `legacyCommandSurfaceRuntime()` shim.
- Discrepancies from design: no change to `legacy_ports.ts`; its adapters already existed and this rework wires them from `index.ts`. The relay/owner/session adapter callbacks are wrapper-only and delegate to current helpers/state; public protocol, CLI output, pairing, reconnect, session sync, and app action behavior are intended unchanged.
- Verification:
  - `cd /home/agent/projects/remote_pi/pi-extension && corepack pnpm typecheck` — passed (`tsc --noEmit`; harmless `/home/agent/.npmrc` EACCES and ignored `pnpm` field warnings).
  - With sandbox cache env (`PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store`, `npm_config_cache=/home/agent/projects/remote_pi/.npm-cache`, `XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache`): `corepack pnpm exec vitest run src/extension/composition_root.test.ts src/session/turn_state.test.ts src/session/session_gate.test.ts src/protocol/session_scope.test.ts` — passed (4 files, 22 tests).
  - Extra probe: `corepack pnpm exec vitest run src/extension.test.ts -t "app session_new recaptures fresh message API|cancel uses freshest session_start ctx"` failed with the known current-head session-gate expectation failures; verified by reverse-applying this rework patch and re-running the same command, which failed identically before these changes.
- Adjacent issues parked: none.
