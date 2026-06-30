import type { ByeReason, ClientMessage, ServerMessage } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { AttachOwnerInput, OwnerMultiplexerPort } from "./ports.js";

export interface PeerChannelHandle extends PeerChannel {
  detach(): void;
}

export interface OwnerAttachInput extends AttachOwnerInput {
  /** True when the owner attached while a turn/compaction is active. */
  turnActive?: boolean;
}

export type CreateOwnerChannelInput = Omit<OwnerAttachInput, "onMessage" | "onDisconnect" | "turnActive"> & {
  onMessage(message: ClientMessage): void | Promise<void>;
  onDisconnect(peerId: string): void;
};

export interface OwnerMultiplexerDeps {
  createChannel(input: CreateOwnerChannelInput): PeerChannelHandle;
  refreshFooter(): void;
}

/**
 * Owns the app-owner channel registry for one pi-extension runtime.
 *
 * The relay WebSocket remains owned by the relay transport; each
 * PlainPeerChannel remains the low-level relay-backed adapter. This module owns
 * only the per-owner channel lifetime, derived paired state, and fanout.
 */
export class OwnerMultiplexer implements OwnerMultiplexerPort {
  private readonly channels = new Map<string, PeerChannelHandle>();
  private readonly peerIdsByChannel = new Map<PeerChannelHandle, string>();
  private readonly messageRouters = new Map<PeerChannelHandle, OwnerAttachInput["onMessage"]>();
  private peerShort = "";
  private lateAttachPeerIds = new Set<string>();

  constructor(private readonly deps: OwnerMultiplexerDeps) {}

  activeCount(): number {
    return this.channels.size;
  }

  peerHint(): string {
    return this.peerShort;
  }

  has(peerId: string): boolean {
    return this.channels.has(peerId);
  }

  get(peerId: string): PeerChannel | undefined {
    return this.channels.get(peerId);
  }

  peerIds(): readonly string[] {
    return [...this.channels.keys()];
  }

  entries(): readonly { peerId: string; channel: PeerChannel }[] {
    return [...this.channels.entries()].map(([peerId, channel]) => ({ peerId, channel }));
  }

  attach(input: OwnerAttachInput): PeerChannel {
    // Idempotent reattach: tear down the stale per-owner listener before
    // installing a fresh channel for the same owner peer id.
    this.detach(input.peerId);

    let channel: PeerChannelHandle | null = null;
    channel = this.deps.createChannel({
      relay: input.relay,
      peerId: input.peerId,
      roomId: input.roomId,
      onMessage: (message) => this.routeFrom(channel as PeerChannelHandle, message),
      onDisconnect: (peerId) => {
        this.detach(peerId);
        input.onDisconnect?.(peerId);
      },
    });

    this.channels.set(input.peerId, channel);
    this.peerIdsByChannel.set(channel, input.peerId);
    this.messageRouters.set(channel, input.onMessage);
    this.peerShort = input.peerId.slice(0, 8);
    if (input.turnActive) this.lateAttachPeerIds.add(input.peerId);
    this.deps.refreshFooter();
    return channel;
  }

  detach(peerId: string, reason?: ByeReason): void {
    const channel = this.channels.get(peerId);
    if (!channel) return;

    if (reason) {
      try { channel.send({ type: "bye", reason }); } catch { /* best-effort per owner channel */ }
    }

    try { channel.detach(); } catch { /* best-effort per owner channel */ }

    this.channels.delete(peerId);
    this.peerIdsByChannel.delete(channel);
    this.messageRouters.delete(channel);
    this.lateAttachPeerIds.delete(peerId);

    if (this.peerShort === peerId.slice(0, 8)) {
      const next = this.channels.keys().next().value as string | undefined;
      this.peerShort = next ? next.slice(0, 8) : "";
    }
    this.deps.refreshFooter();
  }

  detachAll(reason?: ByeReason): void {
    for (const peerId of [...this.channels.keys()]) {
      this.detach(peerId, reason);
    }
    this.lateAttachPeerIds.clear();
    this.peerShort = "";
    this.deps.refreshFooter();
  }

  broadcast(message: ServerMessage): void {
    for (const channel of this.channels.values()) {
      try { channel.send(message); } catch { /* best-effort per owner channel */ }
    }
  }

  routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void> {
    const channel = sender as PeerChannelHandle;
    const peerId = this.peerIdsByChannel.get(channel);
    if (!peerId || this.channels.get(peerId) !== channel) return;
    const route = this.messageRouters.get(channel);
    return route?.(message, sender);
  }

  lateAttachTargets(): readonly PeerChannel[] {
    const targets = [...this.lateAttachPeerIds]
      .map((peerId) => this.channels.get(peerId))
      .filter((channel): channel is PeerChannelHandle => !!channel);
    this.lateAttachPeerIds.clear();
    return targets;
  }

  lateAttachEntries(): readonly { peerId: string; channel: PeerChannel }[] {
    const targets = [...this.lateAttachPeerIds]
      .map((peerId) => {
        const channel = this.channels.get(peerId);
        return channel ? { peerId, channel } : null;
      })
      .filter((entry): entry is { peerId: string; channel: PeerChannelHandle } => !!entry);
    this.lateAttachPeerIds.clear();
    return targets;
  }
}

export function createOwnerMultiplexerPort(
  deps: OwnerMultiplexerDeps,
): OwnerMultiplexerPort {
  return new OwnerMultiplexer(deps);
}
