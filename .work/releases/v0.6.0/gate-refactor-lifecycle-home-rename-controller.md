---
id: gate-refactor-lifecycle-home-rename-controller
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Home rename dialog leaks its TextEditingController

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`app/lib/ui/home/home_page.dart:438`

## Issue
`_promptRename` creates a local `TextEditingController` for the rename dialog and never disposes it after the dialog closes.

## Fix
Own the controller with a lifecycle boundary: wrap the dialog await in `try/finally { controller.dispose(); }` (after preserving the result), or move the field into a stateful dialog widget that disposes it.
