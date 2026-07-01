# Changelog

All notable changes to Remote Pi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For the canonical protocol specification, see [PROTOCOL.md](PROTOCOL.md).

---

## [app-v1.2.0] — 2026-07-01

Mobile app minor over `app-v1.1.1`. Ships the mobile half of the bold-refactor
arc (canonical-session attribution/hydration, reachability app adapter + state
machine, transcript event log store/replay/projection) plus the second
gate-enabled release pass. **Must deploy paired with `relay-0.2.0`** — the
relay auth signature is now domain-separated (wire change).

### Fixed
- **Security**: relay auth no longer signs the bare relay-provided nonce with the
  long-term owner Ed25519 key (cross-protocol signing oracle). The app now signs
  `remote-pi-relay-auth-v1\n` ++ nonce; the relay verifies the same.
- **Lifecycle**: `ConnectionManager.dispose` now tears down the active connection
  (cancels the in-flight connect token + closes the WebSocket channel) instead of
  leaking it past disposal.

### Added
- Canonical `RemoteSessionRef` identity + attribution/hydration for sessions.
- Reachability as an explicit state machine + app adapter (replaces scattered
  booleans).
- Transcript event log: append-only store, hydration/replay, projection-derive.

### Internal (release-gate dogfood)
- 6 gates run; 24 findings produced. 2 high blocking (signing oracle + dispose leak)
  resolved before ship; 22 medium/low tracked in backlog.

## [cockpit-v1.6.0] — 2026-07-01

Desktop cockpit minor over `cockpit-v1.5.1`. Ships the cockpit half of the
bold-refactor arc (workspace projection, cockpit control RPC, transcript
hydration) plus the first gate-enabled release pass.

### Added
- Workspace is now a pure document (`WorkspaceDocument` / `LeafPane` / `SplitPane`,
  multiple tabs/sessions) with mutations as typed command transforms
  (`WorkspaceDocumentCommands` → `WorkspaceCommandResult`) funneled through a
  single reducer (`CockpitViewModel._applyWorkspaceCommand`).
- Agent sessions are immutable projections (`AgentSessionProjection`) consumed
  by the UI via derived getters, not direct mutable fields.
- Cockpit ↔ Pi control RPC (schema command envelopes for remote-pi relay/mesh
  control) — extensions now intentionally loaded.
- Transcript event hydration/replay seam in the cockpit.

### Changed
- Settings split into a category registry + dispatch composition (appearance,
  connectivity, daemon, language, notification, schedule).
- `rpc-protocol.md` spawn contract updated: defaults `noSession=false` /
  `noExtensions=false` (extensions loaded for remote-pi command discovery).
- `cockpit/CLAUDE.md` scope rewritten from MVP/single-pane to current
  workspace-projection architecture.

### Fixed
- Removed a temporary debug trace scaffold (`_trace`/`ck_trace.log`) left in the
  workspace settings dialog.
- `auto_retry_*` events no longer listed as ignored (parsed as `RpcAutoRetry`).

### Internal (release-gate dogfood)
- First release run through the gate-enabled substrate (security, tests, cruft,
  docs, patterns, refactor). 24 gate findings produced; 4 critical/high + 1
  medium (debug artifact) resolved before ship; 19 medium/low tracked in backlog.
- 7 new widget/unit tests covering LSP command save/reset behavior and the
  notification permission mounted guard.

## [app-v1.1.1] — 2026-06-29

Mobile app patch over `app-v1.1.0`. Mobile-side fixes shipped to the
operator's phone before the bold-refactor arc began.

### Fixed
- Mobile message send failures now visible (send-timeout backstop, pending-send
  preservation on disconnect, deterministic disconnect test).
- Mobile `working` status now converges on disconnect instead of sticking.
- Room-switch snapshot adoption corrected.
- History clear guarded against missing prior session start.
- Rooms controller now closes on dispose (lifecycle leak).

### Added
- Android debug-APK build smoke test (`flutter build apk --debug`).

## [extension-0.5.4] — 2026-06-29

pi-extension patch over `extension-0.5.3`. Stale-context and session-bound
surface fixes.

### Fixed
- Stale Pi SDK context after session replacement (`/new`): API recapture and
  runtime audit hardened the session-bound surface.
