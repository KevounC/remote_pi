---
id: story-adversarial-security-privacy-review
kind: story
stage: done
tags: [pi-extension, relay, app, docs, workflow]
parent: feature-adversarial-codebase-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Security/privacy and relay abuse adversarial review

Run the security/privacy and relay-abuse pass for `feature-adversarial-codebase-review`.

## Scope

Review `PROTOCOL.md` trust model, relay auth/mesh membership, pi-extension pairing/key storage, cross-PC anti-spoofing, documentation claims, and dependency/audit posture.

Bias toward spoofed peers, replay/rollback, malformed frames, relay-visible plaintext, stale E2E claims, clone handling, keyring fallback, self-revoke, and abuse of relay routing/control frames.

## Output schema

```markdown
### <short title>
- **Severity**: critical|high|medium|low
- **Confidence**: high|medium|low
- **Evidence**: `path:line` plus quoted/summarized code/docs behavior
- **Failure scenario**: concrete abuse, privacy, or misleading-security scenario
- **Suggested routing**: patch|refactor|test-only|docs-only|uncertain
```

## Acceptance Criteria

- [x] Review separates documentation/security-copy findings from exploitable code findings.
- [x] Review avoids claiming E2E protections that `PROTOCOL.md` explicitly rejects.
- [x] Review labels threat-model assumptions and required operator decisions.

## Reviewer output — 2026-06-28

Read-only pass completed by subagent `c451d579-6693-47c`. No files were edited by the reviewer.

## Documentation / security-copy findings

### Stale E2E claim in site README
- **Severity**: high
- **Confidence**: high
- **Evidence**: `site/README.md` says the site describes controlling Pi from phone over an "end-to-end encrypted channel," contradicting `PROTOCOL.md`'s no-E2E trust model.
- **Failure scenario**: user believes public relay traffic is E2E and sends sensitive content through a relay operator who can read plaintext payloads.
- **Suggested routing**: docs-only, urgent.

### Stale E2E claim in root/pi-extension README surfaces
- **Severity**: high
- **Confidence**: high for `pi-extension/README.md`, needs orchestrator verification for root README.
- **Evidence**: `pi-extension/README.md` contains "payloads are end-to-end encrypted between the Pi and the paired device"; reviewer also claimed a root README stale occurrence, but the orchestrator must verify because `REPO-EVAL.md` earlier found root README mostly honest but potentially confusing around "opaque ciphertext."
- **Failure scenario**: stale security copy is reused in docs/support and creates false confidentiality expectations.
- **Suggested routing**: docs-only.

### `libsodium-wrappers` reference in `pi-extension/CLAUDE.md` is stale
- **Severity**: low
- **Confidence**: high
- **Evidence**: `pi-extension/CLAUDE.md` lists `libsodium-wrappers`; `pi-extension/package.json` uses `@noble/ed25519`; no libsodium dependency was found.
- **Failure scenario**: an agent follows stale crypto guidance and reintroduces wrong crypto assumptions/dependencies after the E2E rollback.
- **Suggested routing**: docs-only.

### ACK/reliability wording drift between `PROTOCOL.md` and agent tool description
- **Severity**: low
- **Confidence**: high
- **Evidence**: `PROTOCOL.md` still describes `busy` as normal drop/retry; `pi-extension/src/session/tools.ts` says current delivery is reliable and broker never returns `busy`.
- **Failure scenario**: future implementer adds obsolete retry/drop semantics or writes tests against stale protocol behavior.
- **Suggested routing**: docs-only.

## Exploitable / code findings

### Relay cross-PC auth cache uses stored mesh blobs without re-verifying signatures
- **Severity**: critical
- **Confidence**: high
- **Evidence**: `relay/src/handlers/pi_forward.rs` `MeshAuthCache::members_of()` parses raw blobs from `store.all_blobs()` and walks `members[].remote_epk`; `MeshStore::all_blobs()` returns only raw blob bytes, not signatures; read path does not call `verify_envelope()`.
- **Failure scenario**: compromised relay DB, malicious operator, or future write-path bug alters stored membership blobs; relay authorizes cross-PC traffic between arbitrary Pi keys despite invalid Owner signatures.
- **Suggested routing**: patch.

