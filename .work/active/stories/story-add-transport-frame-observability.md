---
id: story-add-transport-frame-observability
kind: story
stage: drafting
tags: [app, relay, pi-extension]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Design transport-frame observability for malformed or unknown app frames

App transport currently drops unknown/malformed relay and peer-channel frames with debug-only or silent logging. The fix needs a small design choice: what should be release-visible without leaking payloads or annoying users?

## Scope

- Define a privacy-safe, throttled diagnostic surface for dropped malformed/unknown frames.
- Decide whether repeated drops should update connection status, emit an `ErrorMessage`, or only increment counters/logs.
- Gate noisy debug metadata behind debug mode.

## Acceptance Criteria

- [ ] Design chooses release-safe observability semantics and privacy constraints.
- [ ] Tests cover malformed frame does not crash and is accounted for.
- [ ] Production logs do not include payloads, keys, or image/message bodies.
