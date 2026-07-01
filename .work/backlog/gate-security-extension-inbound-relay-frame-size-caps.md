---
id: gate-security-extension-inbound-relay-frame-size-caps
kind: story
stage: drafting
tags: [security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Pi extension decodes inbound relay frames before size caps

## Severity
Low

## Domain
Input Validation & Injection / API Security / Error Handling

## Location
`pi-extension/src/extension/owner_multiplexer.ts:108`

## Evidence
```ts
parsed = JSON.parse(line) as unknown;
...
return decodeClient(Buffer.from(ct, "base64").toString("utf8"));
```

## Issue
Inbound relay envelopes are parsed as full JSON strings and their `ct` payloads are base64-decoded into UTF-8 before the extension applies any explicit raw-frame or decoded-payload size cap. The same shape also appears in `pi-extension/src/transport/peer_channel.ts:101` and `pi-extension/src/extension/command_surface/pairing_coordinator.ts:97`. A compromised relay or paired peer can force avoidable allocation/parse work in the local extension process up to the WebSocket library's default frame limit.

## Remediation direction
Configure an explicit `ws` max payload for the extension client, reject raw relay lines above the protocol cap before `JSON.parse`, reject `ct` values above the encoded/decoded limit before `Buffer.from`, and align the limits with generated protocol `too_large` handling.
