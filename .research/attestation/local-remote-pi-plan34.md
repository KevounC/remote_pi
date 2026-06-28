---
source_handle: local-remote-pi-plan34
fetched: 2026-06-28
source_path: plan/34-mesh-reliable-delivery-passive-presence.md and pi-extension/src/session/tools.ts
provenance: source-direct
---

# Reliable-delivery plan / current tool attestation

1. `plan/34-mesh-reliable-delivery-passive-presence.md` records a decision to remove busy-drop behavior: always write to the destination socket, even when the peer is busy.
2. The same plan marks the busy-drop removal complete and says no `busy` ACK should occur for unicast new-work; the legacy `busy` status may remain as an inert type fallthrough.
3. `pi-extension/src/session/tools.ts` describes current `agent_send` as reliable delivery: a peer mid-turn still receives the message and processes it on a future turn, so callers do not retry-on-busy.
4. This contradicts the older `PROTOCOL.md` ACK text that says `busy` means the message was discarded.
