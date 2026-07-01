---
id: release-cockpit-v1.6.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-01
---

# Release cockpit-v1.6.0

First dogfood release of the gate-enabled substrate. Binds the cockpit-attributed
bold-refactor work: the workspace-projection epic (whole — parent + 3 child features)
plus 3 cross-component stories whose cockpit-only tag routes them here while their
multi-component parents ship later in the repo-level release.

## Bound items

### Active done items (7)
- epic-bold-cockpit-workspace-projection (epic)
- epic-bold-cockpit-workspace-projection-agent-session (feature)
- epic-bold-cockpit-workspace-projection-settings-split (feature)
- epic-bold-cockpit-workspace-projection-workspace-document (feature)
- epic-bold-generated-protocol-cockpit-control-rpc-step-3 (story — parent is repo-level)
- epic-bold-transcript-event-log-hydration-replay-step-4 (story — parent is repo-level)
- epic-bold-transcript-event-log-projection-derive-step-5 (story — parent is repo-level)

### Archived stubs late-bound
(none — all unbound archived stubs are multi-component → repo-level)

## Gate runs

### gate-refactor (2026-07-01) — 9 findings (0 high, 9 medium, 0 low) from 3 libraries

All findings medium confidence → stage: drafting (per gate_finding_routing default; Medium→drafting).
Untagged (libraries declare findings-route: none) → route through story/feature design.
Findings do NOT block this release (drafting is non-blocking; ship proceeds on bound items being done).

- boundaries (2): ambiguous-map-to-domain at rpc_event.dart (untyped wire blobs in domain events) + rpc_process_gateway.dart (respondUi takes raw Map)
- lifecycle (7): unguarded-async-void across workspace_projection, agent_composer, language_settings, cron_log_dialog, connectivity_settings, daemon_settings, schedule_settings (discarded futures / missing unawaited)
- protocol-contract (0): clean — no handwritten mirrors (cockpit consumes generated protocol correctly)

9 items written to .work/active/stories/gate-refactor-*.md. Grounding held: zero fabricated
file:line (the post-review grounding corrections paid off); two findings spot-verified as real.

(populated by remaining gates as they complete)

### gate-security (2026-07-01) — 3 findings (0 critical, 0 high, 1 medium, 2 low)

- Medium: raw RPC traffic printed to debug logs (pi_rpc_process.dart:222) — prompts/tokens/images
- Low: raw child stderr surfaced in transcript (agent_session.dart:658)
- Low: file-name validation misses Windows path separator (cockpit_viewmodel.dart:532)
3 items written to .work/active/stories/gate-security-*.md.

### gate-tests (2026-07-01) — 5 coverage gaps (2 critical, 0 high, 3 medium) from 103 ACs (98 covered)

- Critical: no test for language LSP probe/save/reset (settings-split AC)
- Critical: no test for notification permission mounted guard/instructions path (settings-split AC)
- Medium: app-preference panels import-only coverage, not persistence/controller
- Medium: daemon tests miss successful create flow
- Medium: control-command serialization test samples only one relay action
5 items written to .work/active/stories/gate-tests-*.md (critical→implementing, medium→drafting).

### gate-docs (2026-07-01) — 5 findings (2 high, 2 medium, 1 low)

- High: rpc-protocol.md stale spawn flags (--no-session/--no-extensions no longer defaults)
- High: cockpit/CLAUDE.md stale single-pane/MVP constraints
- Medium: auto_retry_* listed as ignored but implementation parses them
- Medium: missing CHANGELOG entry for cockpit-v1.6.0 (Phase 5.5 will draft before ship)
- Low: cockpit README is generic Flutter boilerplate
5 items written to .work/active/stories/gate-docs-*.md.

### gate-patterns (2026-07-01) — 6 pattern candidates discovered

6 reusable shapes (3+ occurrences each): pure-workspace-command-transform, centralized-protocol-adapter-boundary, settings-category-registry-dispatch, projection-boundary-for-session-UI, single-reducer-workspace-mutation, settings-data-state-tri-state-render. Pattern-skill authoring deferred (gate-patterns is the final gate; pattern skills are a separate artifact under .agents/skills/patterns/, lower priority for this dogfood). Recorded here for traceability.

### gate-cruft (2026-07-01) — 2 findings (0 high, 1 medium, 1 low)

- Medium: temporary debug trace scaffold (_trace writing ck_trace.log) in production UI flow (workspace_settings_dialog.dart:9) — also found 2 files outside the original bundle list (transitively changed)
- Low: empty catch-swallow in formatter reload path (file_viewer.dart:368)
2 items written to .work/active/stories/gate-cruft-*.md.

