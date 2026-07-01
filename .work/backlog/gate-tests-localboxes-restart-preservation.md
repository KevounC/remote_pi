---
id: gate-tests-localboxes-restart-preservation
kind: story
stage: drafting
tags: [testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-01
updated: 2026-07-01
---

# LocalBoxes.init restart preservation is only partially covered

## Severity
Medium

## Location
app/lib/data/local/boxes.dart:54

## Issue
AC uncovered (bound item: epic-bold-transcript-event-log-store-step-1): Existing LocalBoxes.init behavior still opens common boxes and wipes only runtime. Existing coverage proves runtime is wiped, but not the "only runtime" preservation half — that sessions_index data remains present across a simulated restart.

## Recommendation
Add a focused test in app/test/data/local/records_test.dart that seeds both sessions_index and runtime, calls LocalBoxes.initForTest(...) again to simulate restart, then asserts runtime is cleared while sessions_index data remains present.
