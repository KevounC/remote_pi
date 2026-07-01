---
id: gate-security-windows-path-separator-validation
kind: story
stage: drafting
tags: [security]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# File name validation misses Windows path separators

## Location
cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart:532

## Issue
File/folder create and rename validation rejects / but not \, so Windows names such as ..\target can escape the intended directory when joined into a path.

## Recommendation
Reject both / and \, reject drive/UNC/control characters, and normalize the final path before verifying it remains inside the intended parent directory.
