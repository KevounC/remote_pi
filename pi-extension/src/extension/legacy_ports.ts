import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { RelayClient } from "../transport/relay_client.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type {
  AttachOwnerInput,
  CommandSurfacePort,
  CrossPcBridgeInput,
  OwnerMultiplexerPort,
  RelayStartInput,
  RelayStartResult,
  RelayTransportPort,
  RemotePiRuntime,
  RemotePiRuntimePorts,
  SdkSessionProjectionPort,
  WakeAgentResult,
} from "./ports.js";
import type { ByeReason, ClientMessage, ServerMessage } from "../protocol/types.js";
import type { RelayConnectivity } from "./types.js";

export interface LegacyRelayTransportDeps {
  status(): RelayConnectivity;
  start(input: RelayStartInput): Promise<RelayStartResult>;
  stop(reason?: ByeReason): void;
  sendRoomMeta: RelayTransportPort["sendRoomMeta"];
  onOuterMessage(handler: (line: string) => void | Promise<void>): () => void;
  attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void>;
  detachCrossPcBridge(): void;
  relay(): RelayClient | null;
  setRelay(relay: RelayClient | null): void;
}

export interface LegacyOwnerMultiplexerDeps {
  activeCount(): number;
  attach(input: AttachOwnerInput): PeerChannel;
  detach(peerId: string, reason?: ByeReason): void;
  broadcast(message: ServerMessage): void;
  routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  lateAttachTargets(): readonly PeerChannel[];
}

export interface LegacySdkSessionProjectionDeps {
  bindApi(pi: ExtensionAPI): void;
  bindCommandContext(ctx: ExtensionCommandContext): void;
  bindSessionContext(ctx: ExtensionContext): void;
  clearStaleContexts(): void;
  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean;
  wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<WakeAgentResult>;
  publishWorking(working: boolean): void;
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
}

export interface LegacyCommandSurfaceDeps {
  register(pi: ExtensionAPI, runtime: RemotePiRuntime): void;
  ensureStarted?(ctx: ExtensionContext): void | Promise<void>;
  prepareSessionShutdown?(): void;
  closeMesh?(): Promise<void>;
}

export interface LegacyIndexDeps {
  relay: LegacyRelayTransportDeps;
  owners: LegacyOwnerMultiplexerDeps;
  session: LegacySdkSessionProjectionDeps;
  commands: LegacyCommandSurfaceDeps;
}

export function createLegacyIndexPorts(deps: LegacyIndexDeps): RemotePiRuntimePorts {
  return {
    relay: createLegacyRelayTransport(deps.relay),
    owners: createLegacyOwnerMultiplexer(deps.owners),
    session: createLegacySdkSessionProjection(deps.session),
    commands: createLegacyCommandSurface(deps.commands),
  };
}

function createLegacyRelayTransport(deps: LegacyRelayTransportDeps): RelayTransportPort {
  return {
    status: () => deps.status(),
    start: (input) => deps.start(input),
    stop: (reason) => deps.stop(reason),
    sendRoomMeta: (patch) => deps.sendRoomMeta(patch),
    onOuterMessage: (handler) => deps.onOuterMessage(handler),
    attachCrossPcBridge: (input) => deps.attachCrossPcBridge(input),
    detachCrossPcBridge: () => deps.detachCrossPcBridge(),
  };
}

function createLegacyOwnerMultiplexer(deps: LegacyOwnerMultiplexerDeps): OwnerMultiplexerPort {
  return {
    activeCount: () => deps.activeCount(),
    attach: (input) => deps.attach(input),
    detach: (peerId, reason) => deps.detach(peerId, reason),
    broadcast: (message) => deps.broadcast(message),
    routeFrom: (sender, message) => deps.routeFrom(sender, message),
    lateAttachTargets: () => deps.lateAttachTargets(),
  };
}

function createLegacySdkSessionProjection(deps: LegacySdkSessionProjectionDeps): SdkSessionProjectionPort {
  return {
    bindApi: (pi) => deps.bindApi(pi),
    bindCommandContext: (ctx) => deps.bindCommandContext(ctx),
    bindSessionContext: (ctx) => deps.bindSessionContext(ctx),
    clearStaleContexts: () => deps.clearStaleContexts(),
    sendPiMessage: (...args) => deps.sendPiMessage(...args),
    wakeAgent: (...args) => deps.wakeAgent(...args),
    publishWorking: (working) => deps.publishWorking(working),
    handleClientMessage: (sender, message) => deps.handleClientMessage(sender, message),
  };
}

function createLegacyCommandSurface(deps: LegacyCommandSurfaceDeps): CommandSurfacePort {
  const port: CommandSurfacePort = {
    register: (pi, runtime) => deps.register(pi, runtime),
  };
  if (deps.ensureStarted) port.ensureStarted = (ctx) => deps.ensureStarted?.(ctx);
  if (deps.prepareSessionShutdown) port.prepareSessionShutdown = () => deps.prepareSessionShutdown?.();
  if (deps.closeMesh) port.closeMesh = () => deps.closeMesh?.() ?? Promise.resolve();
  return port;
}
