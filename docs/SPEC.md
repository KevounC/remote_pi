# Remote Pi — Specification

Technical boundaries, hard constraints, external interfaces, and the trust
model. Current truth, not history. Cross-check any version-sensitive fact
against the package files in the relevant subproject before relying on it.

## Stack

| Component | Language / runtime | Entry manifest | Builds to |
|---|---|---|---|
| `pi-extension/` | Node.js + TypeScript (ESM) | `pi-extension/package.json` | `dist/` — Pi extension + `remote-pi` + `pi-supervisord` CLIs |
| `app/` | Flutter / Dart (mobile) | `app/pubspec.yaml` | Android APK (primary); iOS buildable |
| `relay/` | Rust (edition 2024), axum 0.7, tokio, rusqlite | `relay/Cargo.toml` | single Rust binary |
| `cockpit/` | Flutter / Dart (desktop) | `cockpit/pubspec.yaml` | macOS / Windows / Linux desktop |
| `site/` | Next.js (App Router) + React + Tailwind | `site/package.json` | static / standalone Docker |
| `rp-s3/` | Rust + axum (download server) | `rp-s3/Cargo.toml` | container serving cockpit installers |

Key dependencies: Pi SDK (`@earendil-works/pi-coding-agent`) consumed by the
extension; `ws` (WebSocket) in the extension; `@napi-rs/keyring` for Pi-key
storage; `ed25519-dalek` and `sha2` in Rust; `cryptography` (dint.dev) for
Ed25519 in the app; Hive for local cache in Flutter; `flutter_modular` +
`shadcn_flutter` in cockpit.

## Hard constraints

- **Pi-only.** No abstraction layer for other coding agents. The extension
  consumes the Pi SDK directly.
- **One Pi-key per PC.** Hardware change = re-pairing. There is no Pi-key
  migration between machines; the Owner-key (mobile, synced via system
  Keychain) compensates.
- **Ed25519 everywhere for identity.** Owner-key signs `mesh_versions`;
  Pi-key authenticates to the relay and signs cross-PC envelopes; App-key is
  ephemeral per pairing session.
- **Relay never decides membership.** It forwards between Pi-siblings of the
  same Owner (verified via Owner signature on `mesh_versions`) and verifies
  signatures, but it never adjudicates who is in the mesh — the Owner does.
- **No E2E today.** TLS on transport is the only protection against an external
  MITM. The relay sees plaintext envelope contents. This is declared honestly
  in product copy and in `PROTOCOL.md`. Re-enabling E2E (Noise XX /
  Curve25519 + ChaCha20-Poly1305) is roadmap-additive and must not change the
  envelope shape.
- **No message-queue offline delivery.** If a peer is offline, the sender gets
  `transport_error: offline` immediately. Queued-message state is a short
  in-memory Pi-side buffer for prompts held during an active turn, lost on
  restart.
- **Cross-PC is relay-mediated.** Direct PC-to-PC (WebRTC/QUIC) is long-term
  roadmap; the relay becomes the fallback then.

## External interfaces

### Wire protocol (the single source of truth — currently handwritten in four places)

The wire is the contract that every surface speaks. Today it is defined as
handwritten mirrors:

- **TS** — `pi-extension/src/protocol/types.ts` (`ClientMessage` /
  `ServerMessage` unions), `protocol/codec.ts` (`encodeClient` / `decodeServer`
  + a `SERVER_TYPES` registry that has drifted — omits `user_message`,
  `compaction`, `action_ok`, `action_error`, `models_list`).
- **Dart** — `app/lib/protocol/protocol.dart` (~1313 lines, the largest hand
  mirror), `protocol/codec.dart`, `protocol/uuid7.dart`.
- **Rust** — `relay/src/protocol/outer.rs` + `rooms.rs` (serde structs for the
  relay outer envelope and room metadata).
- **Cockpit↔pi control RPC** — a fourth, private NUL-prefix string RPC
  (`\x00remote-pi-ctrl:...`) over Pi custom events, mirrored in
  `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart` and
  `pi-extension/src/index.ts`.

This four-way hand mirror is the root cause of "annoying to bugfix" and the
target of the `epic-bold-generated-protocol` refactor: define the wire once in
a canonical schema, generate TS unions + validators, Dart sealed classes +
`fromJson`, and Rust serde structs. Until that lands, treat
`pi-extension/src/protocol/types.ts` as the de-facto source of truth and
mirror changes by hand to Dart and Rust.

### Transports

1. **App ↔ pi-extension** — WebSocket over TLS (relay-mediated) carrying
   newline-delimited JSON `ClientMessage` / `ServerMessage`. Chat-bearing
   `ServerMessage`s (`user_message`, `agent_chunk`, `agent_done`,
   `session_history`) carry **no session discriminator** today — see
   "Open questions" and `docs/ARCHITECTURE.md` → "Session and room model."
