---
id: gate-refactor-lifecycle-unguarded-async-workspace-projection
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Async tab disposal is discarded by workspace teardown

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:268,361

## Issue
WorkspaceProjection calls PaneItem.dispose() synchronously even though AgentSession.dispose() is async and owns process/subscription teardown.

## Fix
Needs analysis: add an explicit awaited close/shutdown path for PaneItem resources, or make async teardown intentionally unawaited with error handling.
