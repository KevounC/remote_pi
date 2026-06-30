import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type { ClientMessage, ServerMessage, ThinkingLevel, SessionHistoryEvent } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { SdkSessionProjectionPort, WakeAgentResult } from "../extension/ports.js";
import type { ActionCtx, ActionPi, SdkModelLike } from "../actions/handlers.js";
import { RemoteSessionIssuer, type RemoteSessionId } from "./remote_session.js";
import type { TranscriptEvent } from "./transcript_event.js";
import {
  initialTurnSnapshot,
  projectTurn,
  reduceTurn,
  type TurnEvent,
  type TurnProjection,
  type TurnSnapshot,
  type TurnSource,
} from "./turn_state.js";
import {
  appendTranscriptEvent,
  deterministicTranscriptEventId,
  imagesFromContent,
  mapLegacyAgentMessagesToTranscriptEvents,
  projectSessionHistory,
  stringifyContent,
  stringifyToolResult,
  type LegacyAgentMessage,
} from "./transcript_projection.js";

export type AgentMessageApi = {
  sendMessage: (...args: Parameters<ExtensionAPI["sendMessage"]>) => void | Promise<void>;
  sendUserMessage: (...args: Parameters<ExtensionAPI["sendUserMessage"]>) => void | Promise<void>;
};

export type FreshActionApi = Partial<AgentMessageApi> & Partial<ActionPi> & Partial<ActionCtx>;

type RoomMetaPatch = {
  session_id?: string;
  model?: string;
  thinking?: ThinkingLevel;
  working?: boolean;
};

export interface SessionHistorySnapshot {
  sessionStartedAt: number;
  sessionId: RemoteSessionId;
  queued: Extract<ServerMessage, { type: "queued_message_state" }>;
  history(inReplyTo: string, limit?: number): Extract<ServerMessage, { type: "session_history" }>;
}

export interface SdkSessionProjectionOutputs {
  broadcast(message: ServerMessage): void;
  sendTo(sender: PeerChannel, message: ServerMessage): void;
  publishRoomMeta(patch: RoomMetaPatch): void;
  activeOwnerIds(): readonly string[];
  lateAttachTargets(): readonly { peerId: string; channel: PeerChannel }[];
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  onStaleMessageApi?(api: AgentMessageApi): void;
}

export interface SeededUserTurn {
  seeded: boolean;
  rollback(): void;
}

export interface SdkSessionProjectionOptions {
  outputs: SdkSessionProjectionOutputs;
}

const SYNC_LIMIT_DEFAULT = 30;

function syncLimit(): number {
  const raw = process.env["REMOTE_PI_SYNC_LIMIT"];
  const parsed = raw ? parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : SYNC_LIMIT_DEFAULT;
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

function isFreshActionApi(value: unknown): value is FreshActionApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as FreshActionApi;
  return typeof candidate.setModel === "function" ||
    typeof candidate.setThinkingLevel === "function";
}

function isStaleContextError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return message.includes("stale after session replacement or reload");
}

function userContentSignature(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
): string {
  return JSON.stringify({ text, images: images ?? [] });
}

