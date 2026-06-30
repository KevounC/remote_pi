import type { SessionHistoryEvent, Usage, WireImage } from "../protocol/types.js";
import type { TranscriptEvent } from "./transcript_event.js";

export type LegacyAgentMessage = {
  role: "user" | "assistant" | "toolResult" | "compaction" | string;
  content?: unknown;
  timestamp?: number;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
  usage?: { input?: number; output?: number };
  tokensBefore?: number;
};

export type SessionHistoryProjection = {
  events: SessionHistoryEvent[];
  truncated: boolean;
};

type ProjectSessionHistoryInput = {
  sessionId: string;
  events: readonly TranscriptEvent[];
  limit: number;
};

type LegacyAdapterInput = {
  sessionId: string;
  messages: readonly LegacyAgentMessage[];
};

export function appendTranscriptEvent(
  events: readonly TranscriptEvent[],
  event: TranscriptEvent,
): TranscriptEvent[] {
  if (events.some((candidate) => candidate.eventId === event.eventId)) return [...events];
  return [...events, event];
}

export function projectSessionHistory(input: ProjectSessionHistoryInput): SessionHistoryProjection {
  const deduped = dedupeTranscriptEvents(input.events)
    .filter((event) => event.sessionId === input.sessionId);
  const allEvents = transcriptEventsToSessionHistory(deduped);
  const effectiveLimit = Math.max(0, input.limit);
  const slice = effectiveLimit > 0 ? allEvents.slice(-effectiveLimit) : [];
  return {
    events: slice,
    truncated: allEvents.length > effectiveLimit,
  };
}

export function transcriptEventsToSessionHistory(
  events: readonly TranscriptEvent[],
): SessionHistoryEvent[] {
  const out: SessionHistoryEvent[] = [];
  const seenUserIds = new Set<string>();
  const seenToolRequests = new Set<string>();
  const seenToolFinishes = new Set<string>();
  const seenAssistantMessages = new Set<string>();
  const seenCompactions = new Set<string>();

  for (const event of events) {
    switch (event.kind) {
      case "user_submitted":
      case "user_confirmed": {
        if (seenUserIds.has(event.clientMessageId)) break;
        seenUserIds.add(event.clientMessageId);
        const projected: SessionHistoryEvent = {
          ts: event.ts,
          type: "user_input",
          id: event.clientMessageId,
          text: event.text,
        };
        if (event.images && event.images.length > 0) projected.images = event.images;
        out.push(projected);
        break;
      }
      case "assistant_committed": {
        if (seenAssistantMessages.has(event.messageId)) break;
        seenAssistantMessages.add(event.messageId);
        const projected: SessionHistoryEvent = {
          ts: event.ts,
          type: "agent_message",
          in_reply_to: event.replyTo,
          text: event.text,
        };
        const usage = toWireUsage(event.usage);
        if (usage) projected.usage = usage;
        out.push(projected);
        break;
      }
      case "tool_requested": {
        if (seenToolRequests.has(event.toolCallId)) break;
        seenToolRequests.add(event.toolCallId);
        out.push({
          ts: event.ts,
          type: "tool_request",
          tool_call_id: event.toolCallId,
          tool: event.tool,
          args: event.args,
        });
        break;
      }
      case "tool_finished": {
        if (seenToolFinishes.has(event.toolCallId)) break;
        seenToolFinishes.add(event.toolCallId);
        out.push(event.error !== undefined
          ? { ts: event.ts, type: "tool_result", tool_call_id: event.toolCallId, error: event.error }
          : { ts: event.ts, type: "tool_result", tool_call_id: event.toolCallId, result: event.result });
        break;
      }
      case "compaction_recorded": {
        if (seenCompactions.has(event.eventId)) break;
        seenCompactions.add(event.eventId);
        out.push({
          ts: event.ts,
          type: "compaction",
          summary: event.summary,
          tokens_before: event.tokensBefore ?? 0,
        });
        break;
      }
      case "user_failed":
      case "assistant_delta":
      case "assistant_done":
        break;
    }
  }

  return out;
}