- Stale Pi API after app `session_new`.
- `peers.json` permissions hardened (`0o600`, atomic write).
- Session-start message API recapture.

### Added
- Local vendor switch (fork-private pi-extension packaging).
- Stale-context source investigation + source fix.

## [relay-0.1.0] — 2026-06-29

First tracked relay release. The relay existed since project inception but had
no tag; `0.1.0` is its first tracked release.

### Fixed
- Relay mesh auth cache reverified.
- Relay control-frame fanout capped.

## [v0.5.0] — 2026-06-29 (repo)

Repo-level cross-component release over `v0.4.0`. Captures work that doesn't
belong to a single component: the agent-reference surface, the adversarial
codebase review, the api-reference stack docs, and cross-component fixes.

### Added
- Agent reference surface: platform-style stack references for agents
  (`.agents/skills/<reference>/SKILL.md` pattern).
- Mobile remote-coding best-practices skill (cross-cutting app/extension/relay).
- API references: pi-extension TypeScript, Flutter mobile, Flutter desktop
  cockpit, Rust relay, Next site stacks.
- Research: platform agent reference patterns.

### Fixed
- Cross-PC transport-error uuid.
- Extension queued-message protocol.
- Late-attach turn stream sync.
- Security doc drift.
- Guard stale session history after `session_new`.
- Mobile resume hydration.

### Reviewed
- Adversarial codebase review (multi-model): findings dedup/routing, mobile
  lifecycle, security/privacy, state/protocol.

## [Unreleased] — PC mesh foundation

This release consolidates the work that turned Remote Pi from "phone controls
one Pi" into a **mesh of coding agents** running on multiple machines, with
the phone acting purely as the initial authenticator. Covers plans 23, 24, 25,
and 27 (see [`plan/`](plan/) directory for design history).

### Added

#### Owner-key sync (plan/23)
- New Flutter plugin `remote_pi_identity` for storing the Owner-key in the
  platform credential store (iOS Keychain with iCloud sync, Android Block Store
  with Google account sync), enabling the same logical Owner across multiple
  mobile devices without re-pairing.
- Owner-key is the cryptographic root of authority — Ed25519 keypair signing
  every `mesh_versions` blob and authorizing pair/revoke operations.

#### Mesh membership (plan/24)
- Relay gained a SQLite-backed `mesh_versions` store. Each Owner publishes a
  signed blob listing the PCs (Pi-pubkeys + nicknames) that belong to their
  mesh. Relay verifies Ed25519 signatures and enforces monotonic versions for
  anti-rollback; never decides membership.
- New endpoints: `POST /mesh/<owner_pk_hash>` (write) and
  `GET /mesh/<owner_pk_hash>` (read).
- `MeshClient` + `MeshSyncService` on the app side, with on-demand pull and
  60-second foreground polling.
- Self-revoke on the Pi: when the Pi detects its own pubkey is no longer in
  the Owner's `mesh_versions`, it exits gracefully.
- Reinstalling the app restores peers automatically once the Owner-key is
  recovered (no manual re-pairing needed).

#### Cross-PC envelope routing (plan/25)
- New WebSocket frames between Pi-extension and relay:
  - `pi_envelope` (Pi-A → Relay): request forwarding to another Pi of the
    same Owner.
  - `pi_envelope_in` (Relay → Pi-B): delivers the envelope verbatim, plus
    `from_pc` ground-truth pubkey for anti-spoof.
- `MeshAuthCache` on the relay (60-second TTL, keyed by Pi-pubkey →
  set-of-siblings) verifies `same Owner` per forward without hitting SQLite
  on every message.
- Transport errors (`offline`, `not_authorized`, `bad_envelope`) flow back as
  **normal envelopes** with `body.type = "transport_error"` and
  `from = "_relay"` — no custom WS error frames. The sender's ACK machinery
  correlates them via `re: <original-envelope-id>`.

#### ACK protocol (plan/25 Wave 0)
- `agent_send` now waits for an ACK (`received | busy | denied | timeout`)
  generated by the destination Pi's TypeScript wrapper — not by the LLM. No
  tokens, no turn required. Default timeout: 5 seconds.
- The wrapper tracks `turn_in_progress` via Pi SDK hooks
  (`pi.on("turn_start"|"turn_end")`); concurrent messages during a turn get
  `busy` and are dropped.