2. **Cross-PC pi-to-pi** — relay `pi_envelope` / `pi_envelope_in` frames
   wrapping the generic agent envelope `{from, to, id, re, body}`. The relay
   forwards opaquely; it does not parse envelope bodies (though the body is
   plaintext base64, not ciphertext).
3. **Cockpit ↔ pi-extension** — Pi custom events with the NUL-prefix control
   RPC string protocol (separate transport, not relay).
4. **Local agent mesh** — Unix Domain Socket broker per PC; local peers
   exchange the same `{from, to, id, re, body}` envelope without crossing the
   relay.

### Identity and trust

| Key | Algorithm | Where it lives | Who creates it | Used for |
|---|---|---|---|---|
| Owner-key | Ed25519 | Mobile Keychain (iOS Keychain / Android Block Store), synced via iCloud / Google account | App on first boot | Signs `mesh_versions`; proves authority to pair/revoke PCs |
| Pi-key | Ed25519 | PC keyring via `@napi-rs/keyring` (macOS Keychain / libsecret / Credential Manager). Fallback `~/.pi/remote/identity.json` (`0600`) with a warning on headless Linux | pi-extension on first boot | Authenticates WS to the relay; signs cross-PC envelopes |
| App-key | Ed25519, ephemeral | App RAM | App per pairing session | Authenticated channel establishment during pairing |

Detailed trust model, threat table, and "what is NOT protected" live in
`PROTOCOL.md` → "Modelo de proteção (Trust Model)." Summary of what is not
protected: relay sees plaintext contents; no E2E; headless Linux falls back to
a `0600` file on disk; full encrypted backups can carry the Keychain; clone
detection (two PCs with the same Pi-key) is not yet implemented.

## Verification commands

Run from the owning subproject root:

```bash
# pi-extension/
corepack pnpm typecheck && corepack pnpm test && corepack pnpm build

# app/
flutter analyze && flutter test

# relay/
cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build

# cockpit/
flutter analyze && flutter test

# site/
pnpm lint && pnpm build
```

If a command is unavailable or too expensive in the current environment, state
what was skipped and why, and run the nearest meaningful smaller check.

## Open questions

Genuine ambiguities surfaced while authoring. None blocks the docs; each has a
recommended resolution and is flagged for operator confirmation so the
foundation stays clean rather than baking in a guess.

1. **Session identity model — current truth vs. locked direction.** The wire
   carries no `session_id` on chat-bearing messages today (the contamination
   bug). The operator has locked the target: canonical `session_id`, required,
   fail-closed, absorbed by `epic-bold-canonical-session`. The foundation docs
   describe **current truth** (no discriminator; relay-room demux) and treat
   the canonical-session direction as in-flight via the bold refactor. Confirm
   this is the right framing for a rolling-foundation doc, or whether VISION
   should describe the target state instead.

2. **Relay "stateless" framing has drifted.** The absorbed project's
   `plan/00-decisions.md` recorded "Relay stateless / Sem persistência." The
   relay now has a SQLite-backed `MeshStore` (the signed `mesh_versions`
   cartulary) plus in-memory `PeerRegistry`, `PresenceManager`, `RoomManager`,
   and `FirehoseMetrics`. Accurate framing: the relay is **stateless for
   message routing** (no per-session state, no offline queue) **with a narrow
   persistence layer for mesh membership** and ephemeral presence/rooms.
   Resolved — `docs/DECISIONS.md` records the current truth; the MVP-era
   "stateless" line is superseded.

3. **Daemon as first-class component.** The absorbed project's
   `plan/00-decisions.md` recorded "Sem daemon no MVP." A substantial
   `pi-extension/src/daemon/` module has shipped (supervisord, cron registry,
   RPC child, install, registry). The daemon is GA, first-class — the
   MVP-scoping decision was explicitly revisited and shipped. Resolved —
   `docs/DECISIONS.md` records current truth.

4. **Fork product direction.** Resolved — fully private-carry; no upstream
   PRs. The bold refactor is fork-local with no upstream-compat constraints.
   Patchbay is the long-term successor direction. `docs/DECISIONS.md` →
   "Fork posture" records this.

5. **Multi-session vs. 1:1 pairing.** The absorbed project's
   `plan/00-decisions.md` had a complex reverted-and-re-added history around
   "1 pairing = 1 session" vs. N sessions per pairing. Current code: the app
   home page lists multiple peers/sessions; `_peerChannel` is a singleton in
   the extension; broadcast happens at the relay. Resolved — the runtime
   invariant is "1 active connection per `(peer, room)` at the extension,
   broadcast-fanout at the relay." `docs/DECISIONS.md` records this.

All five resolved ambiguities are locked in `docs/DECISIONS.md`. The open
questions section above is retained for future ambiguities surfaced during
the bold refactor.
