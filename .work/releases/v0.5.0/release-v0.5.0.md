---
id: release-v0.5.0
kind: release
stage: released
tags: [workflow, research, docs]
parent: null
depends_on: []
release_binding: v0.5.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Release v0.5.0 (repo)

Repo-level release over `v0.4.0`. Captures cross-component work that doesn't
belong to a single component release: the agent-reference-surface + best-practices
skill, the adversarial codebase review and its four review stories, the
api-reference stack docs, and cross-component fixes (queued-message protocol,
late-attach sync, cross-PC transport-error uuid, security-doc drift, mobile
resume-hydration, history-after-new guard). Bound by the multi-component /
docs-research attribution rule.

## Bound items

19 items (all `stage: done`):

- `feature-agent-reference-surface`
- `feature-adversarial-codebase-review`
- `feature-mobile-remote-coding-best-practices-skill`
- `story-api-reference-pi-extension-typescript-stack`
- `story-api-reference-flutter-mobile-stack`
- `story-api-reference-flutter-desktop-cockpit-stack`
- `story-api-reference-rust-relay-stack`
- `story-api-reference-next-site-stack`
- `story-research-platform-agent-reference-patterns`
- `story-adversarial-findings-dedup-routing`
- `story-adversarial-mobile-lifecycle-review`
- `story-adversarial-security-privacy-review`
- `story-adversarial-state-protocol-review`
- `story-fix-cross-pc-transport-error-uuid`
- `story-implement-extension-queued-message-protocol`
- `story-fix-late-attach-turn-stream-sync`
- `story-fix-security-doc-drift`
- `story-guard-stale-session-history-after-new`
- `story-add-mobile-resume-hydration`

## Gate runs

None — `gates_for_release: []`.

## Shipped items

Bodies live on disk (`retain-bodies`). Active done items moved to
`.work/releases/v0.5.0/`; archived items stay in `.work/archive/`.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| feature-agent-reference-surface | Agent reference surface | feature | — | HEAD |
| feature-adversarial-codebase-review | Adversarial codebase review | feature | — | HEAD |
| feature-mobile-remote-coding-best-practices-skill | Mobile remote-coding best-practices skill | feature | — | HEAD |
| story-api-reference-pi-extension-typescript-stack | API reference: pi-extension TypeScript stack | story | — | HEAD |
| story-api-reference-flutter-mobile-stack | API reference: Flutter mobile stack | story | — | HEAD |
| story-api-reference-flutter-desktop-cockpit-stack | API reference: Flutter desktop cockpit stack | story | — | HEAD |
| story-api-reference-rust-relay-stack | API reference: Rust relay stack | story | — | HEAD |
| story-api-reference-next-site-stack | API reference: Next site stack | story | — | HEAD |
| story-research-platform-agent-reference-patterns | Research: platform agent reference patterns | story | — | HEAD |
| story-adversarial-findings-dedup-routing | Adversarial findings dedup routing | story | — | HEAD |
| story-adversarial-mobile-lifecycle-review | Adversarial mobile lifecycle review | story | — | HEAD |
| story-adversarial-security-privacy-review | Adversarial security/privacy review | story | — | HEAD |
| story-adversarial-state-protocol-review | Adversarial state/protocol review | story | — | HEAD |
| story-fix-cross-pc-transport-error-uuid | Cross-PC transport-error uuid | story | — | HEAD |
| story-implement-extension-queued-message-protocol | Extension queued-message protocol | story | — | HEAD |
| story-fix-late-attach-turn-stream-sync | Late-attach turn stream sync | story | — | HEAD |
| story-fix-security-doc-drift | Security doc drift | story | — | HEAD |
| story-guard-stale-session-history-after-new | Guard stale session history after new | story | unbound | 3dba904 |
| story-add-mobile-resume-hydration | Mobile resume hydration | story | unbound | 3dba904 |

## Notes

- Date shipped: 2026-06-29 (substrate catch-up)
- Mapping: `tag-based`
- Total items shipped: 19
- Gate finding totals: n/a
