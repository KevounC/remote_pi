# Remote Pi — Architecture

How the system is organized: components, data flow, the wire protocol shape,
the session/room model, and lifecycle. Current truth. For the security/trust
detail see `PROTOCOL.md`; for locked decisions see `docs/DECISIONS.md`.

## Components

```
                ┌─────────────────────────────────────────────┐
                │                   RELAY (Rust)               │
                │  axum WS + HTTP  ·  SQLite mesh_versions     │
                │  PeerRegistry · PresenceManager · RoomManager │
                │  MeshAuthCache (60s) · FirehoseMetrics        │
                └───┬───────────────────────────────────┬───────┘
        TLS WS (pi_envelope)              TLS WS (ClientMessage/ServerMessage)
                    │                                       │
   ┌────────────────┴──────────────┐         ┌─────────────────┴────────────┐
   │      pi-extension (Node/TS)   │         │        app (Flutter mobile)    │
   │  Pi SDK bridge · daemon/sup.  │◄────────┤  chat · tool req · actions    │
   │  relay_client · mesh_node     │  pair +  │  ConnectionManager · sync     │
   │  UDS broker · pairing · rooms │  WS chat │  Hive cache · mesh_client     │
   └──┬──────────────────────┬─────┘         └────────────────────────────────┘
      │ UDS envelope          │ Pi custom-event RPC (NUL-prefix control)
      │ {from,to,id,re,body}  │
      ▼                       ▼
   other Pi peers        cockpit (Flutter desktop)
   on same PC            PTY · filesystem · worktrees · session view
```

### pi-extension (`pi-extension/src/`)

The Pi extension plus a standalone daemon. It is the only component that
touches the Pi SDK.

- `index.ts` — extension entry; Pi SDK lifecycle hooks, session-bound context
  capture, control-RPC handling, relay client wiring. (The largest file; the
  `epic-bold-split-pi-extension-index` refactor decomposes it into modules.)
- `session/` — the local agent mesh surface: `broker` (UDS), `broker_remote`,
  `mesh_node` (cross-PC peer), `bridge` (Pi SDK ↔ wire), `cwd_lock`,
  `leader_election`, `peer` / `peer_inventory`, `envelope`, `local_config` /
  `global_config`, `tools`, `setup_wizard` / `wizard`.
- `transport/` — `relay_client` (WS to relay), `peer_channel`,
  `pi_forward_client` (cross-PC forward).
- `mesh/` — `canonical` (envelope canonicalization for signing), `siblings`
  (Pi-pubkey → sibling set), `verify`, `self_revoke` (polling mesh_versions
  and graceful exit), `encoding`, `types`.
- `pairing/` — `crypto` (Ed25519 challenge-response), `qr` (Pi-pubkey + room
  hint + single-use token), `storage` (`peers.json`).
- `daemon/` — `supervisor`, `supervisord` CLI, `cron_registry` / `cron_log`,
  `rpc_child`, `install`, `registry`, `id`, `client`. First-class
  long-running mode (see Open questions §3 in SPEC).
- `protocol/` — `types` (the de-facto wire source of truth today),
  `codec` (`encodeClient` / `decodeServer` + drifted `SERVER_TYPES` registry).
- `actions/` — `registry`, `handlers` (typed app actions → Pi SDK calls).
- `rooms.ts`, `config.ts`, `ui/footer.ts`, `mcp/mesh_server.ts`.

### app (`app/lib/`)

Flutter mobile. Clean architecture: `domain/` (contracts, entities, value
objects, use-cases) has no UI or infra imports; `data/` holds adapters
(transport, sync, mesh, local Hive, repositories); `ui/` is feature pages
with ViewModels + states.

- `protocol/` — `protocol.dart` (~1313-line hand mirror of the TS unions),
  `codec.dart`, `uuid7.dart`.
- `data/transport/` — `ws_transport`, `connection_manager` (the cleanest
  reachability state machine — lifted to a shared contract by
  `epic-bold-reachability-contract`), `peer_channel`, `relay_config`,
  `epk_encoding`, `channel`.
- `data/sync/` — `sync_service` (applies `ServerMessage`s to session state;
  `_applyHistory` replaces the active message box — the contamination vector),
  `sync_events`.
- `data/mesh/` — `mesh_client`, `mesh_sync_service`, `mesh_blob`,
  `mesh_envelope` (cross-PC app-side state).
- `data/local/` — Hive boxes + records (`message_record`, `runtime_record`,
  `session_index_record`).
- `pairing/` — `qr_scanner`, `pair_request_flow`, `owner_identity_bridge`,
  `storage`.
- `ui/` — `chat`, `home`, `onboarding`, `pairing`, `settings`, `voice`,
  `update`, `sync_required`; each with `states/` + `viewmodels/` + `widgets/`.
- `domain/` — `contracts/` (ports), `entities/`, `value_objects/`,
  `session_state.dart`.

### relay (`relay/src/`)

Rust + axum. One binary, one port: WebSocket upgrade (`GET /`), health
(`GET /health`), mesh membership HTTP (`GET/POST /mesh/:hash`).

