import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type {
  ByeReason,
  ClientMessage,
  ServerMessage,
  ThinkingLevel,
} from "../protocol/types.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { RelayConnectivity } from "./types.js";

export interface RuntimeEpoch {
  readonly id: number;
  readonly disposed: boolean;
  isCurrent(): boolean;
  dispose(): void;
}

export interface RuntimeUiPort {
  notify(message: string, type?: "info" | "warning" | "error"): void;
  setStatus(key: string, value: string | undefined): void;
  setTitle(title: string): void;
}

export interface RelayStartInput {
  relayUrl: string;
  roomId?: string;
  roomMeta?: RoomMeta;
}

export interface RelayStartResult {
  relay: RelayClient;
  roomId?: string;
}

export interface CrossPcBridgeInput {
  relay: RelayClient;
  roomId: string;
  localPcLabel: string;
}

export interface RelayTransportPort {
  status(): RelayConnectivity;
  start(input: RelayStartInput): Promise<RelayStartResult>;
  stop(reason?: ByeReason): void;
  sendRoomMeta(patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel }): void;
  onOuterMessage(handler: (line: string) => void | Promise<void>): () => void;
  attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void>;
  detachCrossPcBridge(): void;
}

export interface AttachOwnerInput {
  relay: RelayClient;
  peerId: string;
  roomId?: string;
  onMessage(message: ClientMessage, sender: PeerChannel): void | Promise<void>;
  onDisconnect?(peerId: string): void;
}

export interface OwnerMultiplexerPort {
  activeCount(): number;
  attach(input: AttachOwnerInput): PeerChannel;
  detach(peerId: string, reason?: ByeReason): void;
  broadcast(message: ServerMessage): void;
  routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  lateAttachTargets(): readonly PeerChannel[];
}

export interface WakeAgentResult {
  ok: boolean;
  detail?: string;
}

export interface SdkSessionProjectionPort {
  bindApi(pi: ExtensionAPI): void;
  bindCommandContext(ctx: ExtensionCommandContext): void;
  bindSessionContext(ctx: ExtensionContext): void;
  clearStaleContexts(): void;
  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean;
  wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<WakeAgentResult>;
  publishWorking(working: boolean): void;
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
}

export interface RemotePiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: RemotePiRuntimePorts;
}

export interface CommandSurfacePort {
  register(pi: ExtensionAPI, runtime: RemotePiRuntime): void;
}

export interface RemotePiRuntimePorts {
  relay: RelayTransportPort;
  owners: OwnerMultiplexerPort;
  session: SdkSessionProjectionPort;
  commands: CommandSurfacePort;
}