- Replies with `re != null` bypass the busy gate — necessary for parallel
  send patterns and reply correlation.
- Reply content remains asynchronous: the destination peer responds with
  another `send` carrying `re: <original-id>`. Sender sees it in its inbox
  on a future turn. No `agent_wait` tool — the model is event-driven by
  design.
- `agent_request` is deprecated (still functional, emits a one-shot warning).

#### Broker remote + prefix routing (plan/25 Waves B + C)
- New module `broker_remote.ts` in the Pi-extension: caches sibling peers
  (`Map<pc_label, {peers, pc_pubkey, ts}>` with 5-min TTL), proactively pushes
  `peers_update` on local `peer_joined`/`peer_left`, and intercepts control
  envelopes (`peers_update`, `peers_request`, `transport_error`).
- New `pi_forward_client.ts`: thin wrapper over the existing relay WS client
  that emits `pi_envelope` frames.
- Broker's `_resolveTargets` parses prefix addressing: envelopes with
  `to = "<pc>:<peer>"` are handed off to `broker_remote` when the prefix is a
  known sibling; envelopes without prefix or with `self_pc_label` continue via
  UDS locally (backward-compatible with peer names containing `:`).
- New privileged API `Broker.injectFromRemote(env)` bypasses the local
  `force from = conn.name` rule (the per-conn anti-spoof) because cross-PC has
  its own defense via `from_pc` in the relay wrapper.
- Anti-spoof on inbound: `envelope.from` prefix must match the `pc_label`
  registered for the authenticated `from_pc` — otherwise dropped with a log.
- `list_peers` aggregates locals (no prefix) and remotes (prefixed by
  `pc_label`).

#### Cross-PC polish (plan/25 Wave D)
- ACK matcher in `peer.ts` now accepts both `from === "broker"` and
  `from.endsWith(":broker")` — cross-PC ACKs (`from = "<pc_label>:broker"`)
  now resolve `sendWithAck` instead of timing out.
- Failover hook: when the leader UDS reconnects, `broker_remote` is torn down
  and recreated, preventing aliasing bugs if the previous leader died.
- Sibling membership now reactive: a callback in `self_revoke.ts` polling
  re-invokes `broker_remote.setSiblings()` whenever the union of members
  across all paired Owners changes. No restart needed.
- New CLI `/remote-pi peers`: lists local and remote peers grouped by
  `pc_label`, locally-sorted alphabetically.
- `audit.jsonl` gained a `via` field (`"uds" | "relay"`) per route so
  cross-PC envelopes are distinguishable in logs.

#### Pairing polish (plan/27 Wave A)
- After a successful pair, the app shows a nickname sheet asking the user to
  label the newly paired PC (defaults to the Pi's `hostname` if provided,
  otherwise "Pi"). Skipping still persists the fallback so the mesh entry
  never has an empty nickname.
- The Pi-extension now includes optional fields in the `pair_ok` payload:
  - `harness: { name: "Pi coding agent", version: "<package.json version>" }`
  - `hostname: os.hostname()`
- `PeerRecord` in the app gained an optional `harness` field. The
  `PeerSectionHeader` renders `via Pi coding agent` (or another harness
  string when wrappers for Claude Code / OpenCode arrive in the future).

#### Pi-key cross-platform storage (plan/27 Wave E1)
- Migrated from `keytar` (deprecated) to `@napi-rs/keyring` for cross-platform
  Pi-secret storage:
  - macOS: Keychain (Apple Silicon transparently delegates to Secure Enclave)
  - Linux desktop: libsecret (GNOME Keyring / KWallet)
  - Windows: Credential Manager (DPAPI-backed)
- Service name renamed `dev.remotepi.mac` → `dev.remotepi.pi` (neutral).
- Migration is silent: on first boot post-upgrade, the new entry is read
  first; if missing, the old `dev.remotepi.mac` entry is read directly via
  the new library (the underlying native APIs are the same), copied to the
  new service, and deleted. Existing Pi-keys are preserved.
- Headless Linux fallback: when keyring is unavailable (no D-Bus session in
  containers / VPS without a desktop), Pi-secret falls back to
  `~/.pi/remote/identity.json` with `chmod 0600` and a loud warning.
- New `KeyStoreBackend` abstraction with `InMemoryBackend` enables
  reproducible tests without touching the developer's real Keychain.

