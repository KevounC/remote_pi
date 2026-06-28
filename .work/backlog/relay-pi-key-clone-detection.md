---
id: relay-pi-key-clone-detection
created: 2026-06-28
updated: 2026-06-28
tags: [relay, pi-extension, security]
---

# Implement Pi-key clone detection alerting

`PROTOCOL.md` already lists clone detection as not implemented. Adversarial review reconfirmed that two hosts using the same Pi-key can coexist without alert. Consider implementing server-side detection for concurrent same-Pi-key connections from suspiciously different source IPs/topologies and surfacing an owner-visible warning.
