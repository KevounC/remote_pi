---
id: gate-docs-relay-ct-limit-1mib-stale
created: 2026-07-01
updated: 2026-07-01
tags: [documentation]
---

# Relay message-size decision table still references 1 MiB

## Location
`docs/DECISIONS.md:97`

## Issue
The decision table still states a 1 MiB relay payload limit, but implementation now defaults to 4 MiB and supports `RELAY_MAX_CT_MIB` override.

## Recommendation
Update the table to `4 MiB` default and note override/env semantics per `relay/src/protocol/outer.rs` so docs match the deployed behavior.

## Evidence
- `relay/src/protocol/outer.rs:17-22` defines `MAX_CT_ENV` and `DEFAULT_MAX_CT_MIB = 4`.
- `relay/src/protocol/outer.rs:27-34` documents override/parsing behavior.
- `relay/src/protocol/outer.rs:118-125` tests explicitly assert ~2 MiB payload acceptance under the 4 MiB default.
