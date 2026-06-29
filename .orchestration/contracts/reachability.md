# Reachability contract

This is the interim canonical source for Remote Pi reachability until `epic-bold-generated-protocol` absorbs it into the canonical protocol schema.

Language projections must derive states, display names, backoff values, heartbeat timings, and transition names from `reachability.json`. They must not invent additional states or drift the `[1, 2, 5, 10, 30]` backoff policy.

`degraded` means the transport is still up but the app/Pi room liveness signal is stale. It is not a relay-wide disconnect and does not imply offline queueing.
