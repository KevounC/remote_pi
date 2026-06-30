import type { ByeReason, ClientMessage, PairErrorCode, ServerMessage } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { RelayClient } from "../transport/relay_client.js";
import type { AttachOwnerInput, OwnerMultiplexerPort } from "./ports.js";

export interface PeerChannelHandle extends PeerChannel {
  detach(): void;
}

export interface OwnerAttachInput extends AttachOwnerInput {
  /** Human/device name from peers.json or the pair_request. */
  peerName?: string;
  /** True when the owner attached while a turn/compaction is active. */
  turnActive?: boolean;
}

export type CreateOwnerChannelInput = Omit<OwnerAttachInput, "onMessage" | "onDisconnect" | "turnActive"> & {
  onMessage(message: ClientMessage): void | Promise<void>;
  onDisconnect(peerId: string): void;
};

export interface OwnerPeerRecord {
  name: string;
  remote_epk: string;
  paired_at: string;
}

type PairTokenStatus = "ok" | "expired" | "consumed" | "unknown";

type PairOkMessage = Extract<ServerMessage, { type: "pair_ok" }>;

type UnknownPeerErrorMessage = Extract<ServerMessage, { type: "error" }>;

export interface PairingSessionSnapshot {
  sessionName: PairOkMessage["session_name"];
  sessionStartedAt: PairOkMessage["session_started_at"];
  sessionId: PairOkMessage["session_id"];
  roomId: PairOkMessage["room_id"];
  harness?: PairOkMessage["harness"];
  hostname?: PairOkMessage["hostname"];
}

export interface OwnerAttachedEvent {
  peerId: string;
  peerName: string;
  activeCount: number;
}

export interface OwnerPairedEvent {
  peerId: string;
  peerName: string;
  pairedAt: string;
}

export interface OwnerMultiplexerDeps {
  createChannel(input: CreateOwnerChannelInput): PeerChannelHandle;
  refreshFooter(): void;
  findKnownPeer(peerId: string): Promise<OwnerPeerRecord | null>;
  consumePairToken(token: string): PairTokenStatus;
  addPeer(record: OwnerPeerRecord): Promise<void>;
  onPeerPersisted(): void;
  currentPairingSession(): PairingSessionSnapshot;
  makeUnknownPeerError(): UnknownPeerErrorMessage;
  onOwnerAttached(event: OwnerAttachedEvent): void;
  onOwnerPaired(event: OwnerPairedEvent): void;
}

interface OwnerOuterEnvelope {
  peer: string;
  room?: string;
  ct: string;
}

