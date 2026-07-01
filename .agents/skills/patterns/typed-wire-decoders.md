# Pattern: Typed Wire Decoders

## Rationale

Multiple modules ingest untrusted wire payloads and apply the same structure:
1) safe JSON parse, 2) runtime shape checks, 3) typed decode, 4) dispatch/fanout.

Keeping this as explicit helper functions reduces malformed-input failure surface
and makes decoding behavior testable and reusable.

## When to use

Use when handling protocol text coming from relay, mesh, or CLI transport lines
that must be validated before touching typed domain objects.

## When not to use

Do not over-apply this to strictly internal, typed in-memory objects already
owned by trusted code paths.

## Examples

### Example 1: outer envelope decode helper in owner multiplexer

**File:** `pi-extension/src/extension/owner_multiplexer.ts:105`

```ts
export function decodeOuterEnvelope(line: string): OwnerOuterEnvelope | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line) as unknown;
  } catch {
    return null;
  }
  if (!isRecord(parsed)) return null;
  if (typeof parsed.peer !== "string" || parsed.peer.length === 0) return null;
  if (typeof parsed.ct !== "string" || parsed.ct.length === 0) return null;
  if (parsed.room !== undefined && typeof parsed.room !== "string") return null;
  return {
    peer: parsed.peer,
    ct: parsed.ct,
    ...(typeof parsed.room === "string" ? { room: parsed.room } : {}),
  };
}
```

### Example 2: mirrored decode helper in pairing coordinator

**File:** `pi-extension/src/extension/command_surface/pairing_coordinator.ts:94`

```ts
function decodeOuterEnvelope(line: string): OuterEnvelope | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line) as unknown;
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;
  const record = parsed as Record<string, unknown>;
  if (typeof record.peer !== "string" || record.peer.length === 0) return null;
  if (typeof record.ct !== "string" || record.ct.length === 0) return null;
  if (record.room !== undefined && typeof record.room !== "string") return null;
  return {
    peer: record.peer,
    ct: record.ct,
    ...(typeof record.room === "string" ? { room: record.room } : {}),
  };
}
```

### Example 3: centrally-typed protocol codec decoder for typed envelopes

**File:** `pi-extension/src/protocol/codec.ts:23`

```ts
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
```

## Common violations

- Repeated inline `JSON.parse` + type-casts at call sites without centralized guard
  functions.
- Dispatching decoded objects without verifying `type` and runtime field shapes.

## Index entry

- **typed-wire-decoders**: Parse/validate untrusted wire payloads through typed decode helpers before dispatch.
