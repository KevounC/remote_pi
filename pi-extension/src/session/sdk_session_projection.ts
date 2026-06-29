import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type { ClientMessage, ServerMessage, ThinkingLevel } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { SdkSessionProjectionPort, WakeAgentResult } from "../extension/ports.js";

export type AgentMessageApi = {
  sendMessage: (...args: Parameters<ExtensionAPI["sendMessage"]>) => void | Promise<void>;
  sendUserMessage: (...args: Parameters<ExtensionAPI["sendUserMessage"]>) => void | Promise<void>;
};

type RoomMetaPatch = {
  session_id?: string;
  model?: string;
  thinking?: ThinkingLevel;
  working?: boolean;
};

export interface SdkSessionProjectionOutputs {
  broadcast(message: ServerMessage): void;
  sendTo(sender: PeerChannel, message: ServerMessage): void;
  publishRoomMeta(patch: RoomMetaPatch): void;
  activeOwnerIds(): readonly string[];
  lateAttachTargets(): readonly { peerId: string; channel: PeerChannel }[];
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  onStaleMessageApi?(api: AgentMessageApi): void;
}

export interface SdkSessionProjectionOptions {
  outputs: SdkSessionProjectionOutputs;
}

function isPromiseLike(value: unknown): value is PromiseLike<void> {
  return !!value &&
    (typeof value === "object" || typeof value === "function") &&
    typeof (value as { then?: unknown }).then === "function";
}

export function isAgentMessageApi(value: unknown): value is AgentMessageApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<AgentMessageApi>;
  return typeof candidate.sendMessage === "function" &&
    typeof candidate.sendUserMessage === "function";
}

function isStaleContextError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return message.includes("stale after session replacement or reload");
}

export class SdkSessionProjection implements SdkSessionProjectionPort {
  private epoch = 0;
  private commandCtx: ExtensionCommandContext | null = null;
  private eventCtx: ExtensionContext | null = null;
  private messageApi: AgentMessageApi | null = null;

  constructor(private readonly opts: SdkSessionProjectionOptions) {}

  bindApi(pi: ExtensionAPI): void {
    this.bindCapabilities(pi);
  }

  bindCommandContext(ctx: ExtensionCommandContext): void {
    this.commandCtx = ctx;
    this.bindCapabilities(ctx);
  }

  bindSessionContext(ctx: ExtensionContext): void {
    this.eventCtx = ctx;
    this.bindCapabilities(ctx);
  }

  clearStaleContexts(): void {
    this.epoch += 1;
    this.commandCtx = null;
    this.eventCtx = null;
    this.messageApi = null;
  }

  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean {
    const api = this.messageApi;
    if (!api) return false;
    try {
      const delivered = api.sendMessage(...args);
      if (isPromiseLike(delivered)) {
        delivered.catch((err: unknown) => {
          if (isStaleContextError(err)) this.forget(api);
        });
      }
      return true;
    } catch (err) {
      if (isStaleContextError(err)) this.forget(api);
      return false;
    }
  }

  async wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<WakeAgentResult> {
    const api = this.messageApi;
    if (!api) return { ok: false, detail: "agent session not bound yet" };
    try {
      await api.sendUserMessage(...args);
      return { ok: true };
    } catch (err) {
      if (isStaleContextError(err)) this.forget(api);
      return { ok: false, detail: err instanceof Error ? err.message : String(err) };
    }
  }

  publishWorking(working: boolean): void {
    this.opts.outputs.publishRoomMeta({ working });
  }

  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void> {
    return this.opts.outputs.handleClientMessage(sender, message);
  }

  currentEpoch(): number {
    return this.epoch;
  }

  commandContext(): ExtensionCommandContext | null {
    return this.commandCtx;
  }

  sessionContext(): ExtensionContext | null {
    return this.eventCtx;
  }

  messageApiBinding(): AgentMessageApi | null {
    return this.messageApi;
  }

  private bindCapabilities(value: unknown): void {
    if (isAgentMessageApi(value)) this.messageApi = value;
  }

  private forget(api: AgentMessageApi): void {
    if (api !== this.messageApi) return;
    this.messageApi = null;
    this.opts.outputs.onStaleMessageApi?.(api);
  }
}
