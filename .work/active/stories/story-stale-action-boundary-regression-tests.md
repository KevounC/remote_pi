---
id: story-stale-action-boundary-regression-tests
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-stale-session-bound-surface-deep-audit]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Add replacement-boundary regression tests for app action surfaces

## Brief

The deep stale-session-bound audit found that several app action surfaces are unit-tested in `actions/handlers.test.ts` but do not have extension-level replacement-boundary regressions. The current code guards or degrades these paths, but tests should pin that behavior so future stale `_pi` or stale ctx fallbacks do not reappear.

## Test targets

- `session_shutdown` → `model_set` returns controlled `internal_error` and does not call stale `_pi.setModel`.
- `session_shutdown` → `thinking_set` returns controlled `internal_error` and does not call stale `_pi.setThinkingLevel`.
- `session_new` → `session_compact` uses fresh `_lastEventCtx` / replacement context rather than stale `_lastCtx`.
- `session_new` → `list_models` uses fresh `getModel` / live registry when available, or degrades explicitly when not.
- `session_shutdown` → relay-state emission does not call stale `sendMessage` and does not log noisy `agent session not bound yet`.

## Acceptance

- Add the above extension-level tests or justify splitting any target into a follow-up.
- No production behavior change unless a test exposes a real gap.
- Targeted and full `pi-extension` verification passes.
