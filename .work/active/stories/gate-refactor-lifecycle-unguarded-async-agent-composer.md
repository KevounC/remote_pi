---
id: gate-refactor-lifecycle-unguarded-async-agent-composer
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

# Agent composer drops session operation futures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/ui/widgets/agent_composer.dart:322,325,496,560,887,918,1233

## Issue
Several async session/drop/control operations are invoked without await, return, or unawaited, so failures and lifecycle ordering are implicit.

## Fix
Needs analysis: await where ordering matters; otherwise wrap in unawaited(...) and ensure the callee catches/reports errors.
