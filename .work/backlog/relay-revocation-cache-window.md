---
id: relay-revocation-cache-window
created: 2026-06-28
updated: 2026-06-28
tags: [relay, pi-extension, security]
---

# Reduce or surface mesh revocation convergence window

Adversarial review noted revocation is eventual: pi-extension self-revoke polls around every 60s and relay positive mesh-auth cache TTL is 60s. Consider push invalidation on mesh version advance, lower TTL/poll cadence, or explicit documentation/UX for the revocation window.
