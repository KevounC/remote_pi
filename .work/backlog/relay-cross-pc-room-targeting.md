---
id: relay-cross-pc-room-targeting
created: 2026-06-28
updated: 2026-06-28
tags: [relay, pi-extension, security]
---

# Scope room-targeted cross-PC pi_envelope routing

Adversarial review found cross-PC `pi_envelope` routing is keyed only by destination Pi pubkey (`to_pc`) and the relay fans out to every live room on that PC. This may leak metadata across workspaces and amplifies DoS fanout. Consider a feature that adds destination room scoping (`to_room` or equivalent) and updates broker/relay/app compatibility.