- `lib.rs` — `AppState` (registry, presence, rooms, mesh, mesh_auth, metrics)
  + router.
- `peers/registry.rs` — `PeerRegistry` (connected peers by pubkey/room).
- `presence.rs` — `PresenceManager` (subscribe/notify, dedup
  offline→online transitions).
- `rooms.rs` — `RoomManager`, `RoomMeta`, `RoomMetaPatch` (per-room metadata:
  `thinking`, `working`, etc. — fields that drift between TS and Dart today).
- `mesh/` — `store` (SQLite `mesh_versions` cartulary, LWW + monotonic
  version anti-rollback), `handler`, `types`, `verify`.
- `auth/` — Ed25519 challenge-response (`challenge.rs`).
- `handlers/` — `peer` (WS upgrade), `pi_forward` (cross-PC
  `pi_envelope` → `pi_envelope_in` forwarding with sibling authorization via
  `MeshAuthCache`).
- `protocol/outer.rs` — serde structs for the outer envelope.
- `metrics.rs` — `FirehoseMetrics` (emit/suppress dedup counters).

### cockpit (`cockpit/lib/`)

Flutter desktop. `flutter_modular` modules/routes/binds, `shadcn_flutter`
UI, Hive persistence.

- `app/cockpit/data/` — `rpc/` (`pi_rpc_process` + factory + registry — the
  NUL-prefix control RPC client), `filesystem/` (file reader/searcher/mutator,
  folder lister, git status, worktree manager, session history, app launcher),
  `terminal/` (PTY gateway), `adapters/` (RPC data/event mappers),
  `repositories/` (Hive project/layout/dismissed-update stores), `update/`,
  `notifications/`, `setup/`.
- `app/cockpit/domain/` — `contracts/` (ports), `entities/` (agent snapshot,
  transcript message, file node, git info, etc.), `validators/`,
  `value_objects/`.
- `app/cockpit/ui/` — `cockpit_page`, `session/` (agent/file-viewer/terminal
  panes), `states/`, `viewmodels/`.

### site (`site/`)

Next.js App Router. Static/presentational marketing + docs. `src/app/`
(layout, page, opengraph-image), `src/components/` (header, footer, docs-shell,
install-tabs, code-block, callout, pager, tabs), `src/lib/` (`app-release`,
`cockpit-release` — read release manifests from rp-s3 / GitHub).

### rp-s3 (`rp-s3/`)

Rust + axum download server. Serves cockpit installers from a mounted volume
behind TLS-terminating proxy. `GET /healthz`, `GET /downloads/<product>/...`
with immutable caching for versioned artifacts, 5-min revalidate for
`latest.json`/`SHA256SUMS`. CORS-open for cross-domain manifest reads by site.

## Wire protocol shape

The wire is the single source of truth. Today it is a four-place handwritten
mirror (see SPEC → "Wire protocol"). The `epic-bold-generated-protocol`
refactor unifies it under one schema with generated TS/Dart/Rust.

### The app↔pi chat wire

`ClientMessage` (app → pi) union: `pair_request`, `user_message` (with
optional `images` and `streaming_behavior`), `queued_message_set` /
`queued_message_clear`, `approve_tool`, `cancel`, `ping`, `session_sync`, and
typed actions `session_new` / `session_compact` / `model_set` /
`thinking_set` / `list_models`.

`ServerMessage` (pi → app) union: `pair_ok` / `pair_error`, `user_input`
(echo), `queued_message_state`, `agent_chunk` / `agent_done` /
`agent_message`, `tool_request` / `tool_result`, `error`, `cancelled`,
`pong`, `bye`, `session_history` (replay of `SessionHistoryEvent`), plus
`action_ok` / `action_error` / `models_list` / `model_select` /
`compaction` (these latter types exist in `types.ts` but are missing from
`codec.ts`'s `SERVER_TYPES` registry — the drift the generated protocol
eliminates).

### The generic envelope (mesh + cross-PC)

```json
{ "from": "<sender>", "to": "<recipient>|[...]|broadcast",
  "id": "<UUIDv7>", "re": "<replied-id>|null", "body": <any JSON> }
```

Local UDS peers and cross-PC relay forwards use the same envelope shape.
Cross-PC wraps it in `pi_envelope` / `pi_envelope_in` frames carrying the
`to_pc` / `from_pc` Pi-pubkeys.

### Cockpit↔pi control RPC

A separate transport: Pi custom events carrying a NUL-prefixed string
(`\x00remote-pi-ctrl:<method>:<args...>`). Folded into the generated schema
by `epic-bold-generated-protocol-cockpit-control-rpc` to retire the magic
prefix.

## Session and room model