#### Protocol & security documentation
- New canonical document [`PROTOCOL.md`](PROTOCOL.md) at the repo root covering:
  wire format, identity model, ACK protocol, cross-PC routing, mesh
  membership, pairing flow, honest trust model, threat model, failure modes,
  and architectural roadmap.
- Linked from `pi-extension/README.md`, `pi-extension/CLAUDE.md`,
  `relay/README.md`, and the site's `/docs#protocol` section (plus footer).

#### Daemon mode (pi-extension)
- Pi can now run as a managed background daemon (`launchd` on macOS,
  `systemd --user` on Linux) for "always on" coding-agent mesh participation.

#### Multi-channel pi-extension (Wave 2D)
- Pi-extension now accepts multiple paired Owners simultaneously via
  `_activePeers: Map<peer_id, PlainPeerChannel>` (no longer a singleton). The
  pair flow no longer rejects new pair requests when one Owner is already
  paired ("concurrency by design").
- `user_message` is rebroadcast to **all active peers** (source-of-truth
  pattern): when any device sends a message, the Pi echoes the canonical
  version with the same `id` to every paired device. Senders render their
  own bubble as `pending` and promote to `confirmed` when the echo arrives;
  other devices insert the message as `confirmed` directly.

### Changed

#### Relay control-frame deduplication
- `peer_online` now fires **only on real offline→online transitions**, not
  on every `register` call. Re-registers from peers that already had a live
  connection are silently absorbed without spamming subscribers.
- `presence_check` and `rooms_check` responses are deduplicated per
  connection: identical replies are suppressed; only changes produce new
  snapshots. Subscribers always receive the initial backfill correctly.
- New `FirehoseMetrics` emits a structured log line every 10 seconds with
  emit/suppress counters per frame type (silent when all counters are zero).
- Closes a regression observed in production where 2 active mobile devices
  caused ~10 redundant `peer_online` per peer per 30 seconds, contributing
  to CPU spikes on Android.

#### Reconnect resilience (app)
- `requestSync` no longer drops requests silently when the WebSocket is not
  yet ready. A `_pendingSyncRequest` flag defers the sync until
  `_onlineActivated` fires.
- `_clearAllPending` now only cancels pending timers without touching the
  message state; a new `_rearmPendingAfterReconnect` re-arms timers for
  surviving `pending` messages after reconnection.
- `_applyHistory` is now an intelligent merge instead of a destructive
  replace: pending messages whose `id` is present in the history are
  confirmed (timers cancelled); pending messages absent from the history
  are preserved in the tail. The merged state is persisted, so cold restarts
  with pending messages re-arm their timers.

#### Site copy
- Reframed from "control your Pi from your phone" to "mesh of coding agents
  on every machine you work from; the phone is just the authenticator."
- All four feature cards rewritten; hero, OG image, docs intro, daemon
  section, and final CTA updated. Layout and components unchanged — diff is
  string-only.

#### Plan/03-protocol historical update
- `plan/03-protocol.md` (MVP-era spec) now opens with an alert pointing to
  `PROTOCOL.md` as the current canonical document, plus a "Post-MVP changes"
  section summarizing the evolution. The rest of the file is preserved as
  historical reference.

### Fixed

#### Self-revoke encoding inconsistency
- After pairing, the Pi-extension occasionally triggered self-revoke because
  the Owner-pubkey stored in `peers.json` was in standard base64 while the
  `remote_epk` carried by the app was in URL-safe base64. Comparison now
  decodes both forms and compares bytes (new `mesh/encoding.ts` helper).

#### "Already paired" rejection on second pairing
- The first iteration of pi-extension treated a non-idle paired state as a
  hard refusal of new pair requests. With concurrent Owners (`plan/25` Wave
  2D), this blocked legitimate pair attempts. `_cmdPair` is now permissive
  and routes a new pair through the multi-channel registry.

#### Mobile chat regression after iPhone joins
- On Android, sending a message right after the iPhone joined the same Pi
  could leave the bubble stuck at `pending` even though the echo arrived.
  Root cause: a transient WS reconnect during the join wiped pending state.
  Fixed by combining the resilience changes above (`_clearAllPending` no
  longer destroys state; `_applyHistory` merges instead of replaces).

