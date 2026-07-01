---
id: gate-docs-relay-claudemd-logging-guidance
kind: story
stage: drafting
tags: [documentation]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# relay/CLAUDE.md logging guidance references info_span! for handlers

## Severity
Low

## Location
relay/CLAUDE.md:30

## Issue
The doc still instructs using tracing::info_span! in handlers, but current relay handlers use info!/warn!/error! directly (with fields) without info_span! usage.

## Recommendation
Update the CLAUDE guidance to reflect actual relay logging practice (or clarify optional span usage) so handler logging conventions are current.
