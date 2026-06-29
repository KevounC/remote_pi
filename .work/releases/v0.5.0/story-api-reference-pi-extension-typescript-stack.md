---
id: story-api-reference-pi-extension-typescript-stack
kind: story
stage: done
tags: [pi-extension, research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
release_binding: v0.5.0
gate_origin: null
research_dials:
  scope_authority: mixed
  verification_rigor: standard
  intent: pi-extension-api-reference
  output_kind: skill-reference
created: 2026-06-27
updated: 2026-06-27
---

# API reference for Pi extension TypeScript stack

Create a platform-style stack reference for `pi-extension/`, where most high-risk Remote Pi behavior currently lives.

## Candidate coverage

- Node ESM + TypeScript NodeNext conventions (`.js` imports in `.ts`, strict TS, top-level await boundaries).
- Pi extension SDK surfaces used here: session lifecycle hooks, UI/context lifetimes, tools/commands/resources, `session_shutdown`/`session_start`, and safe handling of replaced sessions.
- WebSocket client behavior via `ws`.
- Local broker / UDS / mesh addressing semantics from `PROTOCOL.md`.
- Crypto/key libraries in use: `@noble/ed25519`, libsodium/secretbox-related code if present, `@napi-rs/keyring` storage behavior.
- Validation/schema libraries: `zod`, `typebox`.
- Test/dev cycle: `corepack pnpm typecheck`, `corepack pnpm test`, `corepack pnpm build`, targeted Vitest patterns.

## Known gotchas to include

- Stale Pi extension context after `/new`, `/resume`, `/reload`, reconnect, or session replacement.
- Never hold old `ctx.ui`/session references without a guard.
- `room_meta.working` must converge to authoritative false after turn end/error/abort/reconnect.
- Mesh peers are agent endpoints, not human mobile/workstation clients.

## Implementation notes

- Drafted `.agents/skills/pi-extension-typescript/SKILL.md` as the first stack reference.
- Sources consulted: `pi-extension/CLAUDE.md`, `pi-extension/package.json`, `pi-extension/src/index.ts`, `pi-extension/src/actions/handlers.ts`, `pi-extension/src/transport/relay_client.ts`, `pi-extension/src/pairing/storage.ts`, `pi-extension/src/protocol/{types,codec}.ts`, `pi-extension/src/session/broker_remote.ts`, `pi-extension/src/daemon/rpc_child.ts`, `pi-extension/src/extension.test.ts` search hits, and installed Pi docs under `/home/agent/.local/lib/node_modules/@earendil-works/pi-coding-agent/docs/` for lifecycle/session APIs.
- ARD-shaped validation pass added `.research/attestation/*` files for the load-bearing sources and citation anchors in the skill reference.
- Adversarial review pass `fe83eb9f-1cdf-487` found one process blocker and two major content issues. Fixes applied: added attestations/citations, corrected the `codec.ts` validation-boundary wording, documented daemon-mode `session_new` exit/restart behavior, added `approve_tool`, and pinned cross-PC anti-spoof checklist language to `BrokerRemote.handleIncoming`.
- Final review pass `c4a1ca92-1809-4bc` approved with no blockers, important findings, or nits. The reviewer verified citation handles resolve, prior findings are fixed, and `AGENTS.md` links the reference.

## Acceptance

- [x] A reference skill/doc exists and is linked from `AGENTS.md` or subproject guidance.
- [x] It includes current API examples verified against installed/current docs, not only training memory.
- [x] It has a dedicated Remote Pi lifecycle/gotchas section grounded in the recent stale-context bug.