## Gate finding routing (per CONVENTIONS gate_finding_routing)

`gate_finding_routing: { critical: implementing, high: implementing, medium: backlog, low: backlog }`.
Critical/high are release-blocking (stay bound, advance to implementing); medium/low are
non-blocking (unbound to .work/backlog/, tracked improvements). Applied to this release's
24 gate findings:

- **Blocking (4)** — stay bound to cockpit-v1.6.0, at stage: implementing:
  - gate-tests-language-lsp-probe-coverage (critical)
  - gate-tests-notification-permission-mounted-guard (critical)
  - gate-docs-rpc-protocol-stale-spawn-flags (high)
  - gate-docs-claudemd-stale-mvp-constraints (high)
- **Non-blocking (20)** — moved to .work/backlog/, release_binding: null:
  - 7 refactor (9 medium → 2 kept blocking? no: all 9 refactor findings were medium → backlog)
  - 3 security (1 medium + 2 low → backlog)
  - 3 tests medium → backlog
  - 3 docs (2 medium + 1 low → backlog)
  - 2 cruft (1 medium + 1 low → backlog)
  - 1 changelog-gap (medium → backlog; Phase 5.5 will draft the changelog before ship regardless)

NOTE: cruft gate-cruft-temp-debug-trace-scaffold is medium (non-blocking by policy) but is a
debug artifact left in production — the convention allows keeping it blocking case-by-case.
Operator deferred this decision; currently routed to backlog per the default. If the operator
wants it fixed before ship, rebind it.

### Binding-consistency warnings

binding_guard=warn  epic_cohesion=phased

**CONFLICTS (3)** — done features unbound while their children are bound to cockpit-v1.6.0.
These are the expected consequence of the attribution rule: the 3 cockpit-tagged stories'
parent features are multi-component (repo-level attribution), so they correctly do NOT bind
here and will ship in v0.6.0. Not true orphans — phased delivery where the child ships first.
- epic-bold-transcript-event-log-hydration-replay (feature, done, unbound) — child step-4 bound here
- epic-bold-generated-protocol-cockpit-control-rpc (feature, done, unbound) — child step-3 bound here
- epic-bold-transcript-event-log-projection-derive (feature, done, unbound) — child step-5 bound here

**INCOMPLETES (16, informational under phased)** — step-stories under the 3 cockpit features
carry only `refactor` (no component tag → repo-level attribution), so they route to v0.6.0,
not cockpit. The cockpit features ship here; their step-stories ship in the repo-level release.
Design note: bold-refactor step-stories don't carry component tags, so they always route to
repo-level even when implementing a component feature. Worth revisiting the tag discipline.

## Shipped items

Bodies live on disk (retain-bodies) and in git history — `git show <git ref>:<former active path>` recovers any.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| epic-bold-cockpit-workspace-projection | Cockpit workspace is a document; the agent session is a projection | epic | — | b1eba69 |
| epic-bold-cockpit-workspace-projection-agent-session | Cockpit workspace — AgentSession as transcript projection | feature | — | b1eba69 |
| epic-bold-cockpit-workspace-projection-settings-split | Cockpit workspace — settings_page split | feature | — | b1eba69 |
| epic-bold-cockpit-workspace-projection-workspace-document | Cockpit workspace — workspace as document (riskiest — design first) | feature | — | b1eba69 |
| epic-bold-generated-protocol-cockpit-control-rpc-step-3 | Step 3: Emit schema-compatible control commands from Cockpit and align custom-event parsing with protocol map | story | — | b1eba69 |
| epic-bold-transcript-event-log-hydration-replay-step-4 | Step 4: Convert Cockpit `get_messages` hydration to event replay projection | story | — | b1eba69 |
| epic-bold-transcript-event-log-projection-derive-step-5 | Step 5: Make Cockpit transcript entries immutable projection outputs | story | — | b1eba69 |
| gate-cruft-temp-debug-trace-scaffold | Temporary debug trace scaffold remains in production UI flow | story | — | b1eba69 |
| gate-docs-claudemd-stale-mvp-constraints | cockpit/CLAUDE.md still describes single-pane/MVP constraints that are no longer true | story | — | b1eba69 |
| gate-docs-rpc-protocol-stale-spawn-flags | rpc-protocol.md documents stale pi --mode rpc spawn flags and relay assumptions | story | — | b1eba69 |
| gate-tests-language-lsp-probe-coverage | No test covers language LSP probe/save/reset behavior | story | — | b1eba69 |
| gate-tests-notification-permission-mounted-guard | No test covers notification permission request mounted guard/instructions path | story | — | b1eba69 |
