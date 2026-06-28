# Brief: Formal-rigor stack and mobile architecture for a Remote Pi reimplementation

## Context

Remote Pi is currently a multi-surface system: Flutter mobile app, Node/TypeScript Pi extension, Rust/Tokio relay, Flutter desktop cockpit, Next/React site, plus a small Rust artifact server. The local architecture routes a Flutter app and Pi extension through a Rust WebSocket relay, and routes local agent messages through an extension-managed UDS broker. Pairing/auth uses Ed25519 and TLS, but current payloads are not end-to-end encrypted from the relay operator's perspective. [local-remote-pi-readme]{1} [local-remote-pi-readme]{2} [local-remote-pi-readme]{3} [local-remote-pi-readme]{4}

The codebase's largest source surface is Dart/Flutter, followed by TypeScript and Rust. The mobile app and cockpit account for most Dart files; TypeScript owns the Pi extension/site; Rust is smaller but critical for relay routing and mesh membership. [local-remote-pi-file-inventory]{1} [local-remote-pi-file-inventory]{3}

## Executive recommendation

**Recommendation:** do not start by rewriting everything. Start by rewriting the *specification surface*:

1. **Normalize the current protocol doc first.** `PROTOCOL.md` still describes `busy` as dropped delivery, while current plan/tool docs say busy-drop was removed and mid-turn sends are reliably queued. Model checking a stale protocol would formalize the wrong system. [local-remote-pi-protocol]{5} [local-remote-pi-plan34]{1} [local-remote-pi-plan34]{2} [local-remote-pi-plan34]{3} [local-remote-pi-plan34]{4}
2. **Use TLA+ or Quint for dynamic distributed behavior.** Model agent send/reply, ACK/timeout, reconnect, room metadata, mobile attach/resume, mesh membership publication, and cross-PC forwarding. TLA+/TLC is the conservative default; Quint is plausible if developer ergonomics matter more than ecosystem maturity. [tla-tools]{2} [tla-tools]{3} [tla-tools]{4} [quint-docs]{1} [quint-docs]{2} [quint-docs]{4}
3. **Use Alloy 6 for relational invariants.** Model owner/pi/app identities, membership graphs, address uniqueness, allowed cross-PC routing relations, revocation, and anti-spoof constraints. Alloy's SAT-backed bounded search is a good fit for topology bugs. [alloy6]{1} [alloy6]{2} [alloy6]{3} [alloy6]{4}
4. **Bridge specs into property/conformance tests.** Add Rust `proptest` for relay/protocol state transitions and TypeScript `fast-check` for extension broker/message handling. [proptest-docs]{1} [proptest-docs]{2} [fast-check-docs]{1} [fast-check-docs]{2} [fast-check-docs]{3} [fast-check-docs]{4}
5. **Choose one schema source of truth.** For a rigorous rewrite, prefer Protobuf + Buf for protocol message definitions and compatibility checks, unless preserving human-readable JSON is a hard product requirement. Buf provides linting, generation, and breaking-change detection; Protobuf has Dart/Rust/TypeScript generation paths. [protobuf-buf-docs]{1} [protobuf-buf-docs]{2} [protobuf-buf-docs]{4} [protobuf-buf-docs]{5} [protobuf-buf-docs]{6} [protobuf-buf-docs]{7}
6. **Mobile choice:** Flutter is appropriate for a cross-platform polished app and the existing codebase, but it is not the most operator/agent-friendly choice for a from-scratch rewrite if the operator is more comfortable in TypeScript/Rust. For a rewrite, evaluate React Native/Expo TypeScript seriously; keep Flutter if migration cost and native-feeling cross-platform stability dominate.

## Stack inventory

