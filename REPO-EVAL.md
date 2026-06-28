# Repository Evaluation: Remote Pi

## Summary

Remote Pi is a polyglot monorepo for a mobile/desktop remote-control surface around the Pi coding agent: Flutter mobile app, TypeScript Pi extension, Rust relay, Flutter desktop cockpit, Next site, and a small Rust download server. The codebase has strong local test assets, explicit agent/reference docs, and thoughtful lifecycle/state-machine work, but it is held back by manual cross-language protocol mirroring, stale security documentation, no routine CI test gate, and several large convergence files.

Verified roots: `pi-extension/`, `app/`, `relay/`, `cockpit/`, `site/`, and `rp-s3/`. Major tracked source is roughly 100k lines excluding generated/build/dependency dirs, with regex-counted test declarations around 678 TS test/describe calls, 592 app Dart test/group/widget calls, 158 cockpit Dart test/group/widget calls, and 85 Rust relay test attributes.

This report is an initial repo-eval pass to inform `feature-adversarial-codebase-review`; it intentionally does not create `.work/` items.

---

## Scorecard

| Dimension | Score | Evidence |
|-----------|-------|----------|
| Architecture & Design | 6/10 | Clear subproject boundaries and ports/adapters guidance, but protocol/state contracts are hand-mirrored across TS/Dart/Rust and `pi-extension/src/index.ts` is 4,214 LOC. |
| Code Quality | 7/10 | Strict TypeScript configs, idiomatic relay with no `unsafe`, and many typed models; reduced by large files, default Dart linting, and manual protocol casts. |
| Error Handling | 6/10 | Relay/TS boundaries often fail fast, but Dart transport has silent broad catches around malformed frames and reconnect paths. |
| Testing | 6.5/10 | Strong local unit/integration coverage in core app/extension/relay surfaces; no full-stack app↔relay↔extension E2E or mobile lifecycle harness. |
| Documentation | 6.5/10 | `PROTOCOL.md`, `AGENTS.md`, `.agents/skills/`, and subproject guidance are unusually strong; public READMEs still contain stale E2E/security claims and ACK drift. |
| CI/CD & Automation | 4/10 | GitHub Actions only cover app/cockpit release packaging; no normal lint/test/build matrix or dependency audit automation was found. |
| Security Posture | 6/10 | No obvious committed secrets, no Rust unsafe, Ed25519 auth/trust model is documented; no dep-audit automation and stale E2E claims remain. |
| Developer Experience | 6.5/10 | Per-subproject commands and references are discoverable; no root task graph/toolchain pins, cockpit README is a Flutter stub. |
| Maintainability | 6/10 | Good rules/skills surface and cohesive subdirectories; protocol drift risk, generated file tracking, and very large files raise long-term cost. |
| **Overall** | **6.1/10** | Weighted per repo-eval rubric: Architecture and Code Quality count 1.5x. |

---

## Dimension Details

### 1. Architecture & Design — 6/10

**Verified positives:**
- Clear monorepo roles are documented in `AGENTS.md`, root `README.md`, and subproject `CLAUDE.md` files.
- `app/lib/data/transport/connection_manager.dart` has an explicit connection/retry state machine and owns timers/subscriptions.
- `relay/src/handlers/peer.rs` separates auth, registration, presence/rooms, and routing loops; `relay/src/rooms.rs` centralizes relay room metadata.

**Verified concerns:**
- Wire protocol facts are manually mirrored in `pi-extension/src/protocol/types.ts`, `app/lib/protocol/protocol.dart`, and relay JSON handling; no schema/generator or cross-language conformance source was found.
- `pi-extension/src/index.ts` is 4,214 LOC and mixes lifecycle, commands, relay state, session state, and CLI/test stubs.
- Cockpit has a 1,982 LOC `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart` and several 900+ LOC widgets.

**Verification notes:**
- Agent A and Agent B independently flagged cross-language protocol duplication as the main architecture risk.

### 2. Code Quality — 7/10

**Verified positives:**
- `pi-extension/tsconfig.json` and `site/tsconfig.json` both set `"strict": true`.
- `relay/src` and `rp-s3/src` contain no `unsafe` matches and no raw `println!`/`eprintln!` matches in production source.
- `pi-extension/src/protocol/types.ts` uses discriminated unions for client/server messages, action names, models, and thinking levels.

**Verified concerns:**
- Exact TS `any` search found `Model<any>` usages in `pi-extension/src/actions/handlers.ts`; not broad `as any`, but still an SDK generic escape hatch.
- `app/lib/protocol/protocol.dart` is 1,313 LOC of hand-written casts/parsing around shared wire data.
- `app/analysis_options.yaml` and `cockpit/analysis_options.yaml` are mostly default `flutter_lints`; `debugPrint` appears 21 times in app/cockpit source.

