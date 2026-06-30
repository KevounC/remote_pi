import { describe, expect, test, vi } from "vitest";
import { OwnerMultiplexer, type CreateOwnerChannelInput, type OwnerMultiplexerDeps, type PeerChannelHandle } from "./owner_multiplexer.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import type { RelayClient } from "../transport/relay_client.js";

class FakeOwnerChannel implements PeerChannelHandle {
  readonly sent: ServerMessage[] = [];
  detached = false;

  constructor(readonly input: CreateOwnerChannelInput) {}

  send(message: ServerMessage): void {
    this.sent.push(message);
  }

  detach(): void {
    this.detached = true;
  }

  receive(message: ClientMessage): void | Promise<void> {
    return this.input.onMessage(message);
  }
}

function encodeClientMessage(message: ClientMessage): string {
  return Buffer.from(JSON.stringify(message)).toString("base64");
}

function makeMultiplexer() {
  const channels: FakeOwnerChannel[] = [];
  const knownPeers = new Map<string, { name: string; remote_epk: string; paired_at: string }>();
  const refreshFooter = vi.fn();
  const persisted = vi.fn();
  const ownerAttached = vi.fn();
  const ownerPaired = vi.fn();
  const deps: OwnerMultiplexerDeps = {
    createChannel: (input) => {
      const channel = new FakeOwnerChannel(input);
      channels.push(channel);
      return channel;
    },
    refreshFooter,
    listPeers: async () => [...knownPeers.values()],
    findKnownPeer: async (peerId) => knownPeers.get(peerId) ?? null,
    consumePairToken: () => "unknown",
    addPeer: async (record) => { knownPeers.set(record.remote_epk, record); },
    onPeerPersisted: persisted,
    currentPairingSession: () => ({
      sessionName: "test-session",
      sessionStartedAt: 123,
      sessionId: "session-1",
      roomId: "room-1",
    }),
    makeUnknownPeerError: () => ({
      type: "error",
      session_id: "session-1",
      code: "unknown_peer",
      message: "Peer not paired — re-scan QR",
    }),
    onOwnerAttached: ownerAttached,
    onOwnerPaired: ownerPaired,
  };
  return {
    mux: new OwnerMultiplexer(deps),
    channels,
    knownPeers,
    refreshFooter,
    persisted,
    ownerAttached,
    ownerPaired,
  };
}

const fakeRelay = {} as RelayClient;

describe("OwnerMultiplexer", () => {
  test("reattaching the same owner replaces the stale channel", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();

    const first = mux.attach({ relay: fakeRelay, peerId: "owner-1", onMessage });
    const second = mux.attach({ relay: fakeRelay, peerId: "owner-1", onMessage });

    expect(first).not.toBe(second);
    expect(channels[0]!.detached).toBe(true);
    expect(channels[1]!.detached).toBe(false);
    expect(mux.activeCount()).toBe(1);
    expect(mux.has("owner-1")).toBe(true);
    expect(mux.entries()).toEqual([{ peerId: "owner-1", channel: second }]);
  });

  test("broadcast fans out to every active owner channel", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ relay: fakeRelay, peerId: "owner-a", onMessage });
    mux.attach({ relay: fakeRelay, peerId: "owner-b", onMessage });

    const message: ServerMessage = { type: "agent_chunk", session_id: "session-1", in_reply_to: "turn-1", delta: "hello" };
    mux.broadcast(message);

    expect(channels[0]!.sent).toEqual([message]);
    expect(channels[1]!.sent).toEqual([message]);
  });

  test("detaching one owner preserves the other owner channel", () => {
    const { mux, channels } = makeMultiplexer();
    const onMessage = vi.fn();
    mux.attach({ relay: fakeRelay, peerId: "owner-a", onMessage });
    mux.attach({ relay: fakeRelay, peerId: "owner-b", onMessage });

    const result = mux.disconnectOwner("owner-a");

    expect(result).toEqual({ disconnected: true, activeOwnerCount: 1 });
    expect(channels[0]!.detached).toBe(true);
    expect(channels[1]!.detached).toBe(false);
    expect(mux.has("owner-a")).toBe(false);
    expect(mux.has("owner-b")).toBe(true);
  });

  test("known-owner reconnect ingress attaches a channel and routes the triggering message", async () => {
    const { mux, knownPeers, channels, ownerAttached } = makeMultiplexer();
    knownPeers.set("known-owner", { name: "Phone", remote_epk: "known-owner", paired_at: "now" });
    const routed: { message: ClientMessage; sender: FakeOwnerChannel }[] = [];
    const message: ClientMessage = { type: "ping", id: "ping-1" };

    await mux.handleOuterLine({
      line: JSON.stringify({ peer: "known-owner", room: "room-1", ct: encodeClientMessage(message) }),
      relay: fakeRelay,
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage: (routedMessage, sender) => {
        routed.push({ message: routedMessage, sender: sender as FakeOwnerChannel });
      },
      onDisconnect: vi.fn(),
      sendToPeer: vi.fn(),
    });

    expect(mux.activeCount()).toBe(1);
    expect(mux.has("known-owner")).toBe(true);
    expect(ownerAttached).toHaveBeenCalledWith({ peerId: "known-owner", peerName: "Phone", activeCount: 1 });
    expect(routed).toEqual([{ message, sender: channels[0] }]);
  });

  test("malformed ingress is ignored and unknown-owner ingress gets a sender-only error", async () => {
    const { mux } = makeMultiplexer();
    const sendToPeer = vi.fn();
    const onMessage = vi.fn();
    const inputBase = {
      relay: fakeRelay,
      roomId: "room-1",
      turnActive: () => false,
      isCurrent: () => true,
      onMessage,
      onDisconnect: vi.fn(),
      sendToPeer,
    };

    await mux.handleOuterLine({ ...inputBase, line: "not-json" });
    await mux.handleOuterLine({ ...inputBase, line: JSON.stringify({ peer: "stranger", room: "room-1", ct: "not-json-base64" }) });
    expect(sendToPeer).not.toHaveBeenCalled();
    expect(onMessage).not.toHaveBeenCalled();
    expect(mux.activeCount()).toBe(0);

    await mux.handleOuterLine({
      ...inputBase,
      line: JSON.stringify({ peer: "stranger", room: "room-1", ct: encodeClientMessage({ type: "ping", id: "ping-2" }) }),
    });

    expect(sendToPeer).toHaveBeenCalledTimes(1);
    expect(sendToPeer).toHaveBeenCalledWith("stranger", {
      type: "error",
      session_id: "session-1",
      code: "unknown_peer",
      message: "Peer not paired — re-scan QR",
    });
    expect(onMessage).not.toHaveBeenCalled();
    expect(mux.activeCount()).toBe(0);
  });
});
