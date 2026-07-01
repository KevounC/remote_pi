---
id: release-cockpit-v1.6.0
kind: release
stage: quality-gate
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
