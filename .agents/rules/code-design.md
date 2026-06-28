# Code Design Rules

Remote Pi is a multi-surface system: Pi extension, mobile app, relay, desktop cockpit, and site. Design for explicit boundaries and convergent state instead of convenience imports or duplicated protocol facts.

For deeper examples, load `.agents/skills/code-design-principles/SKILL.md` before significant design, implementation, or review work.

## Ports and adapters

Domain logic must not depend directly on infrastructure. Define the port where the core logic lives; implement it at the edge.

- Flutter domain/use-case code does not import UI widgets, route objects, storage clients, WebSocket clients, or platform APIs directly.
- Pi extension session/mesh logic should isolate Pi SDK, relay WebSocket, filesystem/keyring, and process-spawn effects behind narrow functions or classes.
- Relay routing should keep transport, auth, rate-limit, and message-routing responsibilities explicit.
- Composition roots wire adapters to ports; domain code receives dependencies by constructor/function parameter or module binding.

## Single source of truth

Any variant set that can drift must be defined once and derived everywhere else:

- protocol message types;
- room/session metadata fields;
- app action names;
- daemon state names;
- mesh peer address formats;
- route/path constants;
- UI state-machine states.

Do not re-enumerate the same variants in separate validators, UI labels, handlers, and tests. Derive types, validation, dispatch, and display from one registry/schema where practical.

## Generated or inferred contracts

Prefer generated/inferred contracts across boundaries instead of handwritten mirrors.

- TypeScript: derive unions from `as const` registries and schemas.
- Dart: keep wire/domain DTOs generated or centrally defined when possible; do not let UI-only copies become a second protocol.
- Rust: derive Serde wire types from canonical structs/enums; do not parse into ad-hoc maps in business logic.
- Cross-language protocol changes require explicit update of every consumer and at least one compatibility test or smoke recipe.

## Fail fast at boundaries

Validate untrusted data at the first boundary:

- relay/app/extension wire messages;
- QR pairing payloads;
- CLI args and daemon registry entries;
- config files and environment variables;
- RPC events from spawned Pi processes;
- filesystem/keyring responses.

Use `unknown` + narrowing in TypeScript, typed DTO parsing in Dart, and Serde/error enums in Rust. Do not pass ambiguous maps, nullable blobs, or raw JSON deep into business logic.

## Lifecycle ownership

Every long-lived resource needs an owner and a teardown path:

- WebSockets, broker sockets, timers, spawned processes, streams/subscriptions, controllers, ViewModels, and file watchers must close on their lifecycle boundary.
- Pi extension session-scoped context is invalid after session replacement (`/new`, `/resume`, `/fork`, `/reload`). Re-capture through `session_start` or `withSession` and guard old contexts.
- Mobile and cockpit async UI code must not use `BuildContext` after `await` without a mounted guard.
- Room/session `working` state must converge false after success, error, abort, compaction, reconnect, and shutdown.

## Observable behavior test

A `[refactor]` or structural cleanup must preserve public behavior. If a change alters protocol shape, user-visible UI, CLI output, persistence format, or timing guarantees, it is not a pure refactor; route it as feature/bug work and update tests/docs accordingly.
