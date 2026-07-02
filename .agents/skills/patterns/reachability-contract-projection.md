# Pattern: Reachability Contract Projection Across Languages

## Rationale

Protocol state machines that cross transport boundaries should be defined once as contracts (`state` list, backoff schedule, heartbeat policy) and projected into each stack using the same bounded-domain shape. This keeps reachability behavior semantically aligned and lets each component implement checks/clamping in local idioms while preserving compatibility.

## When to use

Use this pattern when each runtime (mobile app, extension process, relay) must execute the same lifecycle policy:
- define the canonical state set in a typed list/enum,
- expose deterministic helper(s) for policy-derived values (timeouts/backoff),
- and keep clamping/indexing logic consistent when attempts exceed configured policy size.

## When not to use

Don’t use this pattern for one-off transport timing knobs, and don’t duplicate raw literals in multiple hot paths without a contract assertion.

## Examples

### Example 1: Extension-level contract constants

**File:** `pi-extension/src/reachability/contract.ts:1`

```ts
export const REACHABILITY_STATES = [
  "connecting",
  "online",
  "degraded",
  "offline",
  "retrying",
] as const;

export const REACHABILITY_BACKOFF_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;

export function reachabilityBackoffMs(attempt: number): number {
  const safeAttempt = Number.isFinite(attempt) ? Math.max(0, Math.trunc(attempt)) : 0;
  return REACHABILITY_BACKOFF_MS[
    Math.min(safeAttempt, REACHABILITY_BACKOFF_MS.length - 1)
  ];
}
```

### Example 2: App-domain contract projection

**File:** `app/lib/domain/value_objects/reachability.dart:21`

```dart
enum ReachabilityState { connecting, online, degraded, offline, retrying }

const reachabilityBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
];

Duration reachabilityBackoffForAttempt(int attempt) {
  final safeAttempt = attempt < 0 ? 0 : attempt;
  final idx = safeAttempt >= reachabilityBackoff.length
      ? reachabilityBackoff.length - 1
      : safeAttempt;
  return reachabilityBackoff[idx];
}
```

### Example 3: Relay contract projection + tests

**File:** `relay/src/reachability.rs:24`

```rs
pub const REACHABILITY_STATES: [ReachabilityState; 5] = [
    ReachabilityState::Connecting,
    ReachabilityState::Online,
    ReachabilityState::Degraded,
    ReachabilityState::Offline,
    ReachabilityState::Retrying,
];

pub const REACHABILITY_BACKOFF: [Duration; 5] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(5),
    Duration::from_secs(10),
    Duration::from_secs(30),
];

pub fn reachability_backoff(attempt: usize) -> Duration {
    REACHABILITY_BACKOFF[attempt.min(REACHABILITY_BACKOFF.len() - 1)]
}
```

```rs
#[test]
fn backoff_matches_contract_and_clamps() {
    let contract = contract();
    let expected = contract["backoffSeconds"]
        .as_array()
        .expect("contract backoff must be an array")
        .iter()
        .map(|value| Duration::from_secs(value.as_u64().expect("backoff must be u64")))
        .collect::<Vec<_>>();

    assert_eq!(REACHABILITY_BACKOFF.as_slice(), expected.as_slice());
    assert_eq!(reachability_backoff(0), Duration::from_secs(1));
    assert_eq!(reachability_backoff(4), Duration::from_secs(30));
    assert_eq!(reachability_backoff(99), Duration::from_secs(30));
}
```

## Common violations

- Divergent state names or ordering across stacks.
- Hardcoded retry/backoff literals copied in each layer without a shared contract source.
- Missing clamp guard, producing index panics or silent truncation.

## Index entry

- **reachability-contract-projection**: Project a shared reachability state machine contract into each stack with clamped policy helpers and shared heartbeat semantics.