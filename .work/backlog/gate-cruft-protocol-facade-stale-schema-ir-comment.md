---
id: gate-cruft-protocol-facade-stale-schema-ir-comment
kind: story
stage: drafting
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Correct stale protocol facade claim about relay-control schema coverage

## Confidence
Medium

## Category
stale comment

## Location
`app/lib/protocol/protocol.dart:4`

## Evidence
```dart
// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
//
// Relay control/presence/rooms frames are not yet in the schema IR, so they
// remain in the temporary hand-maintained island exported below.
```

`protocol/schema/manifest.json:20` already declares the `relayControl` family, and `protocol/schema/relay-control.schema.json:4` titles it "Remote Pi relay auth, presence, rooms, and control frames".

## Removal
Update the facade comment so it no longer says relay control/presence/rooms are absent from the schema IR. If the current limitation is Dart-emitter coverage, say that precisely (for example: relay-control schema exists, but Dart relay-control DTO generation is deferred) or delete the stale explanation when the hand-maintained island is retired.
