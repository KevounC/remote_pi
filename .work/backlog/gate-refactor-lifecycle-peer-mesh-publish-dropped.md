---
id: gate-refactor-lifecycle-peer-mesh-publish-dropped
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Peer mutation hook drops async mesh publish failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
app/lib/config/dependencies.dart:98

## Issue
The sync attachPeerMutationHook callback calls async meshSync.publish() with only a lint ignore. The returned Future<MeshPublishResult> and any thrown error are discarded.

## Fix
needs analysis
