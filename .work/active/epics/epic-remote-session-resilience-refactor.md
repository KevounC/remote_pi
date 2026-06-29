---
id: epic-remote-session-resilience-refactor
kind: epic
stage: drafting
tags: [pi-extension, app, relay, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-27
updated: 2026-06-29
---

# Remote session resilience refactor

Bold refactor arc for Remote Pi's mobile/workstation remote-coding experience: make session state, mesh/relay semantics, and mobile UI state robust under reconnects, multi-client use, `/new`, dropped events, and long-running agent turns.

## Drivers

- Mobile and workstation can attach to the same remote Pi session, but session/control semantics need to be explicit and observable.
- A bug is already filed where mobile status can stay stuck on `Working` after the agent is idle: `.work/backlog/remote-pi-mobile-working-status-stuck.md`.
- The Pi extension and Flutter app likely both need state-machine cleanup rather than one-off patches.
- The full codebase should receive multi-model adversarial review before/alongside invasive changes.

## Arc sketch

Sequence the arc as **reference → review → design → refactor**, with only urgent narrow patches allowed to bypass the full track.

1. **Stabilize the agent substrate first.** Build enough platform-style reference surface for agents to reason correctly about the stack before asking them to review or refactor it:
   - `feature-agent-reference-surface`
   - `feature-mobile-remote-coding-best-practices-skill`
2. **Patch only small/high-confidence live bugs while research runs.** `story-mobile-working-status-stuck` may proceed as a narrow bugfix if reproduction is clear, but should record any architectural findings back into the epic rather than ballooning into the refactor.
3. **Run adversarial review after the first reference pass, before the bold refactor.** Reviewers should receive the new stack references, `PROTOCOL.md`, recent stale-context history, and the mobile/mesh best-practices checklist:
   - `feature-adversarial-codebase-review`
4. **Deduplicate and design the state-machine refactor.** Convert accepted findings into implementation stories grouped by boundary: pi-extension authoritative session/room state, app state/rendering, relay protocol/semantics, tests/smokes.
5. **Implement in thin vertical slices.** Prefer one observable session-state behavior per slice (`/new`, reconnect hydration, dropped turn_end, multi-client attach) with tests/smokes at each boundary.
6. **Final cross-model review + live soak.** Re-run focused adversarial review on the refactored paths and soak via real mobile/workstation use before considering upstream PRs.

## Initial decomposition

- `feature-agent-reference-surface` — platform-style language/library/dev-cycle references for Remote Pi agents.
- `feature-mobile-remote-coding-best-practices-skill` — targeted research + durable best-practices skill/checklist for mobile remote-coding mesh apps.
- `feature-adversarial-codebase-review` — multi-model adversarial review of app, pi-extension, relay, cockpit/site where relevant.
- `story-mobile-working-status-stuck` — reproduce and fix stale `Working` status.

## Reframing (2026-06-29 bold-refactor scan)

The bold-refactor scan superseded this epic's refactor framing. Arc steps 1-3
(reference → review → prep) shipped; step 4 ("design the state-machine refactor")
was the bold scan itself, which produced 8 `epic-bold-*` refactor epics that
collectively realize the resilience arc's intent.

This epic now tracks only the **residual targeted patches** that ship before the
bold refactor lands — work that doesn't need to wait for the architectural
reconception:

- `story-stale-command-ui-notify-guard` — safe command-notification helper
  (shippable slice; broader concern folds into `epic-bold-split-pi-extension-index`).
- `story-stale-action-boundary-regression-tests` — boundary regression tests
  that survive the refactor and inform it.
- `story-add-transport-frame-observability` — privacy-safe diagnostics for
  dropped frames (independent of the refactor).
- `feature-remote-pi-fork-vendor-and-mobile-surface` — fork setup / mobile
  build smoke (operational, not architectural).

Superseded children retired to `.work/archive/` with `status: superseded` and
folded into the bold epics that absorb them:

- `story-mobile-working-status-stuck` → `epic-bold-turn-state-machine-projection-consumers`
- `story-fix-cross-pc-bridge-late-attach-after-shutdown` → `epic-bold-split-pi-extension-index-sdk-session-projection-module` + `epic-bold-turn-state-machine-late-attach`
- `story-investigate-model-thinking-actions-after-session-replacement` → `epic-bold-split-pi-extension-index-sdk-session-projection-module`
- `feature-session-isolation-wire-discriminator` → `epic-bold-canonical-session-wire-discriminator`

Do not add new refactor-scale work here — route it through the bold epics. This
epic closes when its 4 residual survivors ship.

## Draft acceptance

- Clear architecture notes for authoritative session state, working/idle state, reconnect hydration, and multi-client behavior.
- Review findings are deduplicated and converted into scoped work items.
- Refactor is split into app and pi-extension implementation stories with verification plans.