**Verification notes:**
- Agent B reported “0 `any`” in the sense of no `: any` / `as any`; direct verification found `Model<any>` generic occurrences. This does not materially change the score.

### 3. Error Handling — 6/10

**Verified positives:**
- `pi-extension/src/protocol/codec.ts` validates JSON shape and known server `type` before returning typed messages.
- `relay/src/handlers/pi_forward.rs` returns typed transport errors for bad envelope/offline/not-authorized scenarios.
- `cockpit/lib/app/core/domain/result.dart` provides an explicit `Result` model used across daemon/relay/LSP adapters.

**Verified concerns:**
- Agent B identified silent Dart frame dropping in `app/lib/data/transport/peer_channel.dart` and broad catches in `ConnectionManager` paths; this can turn malformed relay frames into stalled UX with little observability.
- Relay production code uses `Mutex::lock().unwrap()` / `.expect("mesh store mutex poisoned")` in shared registries/stores; acceptable for fail-fast services, but a poison panic can become relay-wide outage.
- `rp-s3/src/main.rs` panics on bind/server/signal setup rather than returning polished errors.

### 4. Testing — 6.5/10

**Verified positives:**
- Test inventory is broad: 33 pi-extension test files, 59 app Dart test files, 20 cockpit test files, relay integration tests under `relay/tests/`.
- Representative tests cover high-risk behavior: stale SDK contexts, working-state propagation, rooms/presence, mesh auth, cross-PC forwarding, and connection retry behavior.
- No tautological `expect(true)` pattern was found in the sampled searches.

**Verified concerns:**
- No `integration_test/`, `e2e/`, Playwright/Cypress, or full app↔relay↔extension harness directory was found.
- `site/` and `rp-s3/` have no test/spec files.
- Several async tests use sleeps/timeouts (`Future.delayed`, `tokio::time::sleep`), which may become flaky under CI load.

**Verification notes:**
- Agent C’s exact counts differed from direct regex counts because `describe`/`group` and test attributes were counted differently. The score uses the qualitative inventory, not exact counts.

### 5. Documentation — 6.5/10

**Verified positives:**
- `PROTOCOL.md` is a detailed canonical trust/protocol surface and explicitly states there is no app-layer E2E encryption today.
- `.agents/rules/` and `.agents/skills/*/SKILL.md` provide high-quality, current agent-facing references.
- `pi-extension/README.md` and `relay/README.md` are substantial human-oriented setup/reference docs.

**Verified concerns:**
- `site/README.md:4-5` still says “end-to-end encrypted channel.”
- `pi-extension/README.md:241` still says payloads are end-to-end encrypted between Pi and paired device.
- `pi-extension/CLAUDE.md:21` mentions `libsodium-wrappers`, while `pi-extension/package.json` only declares `@noble/ed25519` for crypto.
- `PROTOCOL.md:84` describes `busy` as normal drop/retry behavior, while `pi-extension/src/session/tools.ts:91` says delivery is reliable and line ~269 says current broker never returns `busy`.

### 6. CI/CD & Automation — 4/10

**Verified positives:**
- `.github/workflows/app-release.yml` and `cockpit-release.yml` are serious release pipelines with signed artifact generation, checksums, and release manifests.
- Lockfiles are present for pnpm, Cargo, and Flutter subprojects.

**Verified concerns:**
- No normal PR/push CI workflow was found for `corepack pnpm test`, `flutter test`, `cargo test`, `pnpm lint`, or equivalent.
- No dependency audit automation (`dependabot`, `renovate`, `cargo-deny`, `pnpm audit`, Snyk/OSV) was found outside incidental text.
- No root monorepo task graph exists to run all subproject checks consistently.

### 7. Security Posture — 6/10

**Verified positives:**
- Direct secret scan found only test tokens/placeholders, no obvious committed real secrets.
- Relay code has no `unsafe` matches; cryptographic identity/auth is described in `PROTOCOL.md` and implemented around Ed25519.
- Root README and canonical protocol admit the relay operator can see payload content and recommend self-hosting.

**Verified concerns:**
- Stale E2E claims in `site/README.md` and `pi-extension/README.md` are security-significant documentation bugs.
- No dependency auditing automation was found.
- Silent decode drops in app transport reduce observability for malformed/injected traffic.

### 8. Developer Experience — 6.5/10

**Verified positives:**
- `AGENTS.md` and subproject `CLAUDE.md` files list correct local verification commands.
- The repo has stack-specific agent skills for TS/Pi extension, Flutter mobile, Rust relay, Flutter desktop, and Next site.
- `pi-extension/package.json` and `site/package.json` have standard scripts.

