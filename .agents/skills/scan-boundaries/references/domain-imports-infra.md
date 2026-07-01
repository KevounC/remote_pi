# Rule: Domain Imports Infra

> Domain and core logic must not import infrastructure (transport, storage, platform APIs, SDK) directly. Define the port where the core lives; implement it at the edge.

## Motivation

Remote Pi is a multi-surface system (pi-extension, app, relay, cockpit, site) where the same
domain concept — a session, a transcript, a reachability state, a room — must be expressible
without depending on *how* it is transported, stored, or spawned. When a domain module imports
infrastructure directly, the domain becomes untestable without the infra (no fake transport, no
in-memory store), and a transport swap forces domain edits. The bold-refactor campaign
established clean ports in `app/lib/domain/contracts/` and generated typed frames in every
subproject's `protocol/generated/`. This rule keeps future releases from eroding those seams.

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Ports and Adapters.

## Signals

A file under a domain/core path imports any of:
- a transport module (`../transport/...`, `relay_client`, `pi_forward_client`, `peer_channel`)
- a storage/local module (`data/local`, `pairing/storage`, `node:fs`)
- a platform/SDK surface (`@earendil-works/pi-coding-agent`, `package:flutter/`, `dart:io`)
- a UI widget or route object (domain consuming its own presentation)

"Under a domain/core path" is defined per subproject in **Scope** below. This rule does NOT
fire in lifecycle/adapter/composition code — see Exceptions.

## Before / After

### From this codebase: the clean baseline (keep this)

**Current (correct) — `app/lib/domain/contracts/repository.dart`:**
```dart
import 'package:app/domain/contracts/disposable.dart';

abstract class Repository implements Disposable {
  @override
  void dispose() {}
}
```
`app/lib/domain/` as a whole imports **zero** infra modules — no `transport`, `mesh`, `local`,
`flutter`, or `dart:io` imports appear under `app/lib/domain/`. This is the posture to preserve.

### Synthetic example: a violation (in a domain/core path)

**Before (violation) — a hypothetical `app/lib/domain/repositories/session_repo.dart`:**
```dart
import 'dart:io';                                     // platform API in domain
import 'package:app/data/transport/relay_client.dart'; // transport in domain
```
Domain logic is now coupled to live transport and platform APIs.

**After (port):**
```dart
import 'package:app/domain/contracts/relay_transport.dart';  // the port
// SessionRepository receives RelayTransport via constructor; composition root wires the adapter
```

## Exceptions

- **Composition roots and lifecycle/adapter code** — `pi-extension/src/index.ts`,
  `pi-extension/src/session/**` (`mesh_node.ts`, `bridge.ts`, `broker.ts`, `cwd_lock.ts`,
  `leader_election.ts`, `local_config.ts`, `global_config.ts`, `setup_wizard.ts` construct/own
  relay+fs resources at session boundaries), `app/lib/main.dart`, cockpit module bindings —
  infra imports there are correct wiring. **`pi-extension/src/session/mesh_node.ts:6` value
  imports `RelayClient` and is NOT a violation of this rule** because it is composition code.
- **Test fixtures** — `*.test.ts`, `*_test.dart`, `relay/tests/**`, `#[cfg(test)]` blocks — may
  import infra to construct fakes/stubs.
- **Generated code** — `protocol/generated/`, `*.g.dart` — produced by codegen, not authored.
- **Opaque forwarding** — relay code forwarding an envelope unchanged may hold raw bytes; see
  `ad-hoc-wire-parse` for the precise boundary.

## Scope

Narrow per-subproject; over-broad globs produce false positives in lifecycle/adapter files:

- Applies to (domain/core paths only):
  - `app/lib/domain/**`
  - `cockpit/lib/**/domain/**` (narrow — NOT all of `cockpit/lib`)
  - `pi-extension/src/reachability/**` (except `*.test.ts`)
  - `pi-extension/src/mesh/**` (except `*.test.ts`)
  - `relay/src/protocol/**` authored non-generated modules (NOT `protocol/generated/**`)
- **Excluded** (composition/lifecycle/adapter sites — do NOT scan):
  - `pi-extension/src/session/**` — lifecycle/adapter/composition, not domain logic
  - `relay/src/handlers/**` — boundary/adapter code; legitimately import stores/registries
  - composition roots, test fixtures, generated code, `site/**`
