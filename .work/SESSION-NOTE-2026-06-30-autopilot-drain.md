# Session note — 2026-06-30 — bold-refactor autopilot drain (env + Wave 1/1b + reviews)

Transient handoff note at `.work/` root (no frontmatter needed). Delete when
the bold-refactor campaign completes. Per `.agents/rules/agent-discipline.md`
this is NOT a durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands

Continued the bold-refactor autopilot drain from the 2026-06-29 review pass.
This session: resolved the dev-environment blockers, re-implemented all 7
bounced stories (Wave 1 + 1b), ran the review pass, and closed 6 of 7 to
`done`. The 7th (transcript-projection-derive-step-3) bounced a second time on
a working-state convergence gap, was re-fixed inline, and is at `stage: review`
under a fresh-context review (subagent `957158c6`, launched end of session).

**Story stage counts:**
- Before this session: 44 done / 0 review / 92 implementing / 4 drafting
- After: **50 done / 0 review / 86 implementing / 4 drafting**
  (6 stories advanced implementing→done via review; 1 bounced back, re-fixed,
  now awaiting its second review).

## Dev environment — RESOLVED (the big unblocker this session)

Project relocated `forks/remote_pi` → `projects/remote_pi`; Flutter SDK moved
into the repo. Verified working toolchain on this fresh sandbox:

- **Flutter**: `~/projects/remote_pi/.tools/flutter` (not on PATH; call binary
  directly). `/opt/flutter` is gone.
- **Pub cache**: `~/projects/remote_pi/.pub-cache` (gitignored, writable).
  Default `/home/agent/.pub-cache` is mounted READ-ONLY — always set
  `PUB_CACHE=~/projects/remote_pi/.pub-cache`.
- **`app/`**: `flutter pub get` online OK (no git deps). 1 known-unrelated
  analyze info: `axisAlignment` deprecated at
  `app/lib/ui/chat/widgets/input_bar.dart:802` — do NOT fail reviews on it.
- **`cockpit/`**: `flutter pub get --offline` REQUIRED. 3 deps are
  git-overridden from `github.com/jacobaraujo7/*` (`gpt_markdown`, `kyroon_pty`,
  `xterm`); a global git config rewrite
  (`url.git@github.com:.insteadof=https://github.com/`) forces HTTPS→SSH and
  there's no SSH key in this sandbox, so online clone fails
  `Permission denied (publickey)`. The bare mirrors in
  `.pub-cache/git/cache/<pkg>-<sha>/` resolve cleanly under `--offline`.
  **Keep that cache populated** — if cleared, cockpit goes back to failing
  until re-seeded.
- **`pi-extension/` pnpm**: `/home/agent/.cache` is READ-ONLY; pnpm 11.x fails
  with `[ERR_SQLITE_ERROR] unable to open database file` unless store/caches
  are redirected. `/home/agent/.npmrc` is a broken char device (harmless
  EACCES warning — ignore). Use:
  ```
  export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  export npm_config_cache=~/projects/remote_pi/.npm-cache
  export XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache
  corepack pnpm install --store-dir ~/projects/remote_pi/.pnpm-store  # if node_modules missing
  corepack pnpm typecheck
  corepack pnpm exec vitest run <path>   # full `pnpm test` has known env UDS/cwd-lock failures (EPERM on /tmp/claude/*.sock); rely on typecheck + targeted vitest
  ```
- **`relay/` cargo**: clean. (A stale build artifact can make first-run clippy
  look red; `cargo clippy --all-targets` rebuild clears it.)
- **node codegen** (`tools/protocol-codegen`): works (node v24.18.0).

**Durable docs updated** (commits `36accbf`, `2b904a9`/`4d393be`): the working
incantations are recorded in `cockpit/CLAUDE.md`, `app/CLAUDE.md`,
`pi-extension/CLAUDE.md`, and the `flutter-mobile`, `flutter-desktop-cockpit`,
`pi-extension-typescript` `.agents/skills/*/SKILL.md` references.

## Wave 1 + 1b — implement rework (7 bounced stories, all `openai-codex/gpt-5.5`)

Parallel implement subagents, disjoint file ownership. Coordination notes given
to colliding pairs (relay `outer.rs`, app `sync_service_test.dart`).

