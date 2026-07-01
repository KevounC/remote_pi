---
id: gate-tests-control-command-serialization
kind: story
stage: drafting
tags: [testing]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: testing
created: 2026-07-01
updated: 2026-07-01
---

# Control-command serialization test only samples one relay action

## Location
cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:405

## Issue
AC uncovered: Control commands from Cockpit are emitted as schema command envelopes. (bound item: epic-bold-generated-protocol-cockpit-control-rpc-step-3)

## Recommendation
Parameterize pi_rpc_process_control_test.dart across relay_on, relay_off, relay_toggle, relay_status, and add an empty-rename failure assertion.
