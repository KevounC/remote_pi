---
id: gate-security-app-inbound-relay-frame-size-caps
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

# Mobile app decodes inbound relay frames before size caps

## Severity
Low

## Domain
Input Validation & Injection / API Security / Error Handling

## Location
`app/lib/data/transport/ws_transport.dart:304`

## Evidence
```dart
final frame = jsonDecode(raw) as Map<String, dynamic>;

// Envelope: {peer, ct} with room-aware routing.
if (frame.containsKey('peer') && frame.containsKey('ct')) {
  final bytes = _b64Decode(frame['ct'] as String);
```

## Issue
The mobile WebSocket demux parses the whole relay frame and base64-decodes `ct` before enforcing any explicit raw-frame or decoded-payload size cap. A malicious/compromised relay or sender that can get a frame delivered to the app can force avoidable allocation and decode work up to the WebSocket stack's implicit limits. Provenance: introduced in this bundle's app transport refactor (`git blame` points at the v0.6.0-bound app relay demux change).

## Remediation direction
Add explicit raw-frame and decoded-payload limits before `jsonDecode` / `_b64Decode`, align the cap with the protocol's relay envelope limit, and surface/drop oversized frames through the existing malformed-frame path without logging payload content.
