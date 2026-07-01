---
id: gate-security-subscription-empty-target-retention
kind: story
stage: drafting
tags: [security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Subscription target map retains empty target entries

## Severity
Medium

## Location
relay/src/subscriptions.rs:54

## Issue
remove_all removes the subscriber from each target set but never deletes now-empty target keys, allowing repeated subscribe/replace calls with new target names to grow memory indefinitely.

## Recommendation
Remove subscribers_of entries when their set becomes empty and consider bounding peer-id length / total subscription churn per connection.
