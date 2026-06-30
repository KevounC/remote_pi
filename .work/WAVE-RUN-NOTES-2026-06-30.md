# Wave run notes — bold-refactor autopilot drainer (2026-06-30)

Transient run log for the autopilot draining pass. Lives at `.work/` root
(transient, no frontmatter required). Delete when the campaign completes.
Per dispatch-economy capsule, dispatch rationale lives here when it affects
bundling/wave width.

## Environment (resolved this session)

- Flutter: `~/projects/remote_pi/.tools/flutter` (not on PATH; call binary directly)
- Pub cache: `~/projects/remote_pi/.pub-cache` (gitignored, writable; default
  `/home/agent/.pub-cache` is read-only)
- `app/`: `flutter pub get` online OK (no git deps).
- `cockpit/`: `flutter pub get --offline` REQUIRED (3 git deps from
  github.com/jacobaraujo7/* can't clone — global git insteadOf rewrites
  https→ssh, no SSH key; bare mirrors in .pub-cache/git/cache/ resolve offline).
- Known-unrelated analyze info: `axisAlignment` deprecated at
  `app/lib/ui/chat/widgets/input_bar.dart:802` — do not fail reviews on it.
- **pi-extension pnpm**: `/home/agent/.cache` is read-only; pnpm 11.x fails with
  `[ERR_SQLITE_ERROR]` unless store/caches are redirected. Use:
  `export PNPM_HOME=~/projects/remote_pi/.pnpm-store npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`
  + `corepack pnpm install --store-dir ~/projects/remote_pi/.pnpm-store` if
  node_modules missing. `/home/agent/.npmrc` is a broken char device (harmless
  EACCES warning — ignore). `pnpm test` full suite has known env UDS/cwd-lock
  failures (EPERM on /tmp/claude/*.sock); rely on typecheck + targeted vitest.
- **relay cargo**: clean `cargo clippy --all-targets` passes (a stale build
  artifact can make first-run clippy look red; rebuild clears it).
- node codegen (`tools/protocol-codegen/bin/protocol-codegen.mjs`): works,
  node v24.18.0.

## Wave 1 — launched 2026-06-30 (5 parallel, openai-codex/gpt-5.5)

Re-work of 5 of the 7 bounced stories. Disjoint ownership → safe parallel writes.

| Agent | Story | Subproject | Owns |
|---|---|---|---|
| dbe7b9bb | cockpit-workspace-projection-settings-split-step-3 | cockpit/ | connectivity panel + test (fake VM/gateway coverage) |
| 03d2f8c1 | split-pi-extension-index-composition-root-step-3 | pi-extension/ | index.ts wiring of legacy_ports adapters |
| 09224f9a | generated-protocol-dart-codegen-step-2 | app/+tools/ | protocol.g.dart regen match |
| 32d03993 | canonical-session-identity-model-step-4 | relay/ | outer.rs fail-closed + remove session_id from RoomMeta |
| b4c08246 (queued) | transcript-event-log-projection-derive-step-3 | app/ | sync_service.dart 3 fixes |

## Wave 1b — deferred (file collisions with Wave 1)

Run after the colliding partner lands:
- generated-protocol-rust-codegen-step-2 (relay) — collides on outer.rs with
  identity-model-step-4. Waits for 32d03993.
- canonical-session-wire-discriminator-step-3 (app) — collides on
  sync_service_test.dart/ws_transport.dart with transcript-projection-derive.
  Waits for b4c08246.

## Review pass

After Wave 1+1b land, run fresh-context gpt-5.5 reviews on each (cross-model
advisory; stories fast-advance on verification). Contract: approve →
review→done + `## Review`; bounce → review→implementing + `## Review bounce`;
commit `review: <slug> (<verdict>)`.

## Coordination rules given to every agent
- cwd is /home/agent/projects/remote_pi (NOT forks/).
- Stage files explicitly; NEVER `git add -A`/`git add .` (avoid staging .key/.pem).
- Leave .key/.pem untracked.
- Use the exact flutter/pnpm/cargo incantations above.
