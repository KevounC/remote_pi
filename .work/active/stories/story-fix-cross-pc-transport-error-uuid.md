---
id: story-fix-cross-pc-transport-error-uuid
kind: story
stage: implementing
tags: [relay, pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Fix cross-PC transport_error envelope IDs

Relay-synthesized cross-PC `transport_error` envelopes currently use a 32-character hex id that does not satisfy the local broker envelope UUID parser, so explicit `offline` / `not_authorized` errors can be dropped locally.

## Scope

- Generate UUID-shaped ids for relay-synthesized transport-error envelopes, or relax the local envelope parser only if that is the chosen protocol rule.
- Preserve `re` correlation with the original envelope id.

## Acceptance Criteria

- [ ] Relay `offline`, `not_authorized`, and `bad_envelope` transport errors parse through `pi-extension/src/session/envelope.ts`.
- [ ] Sender receives the explicit transport error reason instead of a generic timeout.
- [ ] Add relay/extension coverage for at least the offline path.
