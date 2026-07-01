import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { SettingsManager } from "@earendil-works/pi-coding-agent";
import type { Ed25519Keypair } from "../../pairing/crypto.js";
import { buildQRUri, clampPairTtlMs, qrSession, renderQRAscii, TOKEN_TTL_MS } from "../../pairing/qr.js";
import {
  addPeer,
  getOrCreateEd25519Keypair,
  KeyringUnavailableError,
  listOwnerPubkeys,
  listPeers,
  removePeer,
  type PeerRecord,
} from "../../pairing/storage.js";
import { MeshClient } from "../../mesh/client.js";
import { SelfRevoke, type SiblingInfo } from "../../mesh/self_revoke.js";
import { decodeClient } from "../../protocol/codec.js";
import type { ClientMessage, PairErrorCode, ServerMessage, ThinkingLevel } from "../../protocol/types.js";
import { roomIdFor } from "../../rooms.js";
import { localConfigExists } from "../../session/local_config.js";
import { ensureModelRegistry } from "../../actions/registry.js";
import { RelayClient, RoomAlreadyOpenError, type RoomMeta } from "../../transport/relay_client.js";
import type { PeerChannel } from "../../transport/peer_channel.js";
import { resolveRelayUrl, toWebSocketUrl } from "../../config.js";
import type { OwnerMultiplexerPort } from "../ports.js";
import type { PairingSessionSnapshot } from "../owner_multiplexer.js";

export type PairingCoordinatorState = "idle" | "started";

type PairRequest = Extract<ClientMessage, { type: "pair_request" }>;
type PairTokenStatus = "ok" | "expired" | "consumed" | "unknown";

type RemotePiUi = {
  notify?: (message: string, type?: "info" | "warning" | "error") => void;
};

type RemotePiUiContext = { ui?: RemotePiUi } | null | undefined;

interface OuterEnvelope {
  peer: string;
  room?: string;
  ct: string;
}

