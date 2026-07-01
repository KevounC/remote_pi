---
id: gate-security-raw-rpc-traffic-logged
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Raw RPC traffic is printed to debug logs

## Location
cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:222

## Issue
The RPC adapter logs raw stdout lines, and the matching stdin log at line 256 can include prompts, tool results, image base64, relay/pairing tokens, and other transcript secrets.

## Recommendation
Remove raw payload logging or guard behind a debug-only redacted logger that strips prompt text, images, tokens, and tool output.
