---
id: epic-bold-generated-protocol-cockpit-control-rpc-step-2
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-generated-protocol-cockpit-control-rpc
depends_on: [epic-bold-generated-protocol-cockpit-control-rpc-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Parse schema control envelopes in pi-extension input path and route to dispatcher

**Priority**: High  
**Risk**: High  
**Source Lens**: fail-fast boundary / abstraction boundary  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`

## Current State

Control messages arrive only as a magic prefix marker today:

```ts
if (event.text.startsWith(CTRL_PREFIX)) {
  void _handleControl(event.text.slice(CTRL_PREFIX.length).trim());
  return { action: "handled" };
}
```

`_handleControl` parses verbs and fixed strings (`relay:on`, `relay:off`,
`relay:toggle`, `relay:status`) with a `rename:` branch.

## Target State

- Add a control-frame parser that recognizes schema-shaped payloads first.
- Keep `CTRL_PREFIX` as an explicit compatibility decoder that maps into the same
  canonical command path.
- Preserve `action:"handled"` on control frames so RPC-origin relay buttons never
  become transcript turns.
- Route both legacy and structured payloads into one command dispatch path to avoid
  duplicated control behavior.

## Implementation Notes

- Introduce a discriminator-based parse (e.g. JSON command object with explicit
  `type: "remote-pi-control"` and normalized fields).
- Keep validation strict enough to avoid swallowing real user input:
  - malformed JSON → no control handling → normal flow.
  - unknown command type → ignored (backward-compatible forward-safety).
- Keep existing relay-name behavior (`_renameAgent`) and relay-state emission behavior.
- Extend tests in `extension.test.ts` so both formats remain covered:
  - legacy `CTRL_PREFIX` input returns `{ action: "handled" }` and dispatches.
  - structured control payload dispatches same effects.

## Acceptance Criteria

- [ ] Structured control payloads are accepted and dispatched to `_handleControl`.
- [ ] Existing `CTRL_PREFIX` inputs still dispatch and are swallowed from transcript.
- [ ] Unknown/invalid control JSON does not consume normal user input.
- [ ] Relay-state + rename behavior remains unchanged for current clients.
- [ ] No behavioral change for app transport messages outside the control overlay.

## Rollback

Drop parser and compatibility branch additions in `pi-extension/src/index.ts` and
`_handleControl` signature, restoring the current `CTRL_PREFIX`-only handling.
