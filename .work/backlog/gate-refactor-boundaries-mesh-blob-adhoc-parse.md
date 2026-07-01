---
id: gate-refactor-boundaries-mesh-blob-adhoc-parse
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

# Mesh membership blob parsed through serde_json::Value

## Library
boundaries

## Rule
ad-hoc-wire-parse

## Confidence
Medium

## Location
relay/src/handlers/pi_forward.rs:106

## Issue
MeshAuthCache::members_of deserializes the verified mesh blob into serde_json::Value and navigates members/remote_epk with .get()/.as_array(). Non-generated interior mesh payload parsing.

## Fix
needs analysis: add a typed DTO for the mesh-members blob and deserialize into it (behavior-changing on malformed input).