| Surface | Current stack | Fit observation |
|---|---|---|
| `relay/` | Rust 2024, Tokio, Axum, SQLite, Ed25519, Serde | Good fit for small trusted routing/auth core and property testing. [local-remote-pi-manifests]{2} |
| `pi-extension/` | Node >=20, TypeScript ESM, Pi SDK, MCP SDK, `ws`, `zod`, `typebox`, keyring, noble Ed25519 | Good fit because Pi extension surface is Node/TS and agent-facing iteration is high. [local-remote-pi-manifests]{1} [local-remote-pi-agent-skills]{3} |
| `app/` | Flutter/Dart, provider/go_router/Hive/WebSocket/secure storage/crypto/scanner/media packages | Mature cross-platform mobile fit, but largest unfamiliar surface for this operator. [local-remote-pi-manifests]{3} [local-remote-pi-file-inventory]{1} |
| `cockpit/` | Flutter/Dart desktop shell with terminal/media/update/native integration | Significant Flutter investment; not central to first formal-methods pass. [local-remote-pi-manifests]{4} |
| `site/` | Next/React/Tailwind/TS | Ordinary web surface; not a formal-risk center. [local-remote-pi-manifests]{5} |
| `rp-s3/` | Small Rust Axum/Tokio artifact server | Low-risk support component. [local-remote-pi-manifests]{6} |

## What to formalize first

### 1. Agent-network delivery semantics

Model:

- addresses as opaque `<cwd>@<name>` plus optional `<pc>:` prefix;
- unicast vs broadcast/multicast;
- ACK status `received | denied | timeout`;
- reply correlation through `re`;
- peer mid-turn queuing;
- no self-send;
- cross-PC transport errors.

Reason: this is where observed swallowed-message risk lives. Also, the durable docs currently conflict on whether busy drops are possible. [local-remote-pi-plan34]{4}

Suggested safety properties:

- If sender receives `received`, the message is either in the recipient inbox or later consumed exactly once by the recipient harness.
- A reply with `re = x` is only delivered if a prior message with id `x` existed in the causal history.
- Broadcast never crosses folder or PC boundaries unless explicitly modeled as multicast.
- No peer receives its own unicast send.

Suggested liveness/fairness properties:

- If a delivered message sits in a live recipient's inbox and the recipient eventually takes a turn, the message is surfaced to that turn.
- Transport timeout does not imply semantic denial.

### 2. Mobile remote-coding state convergence

The project's own mobile checklist already states the right shape: authoritative snapshots, idempotent commands, replayable deltas, reconnect hydration. [local-remote-pi-agent-skills]{2}

Model:

- mobile foreground/background/resume as nondeterministic loss of live socket;
- room snapshot vs event delta;
- `working` true/false convergence;
- delayed or duplicate command replies;
- session replacement while old callbacks are in flight.

Reason: iOS and Android do not promise continuous background WebSocket execution. Android defers background CPU/network in Doze/App Standby; iOS can suspend backgrounded apps, and suspended apps do not get CPU time. [ios-android-background]{1} [ios-android-background]{2} [ios-android-background]{3} [ios-android-background]{4} [ios-android-background]{5}

Suggested safety properties:

- A stale cached `working: true` cannot render as live working after reconnect without fresh room confirmation.
- A delayed reply for session A cannot mutate the selected state for session B.
- Every command response is bound to `(peer, room/session, command id)`.

### 3. Mesh membership / identity / anti-spoof

Model:

- Owner-key, Pi-key, App-key roles;
- Owner-signed monotonic mesh versions;
- revocation/self-revoke;
- relay membership authorization;
- broker-side prefix anti-spoof.

Reason: current protocol already has crisp relational constraints and a signed membership graph. [local-remote-pi-protocol]{1} [local-remote-pi-protocol]{2} [local-remote-pi-protocol]{6} [local-remote-pi-protocol]{7}

Alloy is especially appropriate here because the hard questions are relational: which keys own which PCs, which labels are unique, which routes are legal, which revoked members can still appear in a stale cache, and whether any route permits spoofing. [alloy6]{1} [alloy6]{2} [alloy6]{3}

### 4. Relay backpressure and state ownership

Model/test:

- bounded vs unbounded queues;
- subscription dedupe;
- event firehose suppression;
- disconnect cleanup;
- room metadata merge-patch semantics.

Reason: local relay guidance records unbounded Tokio mpsc senders; new high-volume paths need explicit backpressure or suppression. [local-remote-pi-agent-skills]{6}

## Formal tool evaluation

| Tool | Best use in Remote Pi | Pros | Cons / cautions | Recommendation |
|---|---|---|---|---|
| TLA+ + TLC | Dynamic distributed protocol: delivery, reconnect, membership update races, room-state convergence | Mature, explicit-state checking, error traces, strong fit for distributed systems | Learning curve; specs can drift from code; state explosion | **Primary conservative choice** |
| PlusCal | Algorithm-shaped specs that translate to TLA+ | Easier imperative entry point for broker/relay algorithms | Can hide TLA+ concepts; still need TLA+ literacy for invariants | Use for first broker/ACK model if it accelerates adoption |
| Quint | TLA-like specs with modern syntax/tooling | State-machine oriented, type checking, simulator + model checkers, TLC backend | Smaller ecosystem than TLA+; need team comfort | **Strong candidate** if you want agent-friendly syntax |
| Apalache | Symbolic bounded checking / inductive invariant checking for TLA+/Quint | SMT-backed, can help with state explosion, supports bounded and inductive checks | Requires type annotations and Apalache-friendly spec style | Add after initial TLC/Quint models hit limits |
| Alloy 6 | Identity, membership, routing relations, topology invariants | SAT-backed bounded counterexample search; excellent for relational bugs; Alloy 6 has temporal features | Less natural for complex protocol liveness than TLA+ | **Use alongside TLA+/Quint**, not instead |
| Dafny/F*/Lean/Coq | Verified code/proofs | Strongest proof story | Heavyweight; poor fit for product-wide rewrite velocity | Defer unless writing a tiny verified crypto/protocol kernel |

TLA+ and Quint are both state-machine tools: TLA+ is the established path; Quint is more ergonomic and still connects to model checking. [tla-tools]{2} [tla-tools]{3} [quint-docs]{1} [quint-docs]{2} [quint-docs]{4} Apalache is complementary, not a replacement for thinking carefully about the model. It translates TLA+ into SMT-backed symbolic checks and supports bounded/inductive analyses. [apalache-docs]{1} [apalache-docs]{2} [apalache-docs]{3} [apalache-docs]{5}

## Mobile framework evaluation

| Option | Fit for Remote Pi | Rigor / agentic coding fit | Risks | Recommendation |
|---|---|---|---|---|
| Keep Flutter/Dart | Best for preserving existing app investment and a polished iOS/Android UI from one codebase | Statically typed, mature mobile ecosystem, platform channels for native APIs | Operator unfamiliarity; Dart less aligned with TS/Rust; still needs generated protocol/test bridge | **Best incremental path** |
| React Native + Expo + TypeScript | Aligns mobile with extension/site TS; strong agentic surface; Expo has TypeScript-first docs | Stronger operator familiarity; shared TS protocol client possible | Native lifecycle edge cases remain; RN WebSocket docs are thin; native modules still needed for keychain/notifications/background | **Best greenfield TS-first path** |
| Native Swift + Kotlin | Best lifecycle/platform correctness | Direct platform APIs; strongest store/background integration | Two apps; higher cost; less shared code | Use only if mobile lifecycle correctness dominates everything |
| Kotlin Multiplatform | Shared mobile business logic with native platform escape hatches | Good for shared domain/networking on mobile; Google-supported for Android/iOS business logic | Adds Kotlin ecosystem; does not align with TS/Rust preference | Consider for native-mobile team, not this operator's preferred stack |
| Thin native shell + Rust core | Strongest rigor for protocol/state-machine reuse | Rust owns core state; mobile UI thinner; property tests in Rust | FFI/build/release complexity; mobile plugins still platform-specific | Attractive long-term architecture, risky as first rewrite step |
| Tauri mobile | Rust-friendly mobile/webview path | Rust + web frontend, mobile support exists | Mobile support and native plugin story still require Kotlin/Swift; less proven for app-store mobile UX | Research spike only |
| Capacitor/Ionic | TS/web-first mobile shell | TypeScript UI and PWA path | WebView/mobile lifecycle/background WebSocket not solved by framework | Not preferred for Remote Pi control app |

