import type { ByeReason, ThinkingLevel } from "../protocol/types.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import {
  REACHABILITY_RELAY_LIVENESS_CHECK_MS,
  REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  reachabilityBackoffMs,
} from "../reachability/reachability_contract.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import type {
  CrossPcBridgeInput,
  RelayStartInput,
  RelayStartResult,
  RelayTransportPort,
} from "./ports.js";
import type { RelayConnectivity } from "./types.js";

export interface RelayStateSnapshot {
  status: RelayConnectivity;
  connected: boolean;
  relayUrl?: string;
  room?: string;
}

export interface RelayTransportStartInput extends RelayStartInput {
  isDisposed?: () => boolean;
  onUnexpectedClose?: () => void;
  onConnected?: (relay: RelayClient) => void | Promise<void>;
}

export class RelayStartAbortedError extends Error {
  constructor() {
    super("relay start aborted");
    this.name = "RelayStartAbortedError";
  }
}

export interface RelayTransportDeps {
  createRelay(url: string, keypair: Ed25519Keypair): RelayClient;
  toWebSocketUrl(url: string): string;
  backoffMs(attempt: number): number;
  now(): number;
  setTimer(cb: () => void, delayMs: number): ReturnType<typeof setTimeout>;
  clearTimer(timer: ReturnType<typeof setTimeout>): void;
  emitRelayState(snapshot: RelayStateSnapshot): void;
}

export interface RelayTransportAdapter extends Omit<RelayTransportPort, "start"> {
  start(input: RelayTransportStartInput): Promise<RelayStartResult>;
  emitRelayState(force?: boolean): void;
  hasPendingReconnect(): boolean;
  currentRelayUrl(): string | null;
  /**
   * @internal Temporary owner-channel bridge while legacy call sites still need
   * direct access to the live RelayClient. Remove when owner ingress is fully
   * routed through RelayTransportPort.
   */
  currentRelayForOwnerChannels(): RelayClient | null;
}

export const RELAY_TRANSPORT_REACHABILITY = {
  backoffMs: reachabilityBackoffMs,
  livenessTimeoutMs: REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  livenessCheckMs: REACHABILITY_RELAY_LIVENESS_CHECK_MS,
} as const;

