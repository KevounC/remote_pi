---
id: gate-refactor-protocol-handwritten-control-type-strings
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

# Control handler repeats generated frame type strings

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
Medium

## Location
relay/src/handlers/control.rs:68

## Issue
The generated RelayControlFrame match already identifies the control variant, but the handler repeats discriminator strings for labels/limits (subscribe_presence, presence_check, rooms_check, etc.; also lines 86, 97, 100, 112, 123, 134, 137). These can drift from the generated protocol source.

## Fix
needs analysis: derive the label from the generated enum/registry or centralize a single generated-backed variant-to-wire-type helper.