Flutter is not an inappropriate choice. It is a mature cross-platform app framework, with one-codebase mobile/web/desktop positioning, Dart, a large package ecosystem, platform channels, and state restoration facilities. [flutter-docs]{1} [flutter-docs]{2} [flutter-docs]{3} [flutter-docs]{4} [flutter-docs]{5} The strongest argument *against* Flutter here is not technical unsuitability; it is operator familiarity and multi-language protocol drift. The app is the largest code surface, and Dart is not the operator's preferred agentic coding surface. [local-remote-pi-file-inventory]{1} [local-remote-pi-file-inventory]{3}

React Native/Expo is credible for a rewrite because Expo has first-class TypeScript support and React Native now has a default New Architecture and stronger TypeScript options. [expo-docs]{1} [react-native-docs]{1} [react-native-docs]{2} [react-native-docs]{4} But React Native does not eliminate mobile OS constraints. It still needs the same snapshot/reconnect/notification semantics, and the official WebSocket surface is thin compared with the importance of Remote Pi's transport. [react-native-docs]{5} [ios-android-background]{1} [ios-android-background]{5}

Kotlin Multiplatform is a credible mobile-domain sharing option, and Google describes it as stable/production-ready for shared Android/iOS business logic. [kmp-docs]{1} [kmp-docs]{2} But it does not match the operator's stated preference for TS/Rust surfaces.

Tauri mobile and Capacitor are worth knowing about, but neither should be the default reimplementation target for a control app whose hard problems are mobile lifecycle, native notifications, secure identity storage, and reliable reconnect. Tauri mobile requires Kotlin/Swift plugin work for native APIs; Capacitor supports web-to-native plugins and background runner patterns but does not make continuous background WebSockets a solved problem. [tauri-mobile-docs]{1} [tauri-mobile-docs]{2} [tauri-mobile-docs]{3} [capacitor-docs]{1} [capacitor-docs]{2} [capacitor-docs]{3} [capacitor-docs]{4}

## Schema / protocol source-of-truth evaluation

| Option | Pros | Cons | Recommendation |
|---|---|---|---|
| Protobuf + Buf | Mature schema IDL; Dart/Rust/TS generation exists; Buf handles lint and breaking checks | Binary-ish mindset; JSON envelope may need adaptation; not enough alone for semantic constraints | **Best rigorous rewrite default** |
| JSON Schema + generated types | Keeps JSON-friendly wire; AJV/TypeBox/Zod ecosystem; Rust can emit schemas via tools | Dart/Rust/TS roundtrip less clean; schemas do not capture semantic constraints alone | Good incremental path if preserving JSON wire |
| TypeScript-first Zod/TypeBox | Great for extension; already local dependencies | Rust/Dart become generated/secondary; risk TS-centric protocol authority | Good for extension-local validation, not whole-system SSOT |
| Rust-first Serde + schema export | Strong relay/core authority | TS/Dart codegen needs careful toolchain; mobile may feel downstream | Good if Rust becomes protocol core |
| OpenAPI/ConnectRPC/gRPC | Strong API tooling; Connect generates many clients | Remote Pi uses bidirectional WebSocket/control streams, not ordinary request/response HTTP only; Rust support needs separate evaluation | Use selectively for HTTP APIs, not as sole event protocol |

Buf/Protobuf is the cleanest formal rewrite baseline because it gives one checked schema artifact plus breaking-change detection. [protobuf-buf-docs]{1} [protobuf-buf-docs]{4} JSON Schema is still useful for the current JSON wire, especially with AJV/TypeBox/Zod, but this pass did not find an equally strong Rust+TS+Dart schema workflow. [json-schema-codegen-docs]{1} [json-schema-codegen-docs]{2} [json-schema-codegen-docs]{4}

