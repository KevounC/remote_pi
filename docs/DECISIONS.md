# Remote Pi — Decisions

The rolling-foundation decisions registry. Locked product, architecture, and
operating decisions — current truth, not history. When a decision changes,
rewrite the line in place; do not append a new historical layer. Serious
rejected alternatives are recorded inline only when a future agent might
otherwise re-open them.

This file succeeds the absorbed project's `plan/00-decisions.md`, which was
retired to git history along with the rest of `plan/` when the fork moved to a
private-carry stewardship model. Decisions that were MVP-era and have since
been superseded are recorded here *as corrected current truth*; the original
MVP-era rationale is retrievable via `git show` if ever needed.

**`plan/` is retired to git history.** Any `plan/NN-*` citation in older
artifacts (e.g. `PROTOCOL.md`, subproject `CLAUDE.md`/`README.md`,
`CHANGELOG.md`) is a historical reference, not current truth. Read the code
and this file as current truth; recover a retired plan's content with
`git show <commit>:plan/NN-name.md` (the commit that retired `plan/` is the
stewardship pass that introduced this file). Likewise `.orchestration/`
lost its cmux overlay and fork-owned `tasks/`/`results/` (superseded by
`.work/`); `.orchestration/contracts/` is kept as the live cross-language
protocol contract test until `epic-bold-generated-protocol` retires it.

Open questions live in `docs/SPEC.md` → "Open questions" until resolved; once
resolved they move here.

## Origin and positioning

