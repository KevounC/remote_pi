# Rule: Infra Value Import In Core

> Core logic may take an infra type as a *type-only* import (the port shape) but must not take a concrete infra *value* import — value imports force construction coupling and can pull module side effects.

## Motivation

A `type`-only import (`import type { RelayClient }`) brings in only the type shape; the core
module does not execute or require the infra module's runtime code, and the concrete instance is
supplied at the edge (constructor parameter, module binding). A *value* import
(`import { RelayClient }`) pulls the concrete class into the core module's graph: the core can
`new RelayClient(...)`, depends on the infra module's **top-level side effects** (which now run
when the core module loads, possibly changing initialization order), and can no longer be
exercised with a fake without the real transport present.

This rule fires only in genuine domain/core paths — NOT in lifecycle/adapter/composition code
(see Scope and Exceptions), where value imports of infra are correct wiring.

## Signals

Under a domain/core path (see Scope), an import of an infra module that is **not** `import type`:
- `import { RelayClient } from "../transport/relay_client.js"` — value import (couples construction)
- `import { mkdirSync } from "node:fs"` — value import of a platform API (pulls side effects)

## Behavior-change caveat (why this is untagged)

Converting a value import to `import type` + constructor injection is **not** guaranteed
behavior-preserving:

- The infra module's top-level side effects may run at a **different time** (load-time vs.
  construction-time), changing initialization order or breaking code that depends on those
  side effects having fired.
- Construction moves to the composition root, which changes **ownership and teardown lifecycle**
  of the resource.
- The public constructor/API shape of the consuming class may change (new required parameter).

So this finding is **medium confidence** by default and routes through story/feature design,
where the lifecycle move is designed explicitly. Only mark **high** when the scanner can verify
the infra module has no top-level side effects AND the consuming site already receives the
instance via parameter elsewhere (a pure import-shape cleanup).

## Before / After

### From this codebase: violations (in domain/core paths only)

**Before — a domain/core module taking a value import of transport.**
If a file under `app/lib/domain/**` or `pi-extension/src/reachability/**` (genuine core) had:
```ts
import { RelayClient } from "../transport/relay_client.js";        // value import in core
```
that would be a violation. (Verify the actual file is in-scope before emitting — see Scope.)

**After:**
```ts
import type { RelayClient } from "../transport/relay_client.js";   // type-only — the port
// core receives RelayTransport via constructor/parameter
```

### From this codebase: NOT a violation (composition/lifecycle — out of scope)

**`pi-extension/src/session/mesh_node.ts:6` and `bridge.ts:3-4`** value-import transport
classes, but these files are **lifecycle/adapter/composition code** under `session/`, not domain
logic. They construct and own relay resources at session boundaries — exactly where value
imports belong. They are explicitly **excluded** from this rule's Scope. A scanner must NOT
flag them here; routing them through this library would be a false positive. A domain/ports
split in `session/` is a real design decision and belongs in feature design, not this scan.

## Exceptions

- **Composition roots and lifecycle/adapter code** — `pi-extension/src/index.ts`,
  `pi-extension/src/session/**` (`mesh_node.ts`, `bridge.ts`, `broker.ts`, `cwd_lock.ts`,
  `leader_election.ts`, `local_config.ts`, `global_config.ts`, `setup_wizard.ts`),
  `app/lib/main.dart`, cockpit module bindings — value imports of infra are correct there.
- **Test fixtures** — `*.test.ts`, `*_test.dart`, `relay/tests/**`, `#[cfg(test)]` blocks —
  value imports are correct for constructing fakes/stubs.
- **Generated code** — `protocol/generated/`, `*.g.dart` — not authored; skip.
- **Type-only imports are never violations** — if every flagged import is `import type`, emit
  nothing.
- **`node:fs/promises` for a single-purpose file module** in a genuinely isolated, file-shaped
  artifact may be acceptable. Mark low confidence; needs analysis.

## Scope

Same as `domain-imports-infra` — domain/core paths only:
- `app/lib/domain/**`, `cockpit/lib/**/domain/**`, `pi-extension/src/reachability/**` (non-test),
  `pi-extension/src/mesh/**` (non-test), `relay/src/protocol/**` authored non-generated modules.
- **Excludes** `pi-extension/src/session/**` (lifecycle/adapter/composition), `relay/src/handlers/**`
  (adapter/boundary code), composition roots, tests, generated code, `site/**`.