| Story | Implement commit | Outcome |
|---|---|---|
| dart-codegen step-2 | `cd283ba` | stale `protocol.g.dart` regenerated; regen diff empty |
| identity-model step-4 | `41da53b` | missing-room fail-closed; relay `session_id` removed; opaque-ct test (NOTE: hand-edited generated `outer.rs` — legitimized by rust-codegen below) |
| cockpit settings-split step-3 | `b2e3979` | 8 fake-gateway tests (load/save/check/disposal) |
| pi-extension composition-root step-3 | `30ec471` | `createLegacyIndexPorts` wired into `index.ts` |
| transcript-projection-derive step-3 | `7dc99eb` | 3 fixes (steer replyTo, tool args, buffer clear); 37→40 tests |
| rust-codegen step-2 | `e4ec27e` | `emitRustOuter()` schema-derived; moved identity-model's hand-edit into generator; regen diff empty |
| wire-discriminator step-3 | `98a88a6` | removed legacy no-room bypass; 4 regression tests; 40 tests |

## Review pass — fresh-context `gpt-5.5` (cross-model advisory)

7 parallel reviews. Verdicts:

| Story | Review commit | Verdict |
|---|---|---|
| dart-codegen step-2 | `88b3cda` | ✅ Approve → done |
| identity-model step-4 | `5901c0c` | ✅ Approve → done (regen-diff empty confirms generated contract intact post-both-stories) |
| cockpit settings-split step-3 | `facee68` | ✅ Approve → done |
| pi-extension composition-root step-3 | `ef506df` | ✅ Approve → done |
| rust-codegen step-2 | `26ed1b9` | ✅ Approve → done (generator truly schema-derived, not hardcoded+bolted) |
| wire-discriminator step-3 | `2fbcd9f` | ✅ Approve → done |
| transcript-projection-derive step-3 | `59f55d1` | ↩️ Request changes (2nd bounce) |

### The one outstanding bounce (transcript-projection-derive-step-3, 2nd)

The first-bounce 3 blockers were resolved and tests green (40), but the
reviewer found `clearActiveSession()` — having just been fixed to clear Hive +
the projection buffer — left `_working`/`_workingReplyTo`/`_streaming` stale.
Working-state convergence violation (Remote Pi's highest-risk invariant) at the
`session_new` wipe boundary.

**Re-fixed inline** (commit `1d7965d`): `clearActiveSession()` now calls the
existing `_resetTurnState()` to converge working state false. Added regression
test `clearActiveSession resets the in-memory turn state — working/streaming
converge false on a mid-turn session wipe (plan/32)`. Verification: analyze
clean (only known axisAlignment info); sync_service_test.dart All tests
passed! (41 = 40 + new regression). Story at `stage: review`; fresh-context
review subagent `957158c6` launched at end of session — **check its verdict
on resume** (approve → done, or bounce → implement again).

## Resume instructions (full autopilot queue drain)

1. **First**: harvest subagent `957158c6` (the transcript-projection-derive
   second-bounce review). If approve → story `done` (50→51). If bounce → small
   re-fix, re-review.
2. **Then: full autopilot queue drain.** ~86 stories still at `implementing`;
   probe the ready-set (all deps `done`) with the `stage_map` script in
   `.work/WAVE-RUN-NOTES-2026-06-30.md`. Last probe found ~18 ready beyond the
   bounce set. Bundle by disjoint file ownership, fan out `openai-codex`
   implement subagents (model explicit per AGENTS.md — spark for small,
   `gpt-5.5` for cross-file), harvest, run fresh-context `gpt-5.5` reviews.
3. **Watch the generated-contract invariant**: identity-model hand-edited a
   generated file; rust-codegen legitimized it. If any future story touches
   `relay/src/protocol/generated/*` or `app/lib/protocol/generated/*`,
   ensure the change is in the GENERATOR, not the generated file.
4. **Coordination rule (learned the hard way)**: do NOT run `git add`/`git
   commit` while parallel write-subagents are in flight — it can sweep in an
   agent's in-progress story transition. Let agents commit their own work;
   the orchestrator commits only its own notes/docs when no agents are writing.

## Run notes

Detailed wave/dispatch rationale lives in
`.work/WAVE-RUN-NOTES-2026-06-30.md` (the env incantations + agent IDs).

## Untracked secrets

`*.key` / `*.pem` in the working tree are local secrets — correctly untracked,
NEVER commit. Every subagent was instructed to stage files explicitly and
leave these alone; all complied.
