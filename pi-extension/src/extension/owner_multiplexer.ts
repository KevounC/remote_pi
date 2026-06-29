import type { ByeReason, ClientMessage, ServerMessage } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { AttachOwnerInput, OwnerMultiplexerPort } from "./ports.js";

export interface PeerChannelHandle extends PeerChannel {
  detach(): void;
}

export type CreateOwnerChannelInput = Omit<AttachOwnerInput, "onMessage" | "onDisconnect"> & {
  onMessage(message: ClientMessage): void | Promise<void>;
  onDisconnect(peerId: string): void;
};

export interface OwnerMultiplexerDeps {
  createChannel(input: CreateOwnerChannelInput): PeerChannelHandle;
  refreshFooter(): void;
  notify(message: string, type?: "info" | "warning" | "error"): void;
}

/**
 * Behavior-preserving shell for owner/app channel ownership.
 *
 * Runtime invariant: one extension instance owns one relay room at a time, so
 * the live channel registry can key by owner peer id. Relay-level fanout to
 * multiple devices for the same owner remains outside this module.
 */
export function createOwnerMultiplexerPort(
  deps: OwnerMultiplexerDeps,
): OwnerMultiplexerPort {
  const channels = new Map<string, PeerChannelHandle>();
  const lateAttachPeerIds = new Set<string>();

  function detach(peerId: string, _reason?: ByeReason): void {
    const channel = channels.get(peerId);
    if (!channel) return;
    try {
      channel.detach();
    } catch {
      /* best-effort per owner channel */
    }
    channels.delete(peerId);
    lateAttachPeerIds.delete(peerId);
    deps.refreshFooter();
  }

  function routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void> {
    const entry = [...channels.entries()].find(([, channel]) => channel === sender);
    if (!entry) return;
    // Step 1 shell: the legacy caller supplies the real per-channel router via
    // AttachOwnerInput.onMessage. Later steps move that router body here.
    return undefined;
  }

  return {
    activeCount(): number {
      return channels.size;
    },

    attach(input: AttachOwnerInput): PeerChannel {
      detach(input.peerId);
      let channel: PeerChannelHandle | null = null;
      channel = deps.createChannel({
        ...input,
        onMessage: (message) => input.onMessage(message, channel as PeerChannel),
        onDisconnect: (peerId) => {
          detach(peerId);
          input.onDisconnect?.(peerId);
        },
      });
      channels.set(input.peerId, channel);
      deps.refreshFooter();
      deps.notify(
        `[remote-pi] Owner attached: peer=${input.peerId.slice(0, 8)} (${channels.size} active)`,
        "info",
      );
      return channel;
    },

    detach,

    broadcast(message: ServerMessage): void {
      for (const channel of channels.values()) {
        try {
          channel.send(message);
        } catch {
          /* best-effort per owner channel */
        }
      }
    },

    routeFrom,

    lateAttachTargets(): readonly PeerChannel[] {
      const targets = [...lateAttachPeerIds]
        .map((peerId) => channels.get(peerId))
        .filter((channel): channel is PeerChannelHandle => !!channel);
      lateAttachPeerIds.clear();
      return targets;
    },
  };
}