export interface PairingCoordinatorDeps {
  getState(): PairingCoordinatorState;
  setState(state: PairingCoordinatorState): void;
  relay(): RelayClient | null;
  setRelay(relay: RelayClient | null): void;
  relayUrl(): string | null;
  setRelayUrl(url: string | null): void;
  roomId(): string | null;
  setRoomId(roomId: string | null): void;
  roomMeta(): RoomMeta | null;
  setRoomMeta(meta: RoomMeta | null): void;
  sessionStartedAt(): number | null;
  setSessionStartedAt(ts: number | null): void;
  currentModel(): string | undefined;
  setCurrentModel(model: string | undefined): void;
  currentThinking(): ThinkingLevel | undefined;
  setCurrentThinking(thinking: ThinkingLevel | undefined): void;
  currentThinkingLevel(): ThinkingLevel | undefined;
  displayName(cwd: string): string;
  currentRemoteSessionId(ctx?: unknown): string;
  withCurrentSession<T extends object>(msg: T): T & { session_id: string };
  currentPairingSession(): PairingSessionSnapshot;
  isDisposed(): boolean;
  turnWorking(): boolean;
  owners: OwnerMultiplexerPort;
  ownerHas(peerId: string): boolean;
  ownerActiveCount(): number;
  refreshPairingsCache(): void;
  onOwnerAttached(event: { peerId: string; peerName: string; activeCount: number }): void;
  onOwnerPaired(event: { peerId: string; peerName: string; pairedAt: string }): void;
  onPeerDisconnect(peerId: string): void;
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  joinLocalMesh(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void>;
  refreshFooter(ctx?: RemotePiUiContext): void;
  notify(message: string, type?: "info" | "warning" | "error", ctx?: RemotePiUiContext): void;
  sendPiMessage(
    message: Parameters<ExtensionAPI["sendMessage"]>[0],
    options?: Parameters<ExtensionAPI["sendMessage"]>[1],
    label?: string,
  ): boolean;
  onRelayClose(): void;
  attachBridgeIfReady(): void;
  emitRelayState(force?: boolean): void;
  setSiblings(siblings: SiblingInfo[]): void;
}

function cwdFrom(ctx: Pick<ExtensionContext, "cwd">): string {
  return "cwd" in ctx && typeof ctx.cwd === "string" ? ctx.cwd : process.cwd();
}

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

function decodeClientMessage(ct: string): ClientMessage | null {
  try {
    return decodeClient(Buffer.from(ct, "base64").toString("utf8"));
  } catch {
    return null;
  }
}

function isPairRequest(message: ClientMessage): message is PairRequest {
  if (message.type !== "pair_request") return false;
  const record = message as unknown as Record<string, unknown>;
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

function sendToPeer(relay: RelayClient, peerId: string, msg: ServerMessage): void {
  const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
  relay.send(JSON.stringify({ peer: peerId, ct }));
}

/**
 * Owns relay-facing pairing commands plus their long-lived resources.
 *
 * The extension root remains the composition boundary for relay/session/owner
 * ports, but the cached Pi identity, auto-listener, and self-revoke poller have
 * one lifecycle owner here.
 */
export class PairingCoordinator {
  private cachedEd25519: Ed25519Keypair | null = null;
  private stopAutoListener: (() => void) | null = null;
  private selfRevoke: SelfRevoke | null = null;

  constructor(private readonly deps: PairingCoordinatorDeps) {}

  currentKeypair(): Ed25519Keypair | null {
    return this.cachedEd25519;
  }

  stopListener(): void {
    this.stopAutoListener?.();
    this.stopAutoListener = null;
  }

  stopSelfRevoke(): void {
    this.selfRevoke?.stop();
    this.selfRevoke = null;
  }

  stopOwnedResources(): void {
    this.stopListener();
    this.stopSelfRevoke();
  }

  listenOn(relay: RelayClient): void {
    this.stopListener();
    this.stopAutoListener = this.installAutoListener(relay);
  }

  async startRelay(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    if (this.deps.getState() !== "idle") {
      ctx.ui.notify("[remote-pi] Already started.", "warning");
      return;
    }

    let edKp: Ed25519Keypair;
    try {
      edKp = await getOrCreateEd25519Keypair();
    } catch (err) {
      if (err instanceof KeyringUnavailableError) {
        ctx.ui.notify(
          "[remote-pi] Could not read this machine's identity: the system " +
          "keychain is locked or access was denied. Unlock it (open the app / " +
          "log in) and run /remote-pi again. Your pairing is NOT lost. " +
          "(Set REMOTE_PI_ALLOW_FILE_IDENTITY=1 only for headless hosts.)",
          "error",
        );
        return;
      }
      throw err;
    }
    this.cachedEd25519 = edKp;

    const { url: relayUrl, source } = resolveRelayUrl();
    const myShort = Buffer.from(edKp.publicKey).toString("base64").slice(0, 8);
    const cwd = cwdFrom(ctx);
    const sessionName = this.deps.displayName(cwd);
    const roomId = roomIdFor(cwd, sessionName);

    if (!this.deps.currentModel()) {
      try {
        const c = ctx as Partial<ExtensionContext> & {
          model?: { name?: string; id?: string };
          getModel?: () => { name?: string; id?: string } | undefined;
        };
        const live = c.getModel?.() ?? c.model;
        if (live) {
          this.deps.setCurrentModel(live.name ?? live.id ?? undefined);
        } else {
          const sm = SettingsManager.create(cwd);
          const provider = sm.getDefaultProvider();
          const modelId = sm.getDefaultModel();
          if (modelId) {
            const found = provider ? ensureModelRegistry().find(provider, modelId) : undefined;
            this.deps.setCurrentModel(found?.name ?? modelId);
          }
        }
      } catch { /* defensive — never block start on a model lookup */ }
    }

    try {
      this.deps.setCurrentThinking(this.deps.currentThinkingLevel());
    } catch { /* defensive — never block /remote-pi start on this */ }

    const sessionId = this.deps.currentRemoteSessionId(ctx);
    const roomMeta: RoomMeta = { name: sessionName, cwd, session_id: sessionId };
    const modelName = this.deps.currentModel();
    if (modelName) roomMeta.model = modelName;
    const thinking = this.deps.currentThinking();
    if (thinking) roomMeta.thinking = thinking;
    this.deps.setRoomMeta(roomMeta);

    ctx.ui.notify(`[remote-pi] Connecting to relay ${relayUrl} (source: ${source}, room: ${roomId})…`, "info");

    const relay = new RelayClient(toWebSocketUrl(relayUrl), edKp);
    try {
      await relay.connect({ roomId, roomMeta });
    } catch (err) {
      if (err instanceof RoomAlreadyOpenError) {
        ctx.ui.notify(
          "[remote-pi] Already running in this cwd. Stop the other terminal first.",
          "error",
        );
        return;
      }
      this.deps.notify(`[remote-pi] relay connect failed: ${String(err)}`, "error", ctx);
      return;
    }

    if (this.deps.isDisposed()) {
      try { relay.close(); } catch { /* best-effort */ }
      return;
    }

    this.deps.setRelay(relay);
    this.deps.setRelayUrl(relayUrl);
    this.deps.setRoomId(roomId);
    this.deps.setState("started");
    if (this.deps.sessionStartedAt() === null) this.deps.setSessionStartedAt(Date.now());

    relay.on("close", this.deps.onRelayClose);
    this.listenOn(relay);
    this.deps.refreshFooter(ctx);

    this.ensureSelfRevoke(relayUrl, edKp);
    this.deps.attachBridgeIfReady();
    this.deps.emitRelayState();
    ctx.ui.notify(`[remote-pi] state: started (peer=${myShort}) — Connected to relay ${relayUrl}`, "info");
  }

  async showPairQr(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> {
    const cwd = cwdFrom(ctx);

    if (this.deps.getState() === "idle") {
      if (!localConfigExists(cwd)) {
        ctx.ui.notify(
          "[remote-pi] First-time setup needed. Run /remote-pi to configure, then /remote-pi pair.",
          "warning",
        );
        return;
      }
      ctx.ui.notify("[remote-pi] Starting mesh + relay before pairing…", "info");
      await this.deps.joinLocalMesh(ctx);
      if (this.deps.getState() === "idle") await this.startRelay(ctx);
    }

    const relay = this.deps.relay();
    if (this.deps.getState() === "idle" || !relay) {
      ctx.ui.notify(
        "[remote-pi] Pair requires the relay to be connected. " +
        "Run /remote-pi to start it (or fix your relay URL via /remote-pi set-relay).",
        "warning",
      );
      return;
    }

    const edKp = this.cachedEd25519;
    if (!edKp) {
      ctx.ui.notify("[remote-pi] Identity is not loaded yet. Run /remote-pi to reconnect, then pair.", "warning");
      return;
    }
    const sessionName = this.deps.displayName(cwd);
    const ttlMatch = /--ttl\s+(\d+)/.exec(args);
    const ttlMs = ttlMatch ? clampPairTtlMs(Number(ttlMatch[1]) * 1000) : TOKEN_TTL_MS;
    const { token, expiresAt } = qrSession.issueToken(ttlMs);
    const roomId = this.deps.roomId() ?? roomIdFor(cwd, sessionName);
    const qrUri = buildQRUri(token, edKp.publicKey, sessionName, roomId);
    const qrAscii = renderQRAscii(qrUri);
    this.deps.sendPiMessage({
      customType: "remote-pi:pair-code",
      content:
        `📱 Scan to pair:\n\n${qrAscii}\n` +
        `📋 Or copy this pairing code (camera-less devices):\n\n${qrUri}`,
      details: { uri: qrUri, token, expiresAt, roomId, name: sessionName },
      display: true,
    }, undefined, "pair-code");

    ctx.ui.notify(
      `[remote-pi] QR ready — valid until ${new Date(expiresAt).toLocaleTimeString()}. ` +
      `Scan with the app, or copy the pairing code printed above.`,
      "info",
    );
  }

  async listDevices(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const peers = await listPeers();
    if (peers.length === 0) {
      ctx.ui.notify("[remote-pi] No paired devices.", "info");
      return;
    }
    const lines = peers.map((p) => {
      const shortid = p.remote_epk.slice(0, 8);
      const tag = this.deps.ownerHas(p.remote_epk) ? " 🟢 online" : " ⚪ offline";
      return `• ${shortid} — ${p.name}${tag}`;
    }).join("\n");
    ctx.ui.notify(`[remote-pi] Paired devices:\n${lines}`, "info");
  }

  async revokeDevice(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    const shortid = arg.trim();
    if (!shortid) {
      ctx.ui.notify(
        "[remote-pi] Usage: /remote-pi revoke <shortid>. Run /remote-pi list to see shortids.",
        "warning",
      );
      return;
    }

    const cwd = cwdFrom(ctx);
    if (this.deps.getState() === "idle") {
      if (!localConfigExists(cwd)) {
        ctx.ui.notify(
          "[remote-pi] First-time setup needed. Run /remote-pi to configure, then /remote-pi revoke.",
          "warning",
        );
        return;
      }
      ctx.ui.notify("[remote-pi] Starting mesh + relay before revoking…", "info");
      await this.deps.joinLocalMesh(ctx);
      if (this.deps.getState() === "idle") await this.startRelay(ctx);
    }
    if (this.deps.getState() === "idle" || !this.deps.relay()) {
      ctx.ui.notify(
        "[remote-pi] Revoke requires the relay to be connected. " +
        "Run /remote-pi to start it (or fix your relay URL via /remote-pi set-relay).",
        "warning",
      );
      return;
    }

    const peers = await listPeers();
    const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));

    if (matches.length === 0) {
      ctx.ui.notify(
        `[remote-pi] No peer matching '${shortid}'. Run /remote-pi list to see shortids.`,
        "warning",
      );
      return;
    }

    if (matches.length > 1) {
      const collisions = matches.map((p) => p.remote_epk.slice(0, 8)).join(", ");
      ctx.ui.notify(
        `[remote-pi] Ambiguous shortid — ${matches.length} matches: ${collisions}. Use mais chars.`,
        "warning",
      );
      return;
    }

    const peer = matches[0]!;
    await removePeer(peer.remote_epk);
    this.deps.refreshPairingsCache();

    if (this.deps.ownerHas(peer.remote_epk)) {
      this.deps.owners.detach(peer.remote_epk, "session_replaced");
    }

    ctx.ui.notify(
      `[remote-pi] Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`,
      "info",
    );
  }

  installAutoListener(relay: RelayClient): () => void {
    const onMsg = (line: string) => { void this.handleOuterLine(relay, line); };
    relay.on("message", onMsg);
    return () => relay.off("message", onMsg);
  }

  async handlePairRequest(relay: RelayClient, appPeerId: string, inner: PairRequest): Promise<void> {
    const sendError = (code: PairErrorCode, message: string) => {
      sendToPeer(relay, appPeerId, { type: "pair_error", in_reply_to: inner.id, code, message });
    };

    const status = qrSession.consumeToken(inner.token) as PairTokenStatus;
    if (status !== "ok") {
      const error = pairErrorForStatus(status);
      sendError(error.code, error.message);
      return;
    }

    const pairedAt = new Date().toISOString();
    try {
      await addPeer({ name: inner.device_name, remote_epk: appPeerId, paired_at: pairedAt });
      this.deps.refreshPairingsCache();
    } catch (err) {
      if (this.isCurrentStartedRelay(relay)) {
        sendError("internal_error", `Failed to persist peer: ${String(err)}`);
      }
      return;
    }
    if (!this.isCurrentStartedRelay(relay)) return;

    const cwd = this.currentCwdForPairing();
    const sessionName = this.deps.displayName(cwd);
    const roomId = this.deps.roomId() ?? roomIdFor(cwd, sessionName);
    this.attachOwner({ relay, appPeerId, peerName: inner.device_name, roomId });

    const session = this.deps.currentPairingSession();
    sendToPeer(relay, appPeerId, {
      type: "pair_ok",
      in_reply_to: inner.id,
      session_name: session.sessionName,
      session_started_at: session.sessionStartedAt,
      session_id: session.sessionId,
      room_id: session.roomId,
      ...(session.harness ? { harness: session.harness } : {}),
      ...(session.hostname ? { hostname: session.hostname } : {}),
    });

    this.deps.onOwnerPaired({ peerId: appPeerId, peerName: inner.device_name, pairedAt });
  }

  private async handleOuterLine(relay: RelayClient, line: string): Promise<void> {
    const outer = decodeOuterEnvelope(line);
    if (!outer) return;
    if (!this.isCurrentStartedRelay(relay)) return;
    const roomId = this.deps.roomId();
    if (outer.room && roomId && outer.room !== roomId) return;
    if (this.deps.ownerHas(outer.peer)) return;

    const inner = decodeClientMessage(outer.ct);
    if (!inner) return;

    if (inner.type === "pair_request") {
      if (!isPairRequest(inner)) return;
      await this.handlePairRequest(relay, outer.peer, inner);
      return;
    }

    const known = await this.findKnownPeer(outer.peer);
    if (!this.isCurrentStartedRelay(relay)) return;
    if (known) {
      const channel = this.attachOwner({
        relay,
        appPeerId: outer.peer,
        peerName: known.name,
        roomId: roomId ?? undefined,
      });
      this.deps.owners.routeFrom(channel, inner);
      return;
    }

    sendToPeer(relay, outer.peer, this.deps.withCurrentSession({
      type: "error",
      code: "unknown_peer",
      message: "Peer not paired — re-scan QR",
    }));
  }

  private attachOwner(input: {
    relay: RelayClient;
    appPeerId: string;
    peerName: string;
    roomId?: string;
  }): PeerChannel {
    const attachInput = {
      relay: input.relay,
      peerId: input.appPeerId,
      roomId: input.roomId,
      turnActive: this.deps.turnWorking(),
      onMessage: (msg: ClientMessage, sender: PeerChannel) => this.deps.handleClientMessage(sender, msg),
      onDisconnect: (peerId: string) => this.deps.onPeerDisconnect(peerId),
    };
    const channel = this.deps.owners.attach(attachInput);
    this.deps.onOwnerAttached({
      peerId: input.appPeerId,
      peerName: input.peerName,
      activeCount: this.deps.ownerActiveCount(),
    });
    return channel;
  }

  private isCurrentStartedRelay(relay: RelayClient): boolean {
    return !this.deps.isDisposed() && this.deps.getState() === "started" && relay === this.deps.relay();
  }

  private async findKnownPeer(peerId: string): Promise<PeerRecord | null> {
    const peers = await listPeers();
    return peers.find((p) => p.remote_epk === peerId) ?? null;
  }

  private currentCwdForPairing(): string {
    const meta = this.deps.roomMeta();
    if (meta?.cwd) return meta.cwd;
    return process.cwd();
  }

  private ensureSelfRevoke(relayUrl: string, edKp: Ed25519Keypair): void {
    if (this.selfRevoke !== null) return;
    this.selfRevoke = new SelfRevoke({
      client: new MeshClient(relayUrl),
      storage: { listOwnerPubkeys, removePeer },
      myPubkey: edKp.publicKey,
      onRevoke: (ownerEpk) => {
        this.deps.refreshPairingsCache();
        if (this.deps.ownerHas(ownerEpk)) {
          this.deps.owners.detach(ownerEpk, "session_replaced");
        }
        const short = ownerEpk.slice(0, 8);
        this.deps.sendPiMessage({
          customType: "remote-pi:mesh-revoked",
          content:
            `🔒 Revoked by Owner ${short}…\n\n` +
            `The mobile app for this Owner removed this PC from the mesh. ` +
            `Re-pair via /remote-pi pair if this was unexpected.`,
          display: true,
        }, undefined, "mesh-revoked");
      },
      onMembersChanged: (siblings) => {
        this.deps.setSiblings(siblings);
      },
      log: { info: () => {}, warn: () => {}, error: () => {} },
    });
    this.selfRevoke.start();
  }
}

export function pairingShortidCompletions(
  prefix: string,
  valuePrefix = "",
): Promise<Array<{ value: string; label: string }>> {
  return listPeers()
    .then((peers) => peers
      .map((p) => ({ shortid: p.remote_epk.slice(0, 8), name: p.name }))
      .filter((x) => x.shortid.startsWith(prefix))
      .map((x) => ({ value: `${valuePrefix}${x.shortid}`, label: `${x.shortid} (${x.name})` })));
}