export interface OwnerOuterLineInput {
  line: string;
  relay: RelayClient;
  roomId?: string;
  turnActive(): boolean;
  isCurrent(): boolean;
  onMessage(message: ClientMessage, sender: PeerChannel): void | Promise<void>;
  onDisconnect(peerId: string): void;
  sendToPeer(peerId: string, message: ServerMessage): void;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

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

export function decodeClientMessage(ct: string): ClientMessage | null {
  let parsed: unknown;
  try {
    const plaintext = Buffer.from(ct, "base64").toString("utf8");
    parsed = JSON.parse(plaintext) as unknown;
  } catch {
    return null;
  }

  // Preserve the legacy live boundary: unknown future client variants are
  // tolerated as long as they are object messages carrying a string `type`, and
  // downstream routing decides whether to handle or ignore them. The important
  // change is that raw JSON stays `unknown` until this boundary narrows it.
  if (!isRecord(parsed) || typeof parsed.type !== "string") return null;
  return parsed as ClientMessage;
}

function isPairRequestMessage(message: ClientMessage): message is Extract<ClientMessage, { type: "pair_request" }> {
  if (message.type !== "pair_request") return false;
  const record = message as Record<string, unknown>;
  return (
    typeof record.id === "string" &&
    typeof record.token === "string" &&
    typeof record.device_name === "string"
  );
}

function pairErrorForStatus(status: Exclude<PairTokenStatus, "ok">): { code: PairErrorCode; message: string } {
  const code: PairErrorCode =
    status === "expired" ? "token_expired"
    : status === "consumed" ? "token_consumed"
    : "token_unknown";
  const message =
    code === "token_expired" ? "Ephemeral token expired. Generate a new QR with /remote-pi pair."
    : code === "token_consumed" ? "Token already consumed by another pair_request."
    : "Token was not issued by this Pi.";
  return { code, message };
}

/**
 * Owns the app-owner channel registry for one pi-extension runtime.
 *
 * The relay WebSocket remains owned by the relay transport; each
 * PlainPeerChannel remains the low-level relay-backed adapter. This module owns
 * only the per-owner channel lifetime, derived paired state, fanout, and the
 * owner ingress decisions that select pairing, reconnect attach, or unknown-peer
 * responses for relay outer envelopes.
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

  async handleOuterLine(input: OwnerOuterLineInput): Promise<void> {
    const outer = decodeOuterEnvelope(input.line);
    if (!outer) return;
    if (!input.isCurrent()) return;
    if (outer.room && input.roomId && outer.room !== input.roomId) return;
    if (this.channels.has(outer.peer)) return;

    const inner = decodeClientMessage(outer.ct);
    if (!inner) return;

    if (inner.type === "pair_request") {
      if (!isPairRequestMessage(inner)) return;
      await this.handlePairRequest(input, outer.peer, inner);
      return;
    }

    const known = await this.deps.findKnownPeer(outer.peer);
    if (!input.isCurrent()) return;
    if (known) {
      const channel = this.attach({
        relay: input.relay,
        peerId: outer.peer,
        peerName: known.name,
        roomId: input.roomId,
        turnActive: input.turnActive(),
        onMessage: input.onMessage,
        onDisconnect: input.onDisconnect,
      });
      this.deps.onOwnerAttached({ peerId: outer.peer, peerName: known.name, activeCount: this.activeCount() });
      this.routeFrom(channel, inner);
      return;
    }

    input.sendToPeer(outer.peer, this.deps.makeUnknownPeerError());
  }

  async handlePairRequest(
    input: OwnerOuterLineInput,
    peerId: string,
    inner: Extract<ClientMessage, { type: "pair_request" }>,
  ): Promise<void> {
    const sendError = (code: PairErrorCode, message: string) => {
      input.sendToPeer(peerId, { type: "pair_error", in_reply_to: inner.id, code, message });
    };

    const status = this.deps.consumePairToken(inner.token);
    if (status !== "ok") {
      const error = pairErrorForStatus(status);
      sendError(error.code, error.message);
      return;
    }

    const pairedAt = new Date().toISOString();
    try {
      await this.deps.addPeer({
        name: inner.device_name,
        remote_epk: peerId,
        paired_at: pairedAt,
      });
      this.deps.onPeerPersisted();
    } catch (err) {
      if (input.isCurrent()) {
        sendError("internal_error", `Failed to persist peer: ${String(err)}`);
      }
      return;
    }
    if (!input.isCurrent()) return;

    this.attach({
      relay: input.relay,
      peerId,
      peerName: inner.device_name,
      roomId: input.roomId,
      turnActive: input.turnActive(),
      onMessage: input.onMessage,
      onDisconnect: input.onDisconnect,
    });
    this.deps.onOwnerAttached({ peerId, peerName: inner.device_name, activeCount: this.activeCount() });

    const session = this.deps.currentPairingSession();
    input.sendToPeer(peerId, {
      type: "pair_ok",
      in_reply_to: inner.id,
      session_name: session.sessionName,
      session_started_at: session.sessionStartedAt,
      session_id: session.sessionId,
      room_id: session.roomId,
      ...(session.harness ? { harness: session.harness } : {}),
      ...(session.hostname ? { hostname: session.hostname } : {}),
    });

    this.deps.onOwnerPaired({ peerId, peerName: inner.device_name, pairedAt });
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
