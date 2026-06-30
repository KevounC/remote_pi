import type { StreamingBehavior, Usage, WireImage } from "../protocol/types.js";

export type TranscriptEvent =
  | {
      kind: "user_submitted";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      clientMessageId: string;
      text: string;
      images?: WireImage[];
    }
  | {
      kind: "user_confirmed";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      clientMessageId: string;
      text: string;
      images?: WireImage[];
      streamingBehavior?: StreamingBehavior;
    }
  | {
      kind: "user_failed";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      clientMessageId: string;
      code: string;
      message: string;
    }
  | {
      kind: "assistant_delta";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      replyTo: string;
      delta: string;
    }
  | {
      kind: "assistant_committed";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      messageId: string;
      replyTo: string;
      text: string;
      usage?: Usage;
    }
  | {
      kind: "assistant_done";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      replyTo: string;
      usage?: Usage;
    }
  | {
      kind: "provider_error";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      replyTo?: string;
      code: string;
      message: string;
    }
  | {
      kind: "tool_requested";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      toolCallId: string;
      tool: string;
      args: Record<string, unknown>;
    }
  | {
      kind: "tool_finished";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      toolCallId: string;
      result?: unknown;
      error?: string;
    }
  | {
      kind: "compaction_recorded";
      eventId: string;
      sessionId: string;
      ts: number;
      turnId?: string;
      summary: string;
      tokensBefore?: number;
    };

export type TranscriptTurnStatus = "idle" | "working" | "streaming" | "error";

export interface TranscriptTurnView {
  status: TranscriptTurnStatus;
  replyTo?: string;
  error?: string;
}

export interface TranscriptProjection<TMessage = unknown> {
  messages: TMessage[];
  streaming?: { replyTo: string; text: string };
  turn: TranscriptTurnView;
}