Important caveat: schemas are not enough. Remote Pi's riskiest properties are temporal and semantic: delivery, correlation, freshness, revocation, reconnect, and session binding. Those require TLA+/Quint/Alloy plus conformance/property tests.

## Proposed rigorous reimplementation architecture

### Incremental architecture

```text
specs/
  agent_network.tla or agent_network.qnt
  mobile_session.tla or mobile_session.qnt
  mesh_membership.als
  relay_backpressure.tla/qnt
proto/ or schema/
  remote_pi.proto / buf.yaml
  generated snapshots checked in or generated in CI
relay/                  Rust implementation + proptest/conformance vectors
pi-extension/           TS implementation + fast-check/conformance vectors
app/                    existing Flutter app or RN rewrite + conformance vectors
```

### Development rule

Every protocol change should update, in order:

1. human protocol doc;
2. formal model if state semantics changed;
3. schema/IDL if wire shape changed;
4. generated types/codecs;
5. cross-language golden vectors;
6. property/conformance tests;
7. implementation.

## Disconfirming analysis

- **Against replacing Flutter:** Flutter is technically appropriate for cross-platform mobile and has official platform-channel/state-restoration support. A rewrite to React Native would improve operator familiarity but would not solve iOS/Android background restrictions by itself. [flutter-docs]{1} [flutter-docs]{4} [flutter-docs]{5} [ios-android-background]{1} [ios-android-background]{5}
- **Against making Alloy the primary dynamic protocol tool:** Alloy 6 has temporal operators, but TLA+/Quint are more directly shaped around state machines and distributed execution traces. Use Alloy where the problem is relational topology. [alloy6]{4} [quint-docs]{4} [tla-tools]{2}
- **Against Protobuf as a complete answer:** Buf/Protobuf can prevent schema drift and generated-code mismatch, but it cannot express all protocol liveness/freshness/session-binding invariants. Those remain model-checking and conformance-test concerns. [protobuf-buf-docs]{1} [protobuf-buf-docs]{4}
- **Against a full Rust-core mobile rewrite first:** A Rust core could concentrate rigor and property tests, but mobile FFI/platform plugin complexity is real and not eliminated by Tauri/Flutter/RN wrappers. [tauri-mobile-docs]{2} [flutter-docs]{4}

## Contradictions / drift found

1. **ACK semantics drift:** `PROTOCOL.md` says `busy` means a message was dropped and the sender retries. Current plan/tool docs say busy-drop was removed and a mid-turn peer still receives queued messages. This must be reconciled before any formal model is treated as authoritative. [local-remote-pi-protocol]{5} [local-remote-pi-plan34]{1} [local-remote-pi-plan34]{2} [local-remote-pi-plan34]{3}
2. **Relay privacy wording risk:** README and relay guidance agree there is no current E2E encryption and relay operators can see message contents. Any rewrite spec should keep this explicit until encryption is actually added. [local-remote-pi-readme]{4} [local-remote-pi-agent-skills]{5}

## Final position

For this operator's preferences, the best target architecture is:

- **Rust** for relay and any shared protocol/state-machine core.
- **TypeScript** for Pi extension and possibly mobile UI if greenfield.
- **TLA+/Quint** for dynamic protocol specs.
- **Alloy 6** for identity/membership/address invariants.
- **Protobuf + Buf** for cross-language wire schema if a rewrite is allowed; JSON Schema/TypeBox/Zod only if preserving JSON wire is a hard constraint.
- **Flutter retained short-term**, because existing investment is high and Flutter is technically appropriate.
- **React Native/Expo TypeScript considered for a rewrite**, because it aligns better with the operator's agentic coding surface, but only if migration cost is acceptable and mobile lifecycle semantics are modeled separately.
