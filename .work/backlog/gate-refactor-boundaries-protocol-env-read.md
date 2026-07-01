---
id: gate-refactor-boundaries-protocol-env-read
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

# relay/src/protocol/outer.rs:34

## Library
domains-imports-infra

## Rule
Medium

## Confidence
Protocol parser reads process environment directly

## Location
relay/src/protocol/outer.rs is an authored protocol module, but max_ct_bytes() reads std::env::var(MAX_CT_ENV) directly, coupling protocol parsing to process configuration instead of receiving a parsed limit from the relay composition/config boundary.

## Issue
needs analysis: move env parsing to the relay configuration/composition boundary and inject/pass the max ct byte limit into the parser.

## Fix

