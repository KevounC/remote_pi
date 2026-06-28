---
id: story-fix-cross-pc-bridge-late-attach-after-shutdown
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-stale-extension-runtime-audit]
created: 2026-06-28
updated: 2026-06-28
---

# Prevent cross-PC bridge late attach after shutdown

## Brief

The stale-runtime audit found that `MeshNode.attachBridge()` / `attachCrossPcBridge()` can construct a `PiForwardClient`, await sibling discovery, and then install `BrokerRemote` listeners after `MeshNode.close()` or session shutdown if teardown lands during the async discovery window.

## Root risk

A closed/outgoing session instance can attach relay/broker listeners after teardown, creating stale cross-PC routing state or ghost listeners.

## Deep-audit confirmation

The later `story-stale-session-bound-surface-deep-audit` independently reconfirmed this as a remaining gap:

- `pi-extension/src/session/bridge.ts` / `mesh_node.ts` bridge attach paths have async discovery/connect continuations without a post-await closed/epoch check.
- `BrokerRemote.handleIncoming`, `PlainPeerChannel`, and `PiForwardClient` mostly rely on listener removal/upstream detach rather than internal detached guards; bridge attach is the highest-risk entry because it can install new listeners after teardown.

## Expected fix shape

Add a closed/epoch guard to the mesh bridge attach path so every async continuation checks whether the `MeshNode` is still live before installing `BrokerRemote` or retaining relay listeners. Add a delayed-discovery regression test: start `attachBridge()`, close the node before discovery resolves, resolve discovery, assert no bridge remains and no relay envelope listeners remain.
