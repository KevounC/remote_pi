---
id: epic-bold-generated-protocol-ts-codegen-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# TS codegen step 4 — swap protocol facades and validator-backed codecs

## Brief
Replace the handwritten TypeScript protocol source with generated facades and update codec/boundary parsing to use schema-derived validators while preserving stable imports and current JSONL behavior.

## Current State

```ts
// pi-extension/src/protocol/codec.ts
export function decodeServer(line: string): ServerMessage {
  const obj = JSON.parse(line.trim());
  const t = (obj as Record<string, unknown>).type as string;
  if (!SERVER_TYPES.has(t as ServerMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${t}`);
  }
  return obj as ServerMessage;
}
```

```ts
// pi-extension/src/transport/peer_channel.ts
this.onMessage(msg as ClientMessage);
```

## Target State

```ts
// pi-extension/src/protocol/types.ts
export type {
  ActionName,
  ByeReason,
  ClientMessage,
  ErrorCode,
  KnownErrorCode,
  PairErrorCode,
  ServerMessage,
  SessionHistoryEvent,
  StreamingBehavior,
  ThinkingLevel,
  Usage,
  WireImage,
  WireModel,
} from "./generated/protocol.generated.js";
```

```ts
// pi-extension/src/protocol/codec.ts
import {
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
  isClientMessage,
  isServerMessage,
} from "./generated/protocol.generated.js";

export function decodeServer(line: string): ServerMessage {
  const obj = parseJsonLine(line);
  const type = readType(obj);
  if (!SERVER_MESSAGE_TYPES.includes(type as ServerMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${type}`);
  }
  if (!isServerMessage(obj)) {
    throw new DecodeError("invalid_message", `invalid server message: ${type}`);
  }
  return obj;
}

export function decodeClient(line: string): ClientMessage {
  const obj = parseJsonLine(line);
  const type = readType(obj);
  if (!CLIENT_MESSAGE_TYPES.includes(type as ClientMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${type}`);
  }
  if (!isClientMessage(obj)) {
    throw new DecodeError("invalid_message", `invalid client message: ${type}`);
  }
  return obj;
}
```

## Implementation Notes

- Keep `types.ts` as the stable import facade so existing call sites avoid broad churn.
- Keep `encodeClient` and `decodeServer` APIs; add `decodeClient` for inbound app messages.
- Use `decodeClient` in `PlainPeerChannel._onLine` and `_installAutoListener` instead of parse-and-cast. Invalid/malformed app messages remain dropped at the boundary; valid current messages continue to route.
- Update `codec.test.ts` so server/client fixture expectations derive from generated registries, not a second handwritten file allowlist.
- Preserve JSONL newline behavior in `encodeClient`.
- Do not require canonical-session fields in compatibility-profile decoding.

## Acceptance Criteria

- [ ] `types.ts` no longer hand-authors protocol unions; it re-exports generated types.
- [ ] `codec.ts` no longer contains a handwritten `SERVER_TYPES` registry.
- [ ] `decodeServer` accepts schema-valid `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list` payloads.
- [ ] App-origin relay messages pass through generated `decodeClient` before routing.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test` pass from `pi-extension/`.

## Risk
High — this is the atomic runtime swap for imports and transport boundary parsing. Keep the facade stable and preserve permissive compatibility semantics to reduce call-site and app-impact risk.

## Rollback
Revert the facade/codec/boundary-adoption commit to restore handwritten `types.ts`, `codec.ts`, and parse-and-cast routing.