#### Chat title flashing "Remote Pi" on open
- Home now passes a title hint via `go_router` extra (room name → cwd
  basename → peer nickname → session name → epk prefix). `ChatPage` renders
  the hint immediately so the AppBar shows the correct label on frame 1.

#### Pi-extension docker image build
- `Dockerfile` was missing `COPY migrations ./migrations`. Builds failed at
  `cargo build` because `store.rs` uses `include_str!` for the SQL schema.
  Added the missing line; verified end-to-end with `docker build` and a
  container smoke test against the three runtime surfaces (`/health`,
  `GET /mesh/<unknown>`, WS upgrade).

#### App session_sync silent drop
- `requestSync` returned early without action when the channel was not yet
  ready, leading to empty chat history after a cold open. Now it defers and
  fires automatically on the next `StatusOnline`.

### Security

- **Honest trust model documentation.** Removed every claim of end-to-end
  encryption from user-facing surfaces:
  - `site/src/app/layout.tsx` global meta tags (description, OG, Twitter
    cards, keywords) — was leaking E2E claims into link previews on
    WhatsApp / Slack / search results.
  - `site/src/app/terms/page.tsx` §2 (Account & Pairing) and §5 (Prohibited
    Conduct) — replaced "end-to-end encrypted channel" with "mutually
    authenticated channel (Ed25519 challenge-response)" and similar.
  - `site/src/app/docs/page.tsx` "The relay" section — now points to the
    real trust model in `PROTOCOL.md`.
  - `pi-extension/README.md` — substituted "Encryption uses Curve25519 +
    ChaCha20-Poly1305; the relay sees only ciphertext" with a TLS-only
    statement and a pointer to `PROTOCOL.md`. (Two further occurrences
    flagged in the file for a follow-up cleanup wave.)
- **No new E2E primitives introduced.** TLS protects traffic in transit; the
  relay sees plaintext envelopes at rest and in forwarding. Self-hosting is
  the recommended path for sensitive deployments. E2E payload encryption is
  on the public roadmap (see `PROTOCOL.md` "Roadmap").

### Removed

- `keytar` dependency removed from pi-extension (deprecated upstream;
  replaced by `@napi-rs/keyring`). 29 transitive packages dropped.

### Decided (architectural)

These decisions were resolved during this cycle but produce no code change.
Documented for context:

- **PC-to-PC direct transport** (WebRTC/QUIC) deferred to a future plan;
  relay remains the cross-PC transport for the MVP. Cross-PC latency hop
  (~100ms via relay) is acceptable.
- **Relay-via-UDS broker gateway** was investigated and discarded. The
  alternative is **wrappers**: when Claude Code or OpenCode support is
  needed, `remote-pi claude` will spawn the harness and register as a peer
  on the existing local UDS broker. Reuses the envelope JSONL protocol,
  requires zero pi-extension refactor, and keeps each harness isolatable.
- **Pi-key hardware-bound storage** (Secure Enclave / TPM / CNG) discarded
  for now. Constraint accepted: "one Pi-key per PC; hardware swap = re-pair".
  Software user-bound storage (Keychain / libsecret / Credential Manager)
  is sufficient given the constraint.

---

## [0.1.3] — 2026-05-22

### Added

- Privacy Policy and Terms of Service pages (`/privacy`, `/terms`).
- Site documentation layout improvements: sidebar + table of contents.
- Multi-platform Docker build for the relay (`linux/amd64`, `linux/arm64`).
- Relay published at `wss://relay-rp1.jacobmoura.work` (default community
  endpoint).
- Visual identity and launch icons for Android, iOS, and macOS.

### Changed

- Native display name "Remote Pi" applied across platforms.
- Pi-extension prepared for npm publishing.

### Fixed

- App: empty custom relay URL allowed in onboarding (previously rejected).

### Removed

- macOS desktop platform from the Flutter build (focus on mobile only).

---

## Earlier history

Plans 01–22 covered bootstrap, AI orchestration, protocol MVP, pairing,
rollback E2E (later reverted), revoke + multi-pairing, presence,
chat-state recovery, onboarding, mirror cache, rooms, agent network, agent
tools, setup wizard, and the site MVP. See [`plan/`](plan/) for the design
history of each.

[Unreleased]: https://github.com/jacobaraujo7/remote_pi/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/jacobaraujo7/remote_pi/releases/tag/v0.1.3
