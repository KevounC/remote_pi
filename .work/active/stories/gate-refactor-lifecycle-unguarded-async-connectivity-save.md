---
id: gate-refactor-lifecycle-unguarded-async-connectivity-save
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

# Relay save action discards its async save future

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart:284,296

## Issue
_save() is async but submit/save UI callbacks invoke it without explicit future handling.

## Fix
Needs analysis: wrap with unawaited(_save()) plus internal error handling, or route through an awaited command helper.