- **Product target**: the [Pi coding agent](https://github.com/earendil-works/pi).
  Pi-only. Not Claude Code (has official Remote Control), not OpenCode (has
  5+ community mobile apps), not Goose/Aider (small market). Pi is the most
  relevant open-source competitor to Claude Code, has public RPC + SDK, and had
  no dedicated mobile app — the niche Remote Pi fills.
- **Not MuxAgent**: it covers multi-harness commercial. Remote Pi is Pi-only,
  open source, quality-first.

## Fork posture (locked)

- **Private-carry fork.** `KevounC/remote_pi` is a private fork of
  `jacobaraujo7/remote_pi`. Upstream is read-only comparison/reference; work
  is pushed only to `origin`. No upstream PRs unless the operator explicitly
  asks.
- **The bold refactor is fork-local.** No upstream-compatibility constraints
  apply to the reconception — the generated protocol schema, canonical session
  model, typed relay actor, etc. are private-carry and need not stay
  shareable with upstream's hand-maintained mirrors.
- **Patchbay is the long-term play.** The bold refactor hardens the fork's
  structure in the short term; patchbay is the intended successor direction
  beyond carrying this fork. Bold-refactor design should avoid decisions that
  block a future patchbay migration (e.g. don't bake fork-specific assumptions
  into the canonical schema in ways that wouldn't travel).

## Architecture

| Decision | Current truth |
|---|---|
| **Daemon is GA, first-class** | A substantial `pi-extension/src/daemon/` module ships: `supervisor`, `supervisord` CLI, `cron_registry`/`cron_log`, `rpc_child`, `install`, `registry`, `id`, `client`. The MVP-era "no daemon" scoping was explicitly revisited and shipped. (Originally an MVP-scoping decision; superseded by the daemon-mode plan that shipped.) |
| **Extension, not wrapper** | Pi has a TypeScript extension API. The extension consumes the Pi SDK directly — no wrapper process. (Future harness support — Claude Code, OpenCode — would come via wrappers like `remote-pi claude`, not by re-targeting the extension.) |
| **Auto-start relay is optional** | Config `auto_start_relay=true` connects to the relay automatically when Pi opens. Daemon config forces this on. |
| **Relay: stateless routing + narrow mesh-membership persistence** | The relay is stateless for message routing — no per-session state, no offline queue, no at-least-once delivery. It has a narrow persistence layer: the SQLite-backed `MeshStore` (the Owner-signed `mesh_versions` cartulary, LWW + monotonic-version anti-rollback) plus ephemeral in-memory `PeerRegistry`, `PresenceManager`, `RoomManager`, and `FirehoseMetrics`. (The MVP-era "relay stateless, no persistence" line is superseded — mesh membership is persisted.) |
| **Relay is open-source + self-hostable** | Credibility commitment. A paranoid user runs their own. The public relay is not a single point of compromise for an operator who self-hosts. |
| **No offline message queue** | If a peer is offline, the sender gets `transport_error: offline` immediately. In-memory queued-message state is a short Pi-side buffer for prompts held during an active turn, lost on restart. |
| **Cross-PC is relay-mediated** | Direct PC-to-PC (WebRTC/QUIC) is long-term roadmap; the relay becomes the fallback then. |

## Pairing

| Decision | Current truth |
|---|---|
| **Persistent, not ephemeral** | Peers saved in `peers.json` (PC) + Keychain/Keystore (mobile). Pair-once, reconnect-forever. Ephemeral-per-session and ephemeral-per-pairing were rejected as hostile UX. |
| **No account** | QR pairing only. An optional account is deferred until multi-device sync or recovery pain demands it. |
| **Ephemeral QR (60s, rotating)** | Short window reduces photo/screenshot leak risk. Single-use token. |
| **Optional safety number** | 6-emoji bilateral (Signal-style) to visually confirm pairing wasn't MITM. |
| **Forward secrecy** | ECDH ephemeral per reconnect. Long-lived Curve25519 key only authenticates identity. |
| **Identity = pubkey** | No username. Relay auth via Ed25519 challenge-response. |
| **Pairing lifetime** | Until someone revokes. |
| **Revoke in app** | Settings list with swipe-to-delete + confirmation modal. |
| **Cross-side signaling on revoke** | Implicit: revoked side clears local storage; other side detects via `error{unknown_peer}` on next reconnect. No dedicated `revoke_pair` wire type. |

## Session and reachability model

| Decision | Current truth |
|---|---|
| **1 active connection per `(peer, room)` at the extension; broadcast-fanout at the relay** | The extension's `_peerChannel` is a singleton per room. Multiple devices with the same Owner-key can coexist connected and receive the same message — the fanout happens at the relay, which distributes one outbound envelope. Skip-sender via `from_conn_id` avoids echo. |
| **Session identity is a designed-then-dropped regression — being restored** | The wire protocol *designed* `session_id` on every push message (the absorbed project's protocol spec specified it on `agent_chunk`, `agent_done`, `tool_request`, `tool_result`). It was dropped during MVP scoping ("1 pairing = 1 session"), and the `app/lib/protocol/protocol.dart` even comments it: *"1 pairing = 1 session: no session_id on any message."* That assumption broke down once multi-session/multi-peer arrived and produced the cross-session contamination class of bug (a foreign `session_history` overwrites the active session's message box). `epic-bold-canonical-session` restores the discriminator: canonical `session_id`, required, fail-closed, opaque to the relay (carried, not learned). This is restoration of a designed invariant, not invention. |
| **Reachability is one contract, not five** | The same backoff `[1, 2, 5, 10, 30]` and ping cadences are reimplemented independently in the extension, app, and relay heartbeat. `epic-bold-reachability-contract` lifts the app's `ConnectionStatus` sealed class to a shared `Reachability` contract adopted by all three. (Currently duplicated; refactor in flight.) |

## Wire protocol

| Decision | Current truth |
|---|---|
| **Handwritten mirrors in four places — being unified** | The wire is defined as hand mirrors in TS (`pi-extension/src/protocol/types.ts`, the de-facto source today), Dart (`app/lib/protocol/protocol.dart`, ~1313 lines), Rust (`relay/src/protocol/outer.rs`), plus a fourth private NUL-prefix control RPC between cockpit and pi-extension. Drift is already biting (the TS `SERVER_TYPES` registry omits several live types). `epic-bold-generated-protocol` replaces this with a single canonical schema + generated TS/Dart/Rust. The hand-maintained `.orchestration/contracts/` (protocol.md + fixtures) is the *current* cross-language contract test and stays until the generated schema replaces it; the codegen becomes the new contract test. |
| **Framing** | JSONL (LF-delimited), UTF-8. |
| **Envelope (mesh + cross-PC)** | `{from, to, id, re, body}` with UUIDv7 ids. Local UDS and cross-PC relay forwards use the same envelope shape; cross-PC wraps it in `pi_envelope`/`pi_envelope_in` frames carrying `to_pc`/`from_pc` Pi-pubkeys. |
| **Cockpit↔pi control RPC** | Separate transport: Pi custom events carrying a NUL-prefixed string (`\x00remote-pi-ctrl:...`). Folded into the generated schema by the bold refactor to retire the magic prefix. |
| **No protocol version field** | v1 implicit. Add `v` only when v2 surfaces and requires migration. |
| **1 MiB message limit** | Relay rejects larger. |
| **ErrorCode is open** | `KnownErrorCode | (string & {})` — receivers tolerate unknown codes for forward-compat. |

## Crypto and trust

| Decision | Current truth |
|---|---|
| **No E2E today; TLS only** | Transport is TLS. The relay sees plaintext envelope contents. No product copy claims E2E. (Noise XX / Curve25519 + ChaCha20-Poly1305 was designed then rolled back as an MVP bottleneck; re-enabling is roadmap-additive and must not change the envelope shape — only the `ct` generator/parser.) |
| **Self-hosting is the mitigation** | For an operator who needs confidentiality from the relay, run a self-hosted relay (open source, ~one Rust binary). |
| **Ed25519 everywhere for identity** | Owner-key signs `mesh_versions`; Pi-key authenticates to relay and signs cross-PC envelopes; App-key is ephemeral per pairing. |
| **One Pi-key per PC** | Hardware change = re-pairing. No Pi-key migration; Owner-key (mobile, synced via system Keychain) compensates. |
| **Relay never decides membership** | It forwards between Pi-siblings of the same Owner (verified via Owner signature on `mesh_versions`) and verifies signatures, but never adjudicates who is in the mesh. |
| **Anti-spoof between Pis** | Broker rejects envelopes where `envelope.from` prefix doesn't match the authenticated `from_pc` pubkey's `pc_label`. |
| **Anti-rollback membership** | Monotonic version + signature prevents relay/attacker from regressing the mesh. |
| **No quantum-safe** | Curve25519 is vulnerable to a stable quantum computer. Switch to Kyber when it becomes a real concern (not 2026). |

## Approval and operational security

| Decision | Current truth |
|---|---|
| **Tool approval removed from the extension** | Tool calls execute directly. The Pi SDK has no native per-tool `requiresApproval` field, and a hardcoded gate (Bash/Edit/Write) forced approval on all custom-package tools — noisy and non-scaling. The app keeps dormant approval infra (`ToolRequest` + approval card) for forward-compat. `tool_result` is still sent for transparency. Re-enable via a future plan when the Pi ecosystem standardizes permissions. |
| **No push notifications** | Cut to avoid APNs ($99/yr cert), FCM SDK, push-token management. Reconnection is on-demand when the user opens the app. (Additive when it returns; schema unchanged; relay decorates `tool_request` with push fire.) |

## Distribution

| Decision | Current truth |
|---|---|
| **Mobile app: dual distribution** | iOS = App Store. Android = Play Store (AAB) + direct APK (`RemotePi.apk` on GitHub Release `app-v*`, linked from site `/download`). Store-ready artifacts verified at `1.1.0+5`. CI covers only the direct APK. |
| **Cockpit: out of stores** | Notarized DMG (macOS) + unsigned EXE (Windows, SmartScreen documented) + deb/rpm (Linux x64+arm64) via GitHub Release `cockpit-v*`. |
| **Binary hosting** | GitHub Release assets (product-prefixed tags; monorepo as pure storage). VPS without SSH → `rp-s3` serves only `latest.json` per product; operator positions the manifest manually = publication gate. |
| **Self-update** | Cockpit macOS/Windows self-update via Sparkle/WinSparkle (`auto_updater`): background download, "restart to install" card, swap + relaunch. Linux stays manual-notify. The rp-s3 manual publication gate still applies (now also covers `appcast-{macos,windows}.xml`). Site `/download` and in-app card read `latest.json` as fallback. |

## Deferred (decide when triggered)

| Item | When |
|---|---|
| Protocol versioning (`v` field) | When v2 surfaces and requires migration |
| Optional user account | When multi-device sync/recovery pain demands it |
| Push notifications | When MVP is validated; additive, schema-unchanged |
| Multi-relay / federation | Probably never — only if the public relay becomes a bottleneck |
| Native apps (Swift/Kotlin) over Flutter | Probably never — reconsider only if Flutter blocks a critical feature (e.g. deep iOS Keychain integration) |
| Clone detection (two PCs, same Pi-key) | Not yet implemented; roadmap — alert when two WS with the same Pi-pubkey appear from different IPs |

## How to update this file

- **New decision locked in conversation** → add a bullet to the right section.
- **Decision changed** → rewrite the line in place as current truth. Do not
  strike-and-append unless the rejected alternative is one a future agent
  might re-open (then record it inline as rejected, with the one-line reason).
- **Decision deferred** → move to "Deferred."
- Do not edit this file silently during implementation. Decisions are locked
  in explicit conversation.