export function mapLegacyAgentMessagesToTranscriptEvents(input: LegacyAdapterInput): TranscriptEvent[] {
  const events: TranscriptEvent[] = [];
  let lastUserId: string | null = null;
  for (const [messageIndex, message] of input.messages.entries()) {
    const ts = typeof message.timestamp === "number" ? message.timestamp : 0;
    if (message.role === "compaction") {
      events.push({
        kind: "compaction_recorded",
        eventId: deterministicTranscriptEventId(input.sessionId, "compaction_recorded", String(ts)),
        sessionId: input.sessionId,
        ts,
        summary: typeof message.content === "string" ? message.content : "",
        tokensBefore: typeof message.tokensBefore === "number" ? message.tokensBefore : 0,
      });
    } else if (message.role === "user") {
      const clientMessageId = `sync_${ts}`;
      lastUserId = clientMessageId;
      const images = imagesFromContent(message.content);
      events.push({
        kind: "user_confirmed",
        eventId: deterministicTranscriptEventId(input.sessionId, "user_confirmed", clientMessageId),
        sessionId: input.sessionId,
        ts,
        clientMessageId,
        text: stringifyContent(message.content),
        ...(images.length > 0 ? { images } : {}),
      });
    } else if (message.role === "assistant") {
      const content = Array.isArray(message.content) ? message.content : [];
      const usage = message.usage ? { input_tokens: message.usage.input ?? 0, output_tokens: message.usage.output ?? 0 } : undefined;
      for (const [blockIndex, raw] of content.entries()) {
        if (!raw || typeof raw !== "object") continue;
        const block = raw as { type?: string; text?: unknown; id?: unknown; name?: unknown; arguments?: unknown };
        if (block.type === "text") {
          const text = String(block.text ?? "");
          if (!text) continue;
          const messageId = `sync_${ts}:assistant:${blockIndex}`;
          events.push({
            kind: "assistant_committed",
            eventId: deterministicTranscriptEventId(input.sessionId, "assistant_committed", messageId),
            sessionId: input.sessionId,
            ts,
            messageId,
            replyTo: lastUserId ?? `sync_${ts}`,
            text,
            ...(usage ? { usage } : {}),
          });
        } else if (block.type === "toolCall") {
          const toolCallId = String(block.id ?? `sync_${ts}:tool:${blockIndex}`);
          events.push({
            kind: "tool_requested",
            eventId: deterministicTranscriptEventId(input.sessionId, "tool_requested", toolCallId),
            sessionId: input.sessionId,
            ts,
            toolCallId,
            tool: String(block.name ?? ""),
            args: isRecord(block.arguments) ? block.arguments : {},
          });
        }
      }
    } else if (message.role === "toolResult") {
      const toolCallId = String(message.toolCallId ?? `sync_${ts}:tool-result:${messageIndex}`);
      const text = stringifyToolResult(message.content);
      events.push(message.isError
        ? {
            kind: "tool_finished",
            eventId: deterministicTranscriptEventId(input.sessionId, "tool_finished", toolCallId),
            sessionId: input.sessionId,
            ts,
            toolCallId,
            error: text,
          }
        : {
            kind: "tool_finished",
            eventId: deterministicTranscriptEventId(input.sessionId, "tool_finished", toolCallId),
            sessionId: input.sessionId,
            ts,
            toolCallId,
            result: text,
          });
    }
  }
  return events;
}

export function stringifyContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((block) => {
      if (!block || typeof block !== "object") return "";
      const typed = block as { type?: string; text?: unknown };
      return typed.type === "text" ? String(typed.text ?? "") : "";
    })
    .join("");
}

export function stringifyToolResult(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return stringifyContent(value);
  if (value !== null && typeof value === "object") {
    const obj = value as { content?: unknown; text?: unknown };
    if (Array.isArray(obj.content)) return stringifyContent(obj.content);
    if (typeof obj.text === "string") return obj.text;
    try { return JSON.stringify(value); } catch { return ""; }
  }
  return value === null || value === undefined ? "" : String(value);
}

export function imagesFromContent(content: unknown): WireImage[] {
  if (!Array.isArray(content)) return [];
  const out: WireImage[] = [];
  for (const block of content) {
    if (!block || typeof block !== "object") continue;
    const typed = block as { type?: string; data?: unknown; mimeType?: unknown };
    if (typed.type === "image" && typeof typed.data === "string" && typeof typed.mimeType === "string") {
      out.push({ data: typed.data, mime: typed.mimeType });
    }
  }
  return out;
}

export function deterministicTranscriptEventId(
  sessionId: string,
  kind: TranscriptEvent["kind"],
  stableKey: string,
): string {
  return `server:${sessionId}:${kind}:${stableKey}`;
}

function dedupeTranscriptEvents(events: readonly TranscriptEvent[]): TranscriptEvent[] {
  const seen = new Set<string>();
  const out: TranscriptEvent[] = [];
  for (const event of events) {
    if (seen.has(event.eventId)) continue;
    seen.add(event.eventId);
    out.push(event);
  }
  return out;
}

function toWireUsage(usage: Usage | undefined): Usage | undefined {
  if (!usage) return undefined;
  return {
    input_tokens: usage.input_tokens ?? 0,
    output_tokens: usage.output_tokens ?? 0,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