**Current truth (pre-bold-refactor).** The protocol carries no `session_id`
on chat-bearing messages. A pairing maps to a relay `room`; the relay demuxes
incoming frames by room and fans out `pi_envelope`s to live rooms. This fails
open in two places: cross-PC `pi_envelope` fans out to every live room
(`relay/src/peers/registry.rs` `forward_to_peer`), and the app accepts legacy
no-room frames unconditionally. The app's `sync_service._applyHistory`
REPLACES the active session's message box, so a foreign `session_history`
overwrites the viewed session — the cross-session contamination class.

This is a designed-then-dropped regression: the absorbed project's protocol
spec *designed* `session_id` on every push message, but it was dropped during
MVP scoping (`app/lib/protocol/protocol.dart:750` comments it: "1 pairing =
1 session: no session_id on any message"). The 1:1 assumption broke down once
multi-session/multi-peer arrived. See `docs/DECISIONS.md` → "Session and
reachability model."

**Locked direction (in-flight via `epic-bold-canonical-session`).** Canonical
`session_id` carried on every chat-bearing message, required and fail-closed,
opaque to the relay (the relay carries it, endpoints validate it). This
restores the designed-then-dropped discriminator and absorbs the
contamination bug and the cross-PC targeting concern.

## Reachability

The same backoff schedule `[1, 2, 5, 10, 30]` and ping cadences are
reimplemented independently in the extension (`index.ts`, `MeshNode`),
the app (`ConnectionManager`), and the relay heartbeat path. Each surface
keeps its own booleans encoding the same unnamed states. The
`epic-bold-reachability-contract` refactor lifts the app's `ConnectionStatus`
sealed class to a shared `Reachability` contract
(`Connecting / Online / Degraded / Offline / Retrying` + one backoff policy)
adopted by all three.

## Lifecycle and convergence

Remote Pi's highest-risk defects are lifecycle and state-convergence bugs.
Invariants every surface must hold:

- **Pi SDK context is session-scoped.** It is invalid after session
  replacement (`/new`, `/resume`, `/fork`, `/reload`). Re-capture through
  `session_start` / `withSession` and guard old contexts.
- **`working` state converges false** after success, error, abort, compaction,
  reconnect, and shutdown — not only on success.
- **Reconnect hydration** re-applies state without duplicating or dropping
  messages; stale events from a prior session must not overwrite the current
  view (the contamination vector).
- **Flutter async UI** uses mounted guards after `await`; ViewModels and
  subscriptions close on their lifecycle boundary.
- **WebSockets, timers, spawned processes, and stream subscriptions** have an
  explicit owner and a teardown path.

The `epic-bold-turn-state-machine` refactor makes the turn lifecycle algebraic
(`Idle / Working / AwaitingTool / Streaming / Done / Error` + explicit
transitions) so convergence is provable rather than heuristic. The
`epic-bold-transcript-event-log` refactor replaces in-place message-box
mutation with an append-only event log + derived projection, eliminating the
replace-on-`session_history` failure mode.

## Data flow (send a prompt, end to end)

1. App `chat_viewmodel` → `ClientMessage.user_message` → `ws_transport` →
   relay WS.
2. Relay forwards by room to the paired pi-extension's WS.
3. Extension `session/bridge` maps to a Pi SDK `sendUserMessage` call
   (multimodal: images → text order).
4. Pi streams `agent_chunk`s; bridge emits `ServerMessage.agent_chunk` → relay
   → app `sync_service` → `chat_viewmodel` → streaming bubble.
5. Tool calls emit `tool_request`; `tool_result` follows. (Approval is
   dormant in the app — tool calls execute directly per
   `plan/00-decisions.md`.)
6. `agent_done` terminates the turn; `working` must converge false.

Cross-PC: the same envelope flows as `pi_envelope` (Pi-A → relay) /
`pi_envelope_in` (relay → Pi-B), authorized via `MeshAuthCache` sibling lookup
and anti-spoof-checked at the receiving broker (`envelope.from` prefix must
match the `from_pc` pubkey's `pc_label`).

## Bold refactor DAG (the in-flight reconception)

Eight epics, two roots. The foundation is `epic-bold-generated-protocol`
(unify the wire); the small independent root is
`epic-bold-reachability-contract`. Every epic's riskiest child is a
design-first root within its epic, so all eight can begin their feasibility-
proving design pass in parallel.

```
generated-protocol (root)        reachability-contract (root, small)
  ├── schema-source                 ├── state-machine
  ├── dart-codegen (riskiest)        ├── app-adapter
  ├── ts-codegen                     └── pi-adapter
  ├── rust-codegen
  └── cockpit-control-rpc

canonical-session ← generated-protocol
  ├── identity-model (riskiest)
  ├── wire-discriminator (absorbs contamination bug)
  ├── relay-opaque-targeting
  └── app-attribution-hydration

turn-state-machine ← generated-protocol
relay-typed-actor ← generated-protocol
cockpit-workspace-projection ← generated-protocol
transcript-event-log ← canonical-session
split-pi-extension-index ← generated-protocol + canonical-session + turn-state-machine
```

Tracked in `.work/active/epics/epic-bold-*.md` + 29 child features. The DAG is
cycle-free; 9 children are ready to design now (the `depends_on: []` roots
across all eight epics).