### Cross-PC `pi_envelope` forwards to every room of the destination peer
- **Severity**: high
- **Confidence**: high
- **Evidence**: `relay/src/handlers/pi_forward.rs` calls `registry.forward_to_peer(to_pc, msg)`; `PeerRegistry::forward_to_peer` iterates all `(peer_id, room_id)` entries matching the destination peer; `pi_envelope` has no `to_room` field.
- **Failure scenario**: multi-workspace PC receives one cross-PC envelope on every room connection, leaking metadata, amplifying fanout, and risking wrong-session delivery if names collide.
- **Suggested routing**: refactor.

### `peers.json` is written without explicit file permissions
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `pi-extension/src/pairing/storage.ts` writes `PEERS_PATH` without mode/chmod; file inherits umask though metadata contains Owner public keys, nicknames, and timestamps.
- **Failure scenario**: permissive umask on shared machine leaks paired-owner metadata to other local users.
- **Suggested routing**: patch.

### App transport silently drops malformed/injected server frames
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `app/lib/data/transport/peer_channel.dart` catches decode errors and drops silently; `app/lib/data/transport/ws_transport.dart` drops unknown/malformed frames via debug-only logging.
- **Failure scenario**: malicious/buggy relay suppresses specific frames or malformed traffic hides important state changes without user-visible indication.
- **Suggested routing**: refactor.

### No rate limiting on relay control-frame subscriptions and presence fan-out
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `relay/src/handlers/peer.rs` accepts control-frame peer lists without size/rate caps and uses unbounded senders for registry messages.
- **Failure scenario**: authenticated peer submits huge subscription/check lists and generates unbounded fanout/memory growth.
- **Suggested routing**: patch.

### `Mutex::lock().unwrap()` in relay shared state can panic the whole relay
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `relay/src/mesh/store.rs` and `relay/src/peers/registry.rs` use `Mutex::lock().unwrap()` / `expect` in shared state.
- **Failure scenario**: one panic while holding a shared mutex poisons future locks and turns a local bug into relay-wide outage.
- **Suggested routing**: refactor.

### Clone detection is not implemented
- **Severity**: medium
- **Confidence**: high
- **Evidence**: `PROTOCOL.md` explicitly lists clone detection as not implemented; relay permits multiple connections for the same Pi key.
- **Failure scenario**: exfiltrated Pi identity can run on another host and receive traffic without alert until owner notices and revokes.
- **Suggested routing**: patch/feature; already roadmap.

### Self-revoke and mesh-auth cache are eventual; revoked Pi keeps access for minutes
- **Severity**: medium
- **Confidence**: high
- **Evidence**: pi-extension self-revoke polls every 60s and relay positive mesh auth cache TTL is 60s.
- **Failure scenario**: after revocation, a peer may retain cross-PC/app access until cache and poller converge.
- **Suggested routing**: patch or documentation/UX; operator decision on acceptable revocation window.

### App resets version watermark when owner key changes, allowing rollback replay
- **Severity**: low
- **Confidence**: medium
- **Evidence**: app mesh sync `resetVersionWatermark()` sets `_lastVersion = 0`, so after owner-key replacement an older signed blob can be accepted for the new/current key context.
- **Failure scenario**: platform key-sync/restore confusion can re-accept an older valid blob and reinstate revoked Pis.
- **Suggested routing**: refactor/uncertain.

### `debugPrint` in app WebSocket transport logs metadata in release builds
- **Severity**: low
- **Confidence**: high
- **Evidence**: `app/lib/data/transport/ws_transport.dart` uses `debugPrint` with byte counts, sender room, and drop reasons.
- **Failure scenario**: platform logs reveal session metadata on managed/shared devices.
- **Suggested routing**: patch.

## No-finding notes from reviewer

- TLS in transit + Ed25519 challenge-response looked sound.
- Mesh POST signature verification and URL-hash consistency looked sound.
- Key material storage looked generally sound (OS keyring / secure storage with 0600 Pi fallback).
- Relay outer-envelope opacity looked sound for production relay routing.

## Dependency / audit posture

- No dependency-audit automation found (`dependabot`, `renovate`, `cargo-deny`, `pnpm audit`, `cargo audit`).
- No PR/push CI gate for routine `cargo test`, `flutter test`, `pnpm test`, or `pnpm lint`.

## Orchestrator verification targets

1. Verify the relay mesh-auth cache read path does not re-check Owner signatures and decide whether write-path verification is sufficient for the threat model.
2. Grep docs for stale "end-to-end" claims and correct/route each contradiction with `PROTOCOL.md`.
3. Verify `pi_envelope` has no room scoping and `forward_to_peer` fans out to every room for a destination peer.
