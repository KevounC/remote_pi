---
id: story-api-reference-pi-extension-typescript-stack
kind: story
stage: drafting
tags: [pi-extension, research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
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

## Acceptance

- A reference skill/doc exists and is linked from `AGENTS.md` or subproject guidance.
- It includes current API examples verified against installed/current docs, not only training memory.
- It has a dedicated Remote Pi lifecycle/gotchas section grounded in the recent stale-context bug.
