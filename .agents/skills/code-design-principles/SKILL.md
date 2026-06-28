---
name: code-design-principles
description: Agent-neutral code design and implementation principles for Remote Pi. Load when designing modules, defining boundaries, implementing features, fixing bugs, reviewing architecture, or applying refactors across pi-extension, app, relay, cockpit, or site.
updated: 2026-06-28
---

# Code Design Principles

These principles are adapted from the SNC/platform design discipline but are intentionally agent-neutral and project-neutral enough for every Remote Pi subproject.

## When to load

Load before:

- designing a new module, feature, boundary, protocol shape, or state machine;
- implementing non-trivial code;
- reviewing architecture or lifecycle behavior;
- refactoring across files/layers;
- changing protocol, persistence, daemon, relay, mesh, or app state semantics.

Also read `.agents/rules/code-design.md`; this skill carries the longer examples and checklist.

## 1. Ports & Adapters

Core logic defines what it needs; infrastructure implements it. Dependencies point inward.

**Design move:** identify external dependencies first: network, filesystem, keyring, clock, randomness, process spawn, database/storage, platform APIs, UI framework, and Pi SDK contexts. Define a port/interface at the layer that owns the use case, then inject an adapter at the composition root.

**TypeScript sketch:**

```ts
export interface PeerStore {
  list(): Promise<PeerRecord[]>;
  save(peer: PeerRecord): Promise<void>;
}

export async function pairDevice(store: PeerStore, payload: PairPayload) {
  const peer = parsePairPayload(payload);
  await store.save(peer);
  return peer;
}
```

**Dart sketch:**

```dart
abstract interface class SessionRepository {
  Future<Result<List<Session>, SessionFailure>> listSessions();
}

final class ListSessionsUseCase {
  ListSessionsUseCase(this._repository);
  final SessionRepository _repository;

  Future<Result<List<Session>, SessionFailure>> call() => _repository.listSessions();
}
```

**Rust sketch:**

```rust
pub trait RateLimiter {
    fn check(&self, peer_id: &PeerId) -> Result<(), RateLimitError>;
}

pub async fn route_message<L: RateLimiter>(limiter: &L, msg: Message) -> Result<()> {
    limiter.check(&msg.peer_id)?;
    // route opaque payload
    Ok(())
}
```

Checklist:

- [ ] Core/domain modules do not import concrete infrastructure.
- [ ] Adapters are wired in one composition boundary.
- [ ] Tests can supply fakes without patching global singletons.

## 2. Single Source of Truth

Variant sets should live in one typed registry/schema, with types, validation, dispatch, display, and tests derived from it.

Good candidates in Remote Pi:

- protocol message names;
- app action names;
- daemon states;
- `room_meta` fields;
- relay auth phases;
- route names and quick actions;
- state-machine states for connection/working/error.

**TypeScript pattern:**

```ts
export const ACTION_HANDLERS = {
  session_compact: handleSessionCompact,
  session_new: handleSessionNew,
  model_set: handleModelSet,
  thinking_set: handleThinkingSet,
} as const;

export type ActionName = keyof typeof ACTION_HANDLERS;
export const ACTION_NAMES = Object.keys(ACTION_HANDLERS) as ActionName[];
```

Avoid separate hand-written unions, switch statements, and validators that each repeat the same set.

Checklist:

- [ ] A new variant is added in one authoritative place.
- [ ] Validators and dispatchers derive from the registry/schema.
- [ ] Tests fail when a variant lacks a handler or label.

## 3. Generated or Inferred Contracts

When two systems share a boundary, one source should own the contract.

Preferred shapes:

- TypeScript: infer unions/types from const registries, schema validators, or generated wire definitions.
- Dart: generate or centrally define DTOs; UI state should not become a second protocol model.
- Rust: Serde structs/enums are the parse boundary; business logic should not operate on raw JSON maps.
- Cross-language protocol: update every consumer in one change and add compatibility tests/smoke steps.

Checklist:

- [ ] There is one named source of truth for the contract.
- [ ] Consumers import/generated-from/infer-from that source rather than mirroring it.
- [ ] Backward compatibility and migration behavior are explicit when persisted/wire formats change.

## 4. Fail Fast

Validate at entry points and reject bad states before they travel.

Boundary examples:

- Relay receives JSON/WebSocket frames: parse into typed messages immediately.
- Extension receives app actions: validate action name and payload before invoking handlers.
- Daemon registry receives cwd/name/schedule: normalize and validate before persisting.
- Flutter receives decoded server events: convert to typed domain events before ViewModels act.
- Config/keyring/filesystem reads: parse and permission-check at load time.

Rules:

- Use `unknown` + narrowing in TypeScript, not `any`.
- Use typed failures/results in Dart and Rust where callers can recover.
- Throw/return early with specific errors; do not let invalid state fail three layers later.

## 5. Lifecycle Ownership

Every resource must have exactly one owner and an explicit shutdown path.

Resource examples:

- Pi SDK session context, relay WebSocket, local broker socket, timers, cron jobs, child processes, file watchers.
- Flutter `ChangeNotifier`, stream subscriptions, controllers, animation/timers, async callbacks.
- Rust tasks, channels, sockets, cancellation tokens.

Rules:

- Establish resources in the lifecycle hook/module that owns them.
- Tear them down in the matching shutdown/dispose/drop path.
- After awaits in start/connect flows, re-check disposed/cancelled state before publishing updates.
- Do not keep stale Pi SDK contexts after session replacement; re-capture on `session_start` or through `withSession`.

## 6. Convergent State Machines

Remote Pi surfaces remote, asynchronous state. Every state machine needs convergence paths, not only happy-path transitions.

For `working`/idle, connection, pairing, and daemon states, ask:

- What sets the state true/active?
- What sets it false/inactive after success?
- What sets it false/inactive after error, abort, timeout, reconnect, compaction, shutdown, and session replacement?
- What snapshot hydrates a late-joining client?
- Which events are deltas, and which are authoritative snapshots?

Checklist:

- [ ] Reconnect sends current state, not only future deltas.
- [ ] Error/abort paths publish the same convergence guarantees as success paths.
- [ ] Tests cover lost update or late attach behavior for state that drives UI.

## 7. Refactor Black-Box Test

A pure refactor preserves observable behavior. Before tagging or treating work as refactor, ask whether a caller/user/peer can observe any difference in:

- protocol shape or timing;
- CLI output;
- persisted files;
- UI behavior;
- error class/status/message;
- public API signature;
- resource/lifecycle guarantee.

If yes, it is feature/bug work, not a pure refactor.

## Review checklist

- [ ] Boundaries are explicit; domain/core logic does not import concrete infrastructure.
- [ ] Variant sets and protocol fields have one source of truth.
- [ ] Boundary inputs are parsed/validated at the edge.
- [ ] Long-lived resources have lifecycle ownership and teardown.
- [ ] Async state converges after success, failure, abort, reconnect, and shutdown.
- [ ] Tests verify the high-risk lifecycle/protocol behavior touched by the change.