export function createRelayTransportPort(deps: RelayTransportDeps): RelayTransportAdapter {
  const backoffMs = deps.backoffMs ?? reachabilityBackoffMs;
  let relay: RelayClient | null = null;
  let relayUrl: string | null = null;
  let keypair: Ed25519Keypair | null = null;
  let roomId: string | null = null;
  let roomMeta: RoomMeta | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let reconnectAttempt = 0;
  let lastStatus: RelayConnectivity | null = null;
  let lastEmittedStatus: RelayConnectivity | null = null;
  let lastStatusChangedAt = deps.now();
  let stopping = false;
  let crossPcBridgeInput: CrossPcBridgeInput | null = null;
  let isDisposed: (() => boolean) | null = null;
  let onUnexpectedClose: (() => void) | null = null;
  let onConnected: ((relay: RelayClient) => void | Promise<void>) | null = null;
  const outerMessageHandlers = new Set<(line: string) => void | Promise<void>>();

  function setLastStatus(status: RelayConnectivity): RelayConnectivity {
    if (status !== lastStatus) {
      lastStatus = status;
      lastStatusChangedAt = deps.now();
    }
    return status;
  }

  function status(): RelayConnectivity {
    void lastStatusChangedAt;
    if (!relayUrl) return setLastStatus("disconnected");
    return setLastStatus(relay ? "connected" : "reconnecting");
  }

  function snapshot(): RelayStateSnapshot {
    const nextStatus = status();
    return {
      status: nextStatus,
      connected: nextStatus === "connected",
      ...(relayUrl ? { relayUrl } : {}),
      ...(roomId ? { room: roomId } : {}),
    };
  }

  function emitRelayState(force = false): void {
    const nextStatus = status();
    if (!force && nextStatus === lastEmittedStatus) return;
    lastEmittedStatus = nextStatus;
    deps.emitRelayState(snapshot());
  }

  function bindRelay(next: RelayClient): void {
    for (const handler of outerMessageHandlers) next.on("message", handler);
    next.on("close", onRelayClose);
  }

  function unbindRelay(current: RelayClient): void {
    current.off("close", onRelayClose);
    for (const handler of outerMessageHandlers) current.off("message", handler);
  }

  function clearReconnectTimer(): void {
    if (reconnectTimer === null) return;
    deps.clearTimer(reconnectTimer);
    reconnectTimer = null;
  }

  function onRelayClose(): void {
    if (stopping || !relayUrl) return;
    if (relay) {
      unbindRelay(relay);
      relay = null;
    }
    onUnexpectedClose?.();
    emitRelayState();
    scheduleReconnect();
  }

  function scheduleReconnect(): void {
    if (reconnectTimer !== null) return;
    if (!relayUrl || !keypair) return;
    if (status() === "disconnected") return;
    const delayMs = backoffMs(reconnectAttempt);
    reconnectAttempt += 1;
    reconnectTimer = deps.setTimer(() => {
      reconnectTimer = null;
      void attemptReconnect();
    }, delayMs);
  }

  async function attemptReconnect(): Promise<void> {
    if (status() === "disconnected" || !relayUrl || !keypair) return;
    const nextRelay = deps.createRelay(deps.toWebSocketUrl(relayUrl), keypair);
    try {
      await nextRelay.connect({
        ...(roomId ? { roomId } : {}),
        ...(roomMeta ? { roomMeta } : {}),
      });
    } catch {
      if (status() !== "disconnected") scheduleReconnect();
      return;
    }

    if (status() === "disconnected" || isDisposed?.()) {
      nextRelay.close();
      return;
    }

    relay = nextRelay;
    reconnectAttempt = 0;
    bindRelay(nextRelay);
    if (onConnected) void onConnected(nextRelay);
    if (crossPcBridgeInput) {
      void attachCrossPcBridge(crossPcBridgeInput);
    }
    emitRelayState();
  }

  async function start(input: RelayTransportStartInput): Promise<RelayStartResult> {
    if (!input.keypair) throw new Error("remote-pi identity not loaded");
    stopping = false;
    clearReconnectTimer();
    const nextRelay = deps.createRelay(deps.toWebSocketUrl(input.relayUrl), input.keypair);
    await nextRelay.connect({ roomId: input.roomId, roomMeta: input.roomMeta });
    if (input.isDisposed?.()) {
      nextRelay.close();
      throw new RelayStartAbortedError();
    }
    if (relay) {
      unbindRelay(relay);
      relay.close();
    }
    relay = nextRelay;
    relayUrl = input.relayUrl;
    keypair = input.keypair;
    roomId = input.roomId ?? null;
    roomMeta = input.roomMeta ?? null;
    isDisposed = input.isDisposed ?? null;
    onUnexpectedClose = input.onUnexpectedClose ?? null;
    onConnected = input.onConnected ?? null;
    reconnectAttempt = 0;
    bindRelay(nextRelay);
    if (onConnected) void onConnected(nextRelay);
    emitRelayState();
    return { relay: nextRelay, roomId: input.roomId };
  }

  function stop(_reason?: ByeReason): void {
    stopping = true;
    clearReconnectTimer();
    reconnectAttempt = 0;
    const current = relay;
    relay = null;
    relayUrl = null;
    keypair = null;
    roomId = null;
    roomMeta = null;
    crossPcBridgeInput = null;
    onUnexpectedClose = null;
    onConnected = null;
    if (current) {
      unbindRelay(current);
      current.close();
    }
    emitRelayState();
  }

  function sendRoomMeta(
    patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel },
  ): void {
    if (!roomId) return;
    if (roomMeta) roomMeta = { ...roomMeta, ...patch };
    relay?.sendControl({ type: "room_meta_update", room_id: roomId, meta: patch });
  }

  function onOuterMessage(handler: (line: string) => void | Promise<void>): () => void {
    outerMessageHandlers.add(handler);
    relay?.on("message", handler);
    return () => {
      outerMessageHandlers.delete(handler);
      relay?.off("message", handler);
    };
  }

  async function attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void> {
    crossPcBridgeInput = input;
  }

  function detachCrossPcBridge(): void {
    crossPcBridgeInput = null;
  }

  return {
    status,
    start,
    stop,
    sendRoomMeta,
    onOuterMessage,
    attachCrossPcBridge,
    detachCrossPcBridge,
    emitRelayState,
    hasPendingReconnect: () => reconnectTimer !== null,
    currentRelayUrl: () => relayUrl,
    currentRelayForOwnerChannels: () => relay,
  };
}
