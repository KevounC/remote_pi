# Pattern: Subscription Unsubscribe Contracts

## Rationale

Long-lived event streams expose subscription APIs that return an explicit
unsubscribe closure, and callers pass stable callbacks into those APIs. This makes
teardown deterministic and encourages lifecycle-aware code paths.

## When to use

Use this pattern for every event/source subscription that can be dynamically added
at runtime and later removed (peer messages, reconnect handlers, relay outer
message streams).

## When not to use

Avoid for fire-and-forget listeners that never need teardown or for one-shot
callbacks.

## Examples

### Example 1: session peer subscription contract

**File:** `pi-extension/src/session/peer.ts:198`

```ts
onMessage(handler: MessageHandler): () => void {
  this.handlers.add(handler);
  return () => this.handlers.delete(handler);
}

onReconnect(handler: ReconnectHandler): () => void {
  this.reconnectHandlers.add(handler);
  return () => this.reconnectHandlers.delete(handler);
}
```

### Example 2: mesh-node delegation to peer-level unsubscribe

**File:** `pi-extension/src/session/mesh_node.ts:381`

```ts
onMessage(handler: (env: Envelope) => void): () => void {
  return this.peer_.onMessage(handler);
}

onReconnect(handler: () => void): () => void {
  return this.peer_.onReconnect(handler);
}
```

### Example 3: transport subscription with closure cleanup

**File:** `pi-extension/src/extension/relay_transport.ts:258`

```ts
function onOuterMessage(handler: (line: string) => void | Promise<void>): () => void {
  outerMessageHandlers.add(handler);
  relay?.on("message", handler);
  return () => {
    outerMessageHandlers.delete(handler);
    relay?.off("message", handler);
  };
}
```

## Common violations

- Returning `void` from subscription APIs and relying on caller to remember/remove
  listeners manually.
- Storing anonymous callbacks without a corresponding closure to reverse
  registration.

## Index entry

- **subscription-unsubscribe-contract**: Return explicit unsubscribe closures for every dynamic event subscription.