**Verified concerns:**
- No root command wraps the full monorepo verification matrix.
- No `.editorconfig`, `.nvmrc`, `.node-version`, or `rust-toolchain.toml` was found.
- `cockpit/README.md` is still the default Flutter “A new Flutter project” stub.

### 9. Maintainability — 6/10

**Verified positives:**
- Durable agent/reference surfaces are unusually strong and current.
- Most subprojects have coherent domain/data/ui or handler/protocol/session subdivisions.
- Regression tests encode many historical lifecycle bugs.

**Verified concerns:**
- Manual wire protocol mirroring across languages is the primary drift risk.
- Large files (`pi-extension/src/index.ts`, `cockpit_viewmodel.dart`, `app/lib/protocol/protocol.dart`) concentrate too many responsibilities.
- `cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart` is a tracked generated file; acceptable if intentional, but it should remain regenerated by a documented script.

---

## Verification Summary

| Check | Result | Notes |
|-------|--------|-------|
| Git status clean | PASS | `git status --short` returned empty. |
| CI exists | PARTIAL | Two GitHub workflows exist, both release-oriented (`app-release`, `cockpit-release`). |
| Routine lint/test CI | FAIL | No workflow command matches for `flutter test`, `cargo test`, `pnpm test`, `pnpm lint`, etc. |
| Lockfiles exist | PASS | `pi-extension/pnpm-lock.yaml`, `site/pnpm-lock.yaml`, `relay/Cargo.lock`, `rp-s3/Cargo.lock`, app/cockpit `pubspec.lock`. |
| TypeScript strict | PASS | `pi-extension/tsconfig.json` and `site/tsconfig.json` set `strict: true`. |
| Linter configured | PARTIAL | Site ESLint and Flutter lints exist; no root lint matrix or custom Dart strictness. |
| Rust unsafe | PASS | No `unsafe` matches in `relay/src` or `rp-s3/src`. |
| Risky Rust panics/unwraps | PARTIAL | Production `Mutex::lock().unwrap()`/`expect` appears in relay shared state; many other unwraps are tests. |
| Test inventory | VERIFIED | Direct regex counts: 678 pi-extension, 592 app, 158 cockpit, 85 relay; exact counts are approximate. |
| E2E/integration harness | FAIL | No `e2e/`, `integration_test/`, Cypress, or Playwright dirs found. |
| README/docs exist | PASS | Root, pi-extension, relay, app, cockpit, site, rp-s3 docs exist; cockpit README is a stub. |
| Security copy consistency | FAIL | Stale E2E claims remain in `site/README.md` and `pi-extension/README.md`; ACK busy semantics drift in `PROTOCOL.md`. |
| Secrets scan | PASS | Only placeholder/test tokens found in sampled tracked files. |
| Dependency audit automation | FAIL | No Dependabot/Renovate/cargo-deny/pnpm-audit automation found. |

14 checks run; 5 failed, 4 partial, 5 passed. No agent/direct-verification discrepancy changed a score materially.

---

## Top 5 Recommendations

1. **Add routine monorepo CI** (Dimension: CI/CD, current score: 4)
   Add a PR/push workflow that runs the documented checks for `pi-extension`, `relay`, `app`, `cockpit`, and `site`, at least in a staged matrix. Start with `corepack pnpm typecheck/test`, `cargo fmt --check && cargo clippy && cargo test`, `flutter analyze/test`, and `pnpm lint/build`.

2. **Create a protocol conformance source or generated contract path** (Dimensions: Architecture/Maintainability, current scores: 6/6)
   Reduce drift between `pi-extension/src/protocol/types.ts`, `app/lib/protocol/protocol.dart`, and relay control frames. Even a checked fixture suite consumed by TS/Dart/Rust would materially reduce risk before larger refactors.

3. **Fix stale security documentation immediately** (Dimensions: Documentation/Security, current scores: 6.5/6)
   Rewrite `site/README.md`, `pi-extension/README.md`, and `pi-extension/CLAUDE.md` to match `PROTOCOL.md`: TLS in transit, no application-layer E2E today, Ed25519 auth, no libsodium/Noise stack.

4. **Restore observability around dropped/malformed app frames** (Dimension: Error Handling, current score: 6)
   Review silent catches in `app/lib/data/transport/peer_channel.dart` and `connection_manager.dart`. At minimum, emit throttled diagnostics so reconnect/parser failures do not become invisible stalls.

5. **Split the largest convergence files along existing boundaries** (Dimensions: Code Quality/Maintainability, current scores: 7/6)
   Prioritize `pi-extension/src/index.ts`, `app/lib/protocol/protocol.dart`, and `cockpit_viewmodel.dart`. Keep behavior stable, add black-box tests first, and extract protocol/lifecycle/adapter responsibilities behind narrow ports.