function recordArgs(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export class SdkSessionProjection implements SdkSessionProjectionPort {
  private readonly issuer = new RemoteSessionIssuer();
  private sessionStartedAt: number | null = null;
  private transcriptEvents: TranscriptEvent[] = [];
  private readonly deliveredUserEventIds = new Map<string, { clientMessageId: string; eventId: string }[]>();
  private lastTranscriptUserId: string | null = null;
  private epoch = 0;
  private commandCtx: ExtensionCommandContext | null = null;
  private eventCtx: ExtensionContext | null = null;
  private messageApi: AgentMessageApi | null = null;
  private actionApi: FreshActionApi | null = null;
  private turn: TurnSnapshot = initialTurnSnapshot();

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
    this.replaceSessionCapabilities(ctx);
  }

  bindReplacementContext(ctx: ActionCtx): RemoteSessionId {
    this.commandCtx = ctx as unknown as ExtensionCommandContext;
    this.eventCtx = ctx as unknown as ExtensionContext;
    this.replaceSessionCapabilities(ctx);
    return this.captureRemoteSession(ctx);
  }

  clearApiBindings(): void {
    this.messageApi = null;
    this.actionApi = null;
  }

  clearStaleContexts(): void {
    this.epoch += 1;
    this.commandCtx = null;
    this.eventCtx = null;
    this.messageApi = null;
    this.actionApi = null;
  }

  captureRemoteSession(ctx: unknown): RemoteSessionId {
    const sessionId = this.issuer.capture(ctx);
    this.opts.outputs.publishRoomMeta({ session_id: sessionId });
    return sessionId;
  }

  currentRemoteSessionId(ctx?: unknown): RemoteSessionId {
    return this.issuer.currentOrCapture(ctx ?? this.eventCtx ?? this.commandCtx ?? undefined);
  }

  currentSessionMessage<T extends object>(msg: T): T & { session_id: RemoteSessionId } {
    return { ...msg, session_id: this.currentRemoteSessionId() };
  }

  currentSessionIdForTest(): RemoteSessionId | null {
    return this.issuer.current();
  }

  setSessionIdForTest(id: string | null): void {
    if (id === null) this.issuer.clear();
    else this.issuer.capture({ sessionManager: { getSessionId: () => id } });
  }

  sessionStartedAtValue(): number | null {
    return this.sessionStartedAt;
  }

  sessionStartedAtOrNow(now = Date.now()): number {
    return this.sessionStartedAt ?? now;
  }

  setSessionStartedAt(ts: number | null): void {
    this.sessionStartedAt = ts;
  }

  ensureSessionStarted(now = Date.now()): number {
    if (this.sessionStartedAt === null) this.sessionStartedAt = now;
    return this.sessionStartedAt;
  }

  appendTranscriptEvent(event: TranscriptEvent): void {
    this.transcriptEvents = appendTranscriptEvent(this.transcriptEvents, event);
  }

  appendUserConfirmedTranscriptEvent(input: {
    sessionId: string;
    ts: number;
    clientMessageId: string;
    text: string;
    images?: Extract<TranscriptEvent, { kind: "user_confirmed" }>["images"];
    streamingBehavior?: Extract<TranscriptEvent, { kind: "user_confirmed" }>["streamingBehavior"];
    eventId?: string;
  }): void {
    const eventId = input.eventId
      ?? deterministicTranscriptEventId(input.sessionId, "user_confirmed", input.clientMessageId);
    this.appendTranscriptEvent({
      kind: "user_confirmed",
      eventId,
      sessionId: input.sessionId,
      ts: input.ts,
      clientMessageId: input.clientMessageId,
      text: input.text,
      ...(input.images && input.images.length > 0 ? { images: [...input.images] } : {}),
      ...(input.streamingBehavior ? { streamingBehavior: input.streamingBehavior } : {}),
    });
    this.lastTranscriptUserId = input.clientMessageId;
  }

  rememberDeliveredUserEvent(
    text: string,
    images: readonly { data: string; mime: string }[] | undefined,
    clientMessageId: string,
    eventId: string,
  ): void {
    const key = userContentSignature(text, images);
    const existing = this.deliveredUserEventIds.get(key) ?? [];
    existing.push({ clientMessageId, eventId });
    this.deliveredUserEventIds.set(key, existing);
  }

  appendLegacySdkMessageToTranscript(message: LegacyAgentMessage): void {
    const sessionId = this.currentRemoteSessionId();
    const ts = typeof message.timestamp === "number" ? message.timestamp : Date.now();
    if (message.role === "user") {
      const text = stringifyContent(message.content);
      const images = imagesFromContent(message.content);
      const matched = this.consumeDeliveredUserEvent(text, images);
      const clientMessageId = matched?.clientMessageId ?? `sync_${ts}`;
      this.appendUserConfirmedTranscriptEvent({
        sessionId,
        ts,
        clientMessageId,
        text,
        ...(images.length > 0 ? { images } : {}),
        ...(matched ? { eventId: matched.eventId } : {}),
      });
      return;
    }

    if (message.role === "assistant") {
      const content = Array.isArray(message.content) ? message.content : [];
      const usage = message.usage
        ? { input_tokens: message.usage.input ?? 0, output_tokens: message.usage.output ?? 0 }
        : undefined;
      for (const [blockIndex, raw] of content.entries()) {
        if (!raw || typeof raw !== "object") continue;
        const block = raw as { type?: string; text?: unknown; id?: unknown; name?: unknown; arguments?: unknown };
        if (block.type === "text") {
          const text = String(block.text ?? "");
          if (!text) continue;
          const messageId = `sync_${ts}:assistant:${blockIndex}`;
          this.appendTranscriptEvent({
            kind: "assistant_committed",
            eventId: deterministicTranscriptEventId(sessionId, "assistant_committed", messageId),
            sessionId,
            ts,
            messageId,
            replyTo: this.lastTranscriptUserId ?? `sync_${ts}`,
            text,
            ...(usage ? { usage } : {}),
          });
        } else if (block.type === "toolCall") {
          const toolCallId = String(block.id ?? `sync_${ts}:tool:${blockIndex}`);
          this.appendTranscriptEvent({
            kind: "tool_requested",
            eventId: deterministicTranscriptEventId(sessionId, "tool_requested", toolCallId),
            sessionId,
            ts,
            toolCallId,
            tool: String(block.name ?? ""),
            args: recordArgs(block.arguments),
          });
        }
      }
      return;
    }

    if (message.role === "toolResult") {
      const toolCallId = String(message.toolCallId ?? `sync_${ts}:tool-result`);
      const text = stringifyToolResult(message.content);
      this.appendTranscriptEvent(message.isError
        ? {
            kind: "tool_finished",
            eventId: deterministicTranscriptEventId(sessionId, "tool_finished", toolCallId),
            sessionId,
            ts,
            toolCallId,
            error: text,
          }
        : {
            kind: "tool_finished",
            eventId: deterministicTranscriptEventId(sessionId, "tool_finished", toolCallId),
            sessionId,
            ts,
            toolCallId,
            result: text,
          });
    }
  }

  setLegacyMessageBufferForTest(msgs: unknown[]): void {
    this.clearTranscriptOnly();
    const sessionId = this.currentRemoteSessionId();
    this.transcriptEvents = mapLegacyAgentMessagesToTranscriptEvents({
      sessionId,
      messages: msgs as LegacyAgentMessage[],
    });
    this.recomputeLastTranscriptUserId();
  }

  setTranscriptEventsForTest(events: TranscriptEvent[]): void {
    this.deliveredUserEventIds.clear();
    this.transcriptEvents = [...events];
    this.recomputeLastTranscriptUserId();
  }

  getTranscriptEventsForTest(): TranscriptEvent[] {
    return [...this.transcriptEvents];
  }

  buildSessionHistoryMessage(
    inReplyTo: string,
    limit: number | undefined,
  ): Extract<ServerMessage, { type: "session_history" }> {
    const serverLimit = syncLimit();
    const requested = limit ?? serverLimit;
    const effectiveLimit = Math.min(requested, serverLimit);

    const projection = projectSessionHistory({
      sessionId: this.currentRemoteSessionId(),
      events: this.transcriptEvents,
      limit: effectiveLimit,
    });

    return this.currentSessionMessage({
      type: "session_history",
      in_reply_to: inReplyTo,
      session_started_at: this.sessionStartedAt ?? 0,
      events: projection.events,
      eos: true,
      truncated: projection.truncated,
    });
  }

  emptySessionHistoryMessage(inReplyTo: string): Extract<ServerMessage, { type: "session_history" }> {
    return this.currentSessionMessage({
      type: "session_history",
      in_reply_to: inReplyTo,
      session_started_at: this.sessionStartedAt ?? 0,
      events: [],
      eos: true,
      truncated: false,
    });
  }

  resetSessionForNew(inReplyTo: string): void {
    this.clearTranscriptOnly();
    this.sessionStartedAt = Date.now();
    this.opts.outputs.broadcast(this.emptySessionHistoryMessage(inReplyTo));
  }

  mapAgentMessagesToEvents(messages: LegacyAgentMessage[]): SessionHistoryEvent[] {
    const sessionId = this.currentRemoteSessionId();
    return projectSessionHistory({
      sessionId,
      events: mapLegacyAgentMessagesToTranscriptEvents({ sessionId, messages }),
      limit: Number.MAX_SAFE_INTEGER,
    }).events;
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

  turnProjection(): TurnProjection {
    return projectTurn(this.turn);
  }

  currentTurnIdForTest(): string | null {
    return this.turnProjection().activeTurnId;
  }

  applyTurn(event: TurnEvent): TurnProjection {
    const before = this.turnProjection();
    this.turn = reduceTurn(this.turn, event);
    const after = this.turnProjection();
    this.publishTurnProjection(before, after);
    return after;
  }

  resetTurnSnapshot(): void {
    const before = this.turnProjection();
    this.turn = initialTurnSnapshot();
    this.publishTurnProjection(before, this.turnProjection());
  }

  recordOwnerAttached(peerId: string): void {
    this.applyTurn({ type: "peer_attached", target: { kind: "owner", id: peerId } });
  }

  queuedMessageState(): Extract<ServerMessage, { type: "queued_message_state" }> {
    const queued = this.turnProjection().queuedMessage;
    return queued
      ? this.currentSessionMessage({ type: "queued_message_state", id: queued.id, text: queued.text })
      : this.currentSessionMessage({ type: "queued_message_state" });
  }

  broadcastQueuedMessageState(): void {
    this.opts.outputs.broadcast(this.queuedMessageState());
  }

  seedUserMessageTurn(input: {
    turnId: string;
    source: Exclude<TurnSource, "compaction">;
    shouldSteer: boolean;
  }): SeededUserTurn {
    const previous = this.turn;
    const seeded = !input.shouldSteer || this.turnProjection().activeTurnId === null;
    if (seeded) {
      this.applyTurn({
        type: "user_message_accepted",
        turnId: input.turnId,
        replyTo: input.turnId,
        source: input.source,
      });
    }
    return {
      seeded,
      rollback: () => {
        if (!seeded) return;
        const before = this.turnProjection();
        this.turn = previous;
        this.publishTurnProjection(before, this.turnProjection());
      },
    };
  }

  maybeDrainQueuedMessage(
    deliver: (message: Extract<ClientMessage, { type: "user_message" }>) => void | Promise<void>,
  ): void {
    const projection = this.turnProjection();
    const queued = projection.queuedMessage;
    if (!queued || !projection.canDrainQueuedMessage) return;
    this.applyTurn({ type: "queued_message_clear" });
    this.broadcastQueuedMessageState();
    void deliver(this.currentSessionMessage({ type: "user_message", id: queued.id, text: queued.text }));
  }

  maybeSendLateAttachSessionSync(
    buildHistory: (inReplyTo: string) => Extract<ServerMessage, { type: "session_history" }>,
  ): void {
    const projection = this.turnProjection();
    if (!projection.canFlushLateAttachSync || projection.awaitingSyncTurnId === null) return;
    const history = buildHistory(projection.awaitingSyncTurnId);
    const activeTargets = new Map(this.opts.outputs.lateAttachTargets().map((entry) => [entry.peerId, entry.channel]));
    for (const target of projection.lateAttachSyncTargets) {
      if (target.kind !== "owner") continue;
      const channel = activeTargets.get(target.id);
      if (!channel) continue;
      try { this.opts.outputs.sendTo(channel, history); } catch { /* best-effort per late attach */ }
    }
    this.applyTurn({ type: "flush_late_attach_sync" });
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

  currentActionPi(action: "model_set" | "thinking_set"): ActionPi | null {
    const api = this.actionApi;
    if (!api) return null;
    if (action === "model_set" && typeof api.setModel !== "function") return null;
    if (action === "thinking_set" && typeof api.setThinkingLevel !== "function") return null;
    return this.wrapActionPi(api);
  }

  freshActionCtx(): ActionCtx | null {
    const ctx = this.eventCtx ?? this.commandCtx;
    return ctx ? this.wrapActionCtx(ctx as unknown as ActionCtx) : null;
  }

  freshCommandActionCtx(): ActionCtx | null {
    return this.commandCtx ? this.wrapActionCtx(this.commandCtx as unknown as ActionCtx) : null;
  }

  forgetStaleBinding(value: unknown): void {
    if (value === this.commandCtx) this.commandCtx = null;
    if (value === this.eventCtx) this.eventCtx = null;
    if (value === this.messageApi) {
      this.messageApi = null;
      this.opts.outputs.onStaleMessageApi?.(value as AgentMessageApi);
    }
    if (value === this.actionApi) this.actionApi = null;
  }

  private publishTurnProjection(before: TurnProjection, after: TurnProjection): void {
    if (before.working === after.working) return;
    this.publishWorking(after.working);
  }

  private bindCapabilities(value: unknown): void {
    if (isAgentMessageApi(value)) this.messageApi = value;
    if (isFreshActionApi(value)) this.actionApi = value;
  }

  private replaceSessionCapabilities(value: unknown): void {
    this.messageApi = isAgentMessageApi(value) ? value : null;
    this.actionApi = isFreshActionApi(value) ? value : null;
  }

  private forget(api: AgentMessageApi): void {
    if (api !== this.messageApi) return;
    this.messageApi = null;
    if (api === this.actionApi) this.actionApi = null;
    this.opts.outputs.onStaleMessageApi?.(api);
  }

  private forgetActionApi(api: FreshActionApi): void {
    if (api === this.actionApi) this.actionApi = null;
    if (api === this.messageApi) {
      this.messageApi = null;
      this.opts.outputs.onStaleMessageApi?.(api as AgentMessageApi);
    }
  }

  private wrapActionPi(api: FreshActionApi): ActionPi {
    return {
      setModel: async (model: SdkModelLike) => {
        if (typeof api.setModel !== "function") throw new Error("Pi model API unavailable for the current session");
        try {
          return await api.setModel(model);
        } catch (err) {
          if (isStaleContextError(err)) this.forgetActionApi(api);
          throw err;
        }
      },
      setThinkingLevel: (level: ThinkingLevel) => {
        if (typeof api.setThinkingLevel !== "function") throw new Error("Pi thinking API unavailable for the current session");
        try {
          api.setThinkingLevel(level);
        } catch (err) {
          if (isStaleContextError(err)) this.forgetActionApi(api);
          throw err;
        }
      },
    };
  }

  private wrapActionCtx(ctx: ActionCtx): ActionCtx {
    const wrapped: ActionCtx = {};
    if (typeof ctx.compact === "function") {
      wrapped.compact = (options?: object) => {
        try {
          return ctx.compact?.(options);
        } catch (err) {
          if (isStaleContextError(err)) this.forgetStaleBinding(ctx);
          throw err;
        }
      };
    }
    if (typeof ctx.newSession === "function") {
      wrapped.newSession = async (options) => {
        try {
          return await ctx.newSession!(options);
        } catch (err) {
          if (isStaleContextError(err)) this.forgetStaleBinding(ctx);
          throw err;
        }
      };
    }
    if (typeof ctx.getModel === "function") {
      wrapped.getModel = () => {
        try {
          return ctx.getModel?.();
        } catch (err) {
          if (isStaleContextError(err)) this.forgetStaleBinding(ctx);
          throw err;
        }
      };
    }
    if (ctx.modelRegistry) wrapped.modelRegistry = ctx.modelRegistry;
    return wrapped;
  }

  private consumeDeliveredUserEvent(
    text: string,
    images: readonly { data: string; mime: string }[] | undefined,
  ): { clientMessageId: string; eventId: string } | undefined {
    const key = userContentSignature(text, images);
    const existing = this.deliveredUserEventIds.get(key);
    if (!existing || existing.length === 0) return undefined;
    const match = existing.shift();
    if (existing.length === 0) this.deliveredUserEventIds.delete(key);
    return match;
  }

  private clearTranscriptOnly(): void {
    this.transcriptEvents = [];
    this.deliveredUserEventIds.clear();
    this.lastTranscriptUserId = null;
  }

  private recomputeLastTranscriptUserId(): void {
    const lastUser = [...this.transcriptEvents].reverse().find((event) =>
      event.kind === "user_confirmed" || event.kind === "user_submitted"
    );
    this.lastTranscriptUserId = lastUser?.clientMessageId ?? null;
  }
}
