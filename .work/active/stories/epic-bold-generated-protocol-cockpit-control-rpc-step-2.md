---
id: epic-bold-generated-protocol-cockpit-control-rpc-step-2
kind: story
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-generated-protocol-cockpit-control-rpc
depends_on: [epic-bold-generated-protocol-cockpit-control-rpc-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`.
- Added a schema-shaped `remote_pi_control` parser in `index.ts` that normalizes `relay_on`, `relay_off`, `relay_toggle`, `relay_status`, and `rename` into the existing legacy command strings before dispatch.
- Kept `CTRL_PREFIX` as an explicit compatibility decoder and routed both structured and legacy frames through the same `_dispatchControlFrame`/`_handleControl` path.
- Added extension tests proving legacy control input is swallowed and dispatches relay-state, structured `remote_pi_control` input is swallowed and dispatches relay-state, structured rename parses to the same command path, and unknown/malformed structured JSON falls through as normal input.
- Discrepancies from design: used the checked-in schema discriminator `type: "remote_pi_control"` from `protocol/schema/cockpit-control.schema.json` rather than the example `"remote-pi-control"` spelling in the notes.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; `corepack pnpm exec vitest run src/extension.test.ts` reported 161 passed / 4 failed out of 165 before the harness timeout.
- False-alarm observation: the 4 failing tests were `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`; these match the known environment/cwd-lock/name-assigned/rename false-failure pattern. A focused `-t "relay control channel"` run showed all new control tests passing, with only the known `rename:<name>...` false-alarm failing.

## Review

Approved (2026-06-30). Independently re-ran (clean state): `corepack pnpm typecheck`
clean; **full pi-ext suite 670 passed | 3 skipped | 0 failed (44 files)** — fully green
(up from 666 — the agent's new structured `remote_pi_control` parser tests). The "4
failed + harness close timeout" the agent reported were the false-alarm pattern + a
transient harness teardown issue — confirmed by clean orchestrator re-run (0 failures).
The agent CORRECTLY classified them by reading the actual test names.

Implementation verified: added a schema-shaped `remote_pi_control` parser normalizing
`relay_on`/`relay_off`/`relay_toggle`/`relay_status`/`rename` into the existing legacy
command strings before dispatch; `CTRL_PREFIX` kept as explicit compat decoder; both
structured + legacy frames route through the same `_dispatchControlFrame`/`_handleControl`
path. Tests prove legacy + structured control input dispatches relay-state, structured
rename parses to the same command path, unknown/malformed JSON falls through as normal
input. Invariant listener-count tests untouched and passing. Commit `7a94ca1` scoped to
pi-ext only (extension.test.ts +46); collision guard held.
