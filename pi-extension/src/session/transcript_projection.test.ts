import { describe, expect, test } from "vitest";
import type { TranscriptEvent } from "./transcript_event.js";
import {
  deterministicTranscriptEventId,
  mapLegacyAgentMessagesToTranscriptEvents,
  projectSessionHistory,
  stringifyToolResult,
} from "./transcript_projection.js";

const sessionId = "sess-a";

function user(clientMessageId: string, text: string, ts: number): TranscriptEvent {
  return {
    kind: "user_confirmed",
    eventId: deterministicTranscriptEventId(sessionId, "user_confirmed", clientMessageId),
    sessionId,
    ts,
    clientMessageId,
    text,
  };
}

function assistant(replyTo: string, text: string, ts: number): TranscriptEvent {
  return {
    kind: "assistant_committed",
    eventId: deterministicTranscriptEventId(sessionId, "assistant_committed", `msg-${ts}`),
    sessionId,
    ts,
    messageId: `msg-${ts}`,
    replyTo,
    text,
  };
}

describe("transcript session_history projection", () => {
  test("applies limit/truncated after session filtering", () => {
    const events: TranscriptEvent[] = [
      user("u1", "one", 1),
      { ...user("foreign", "skip", 2), sessionId: "other" },
      assistant("u1", "two", 3),
      user("u2", "three", 4),
    ];

    const projection = projectSessionHistory({ sessionId, events, limit: 2 });

    expect(projection.truncated).toBe(true);
    expect(projection.events).toEqual([
      expect.objectContaining({ type: "agent_message", text: "two", ts: 3 }),
      expect.objectContaining({ type: "user_input", text: "three", ts: 4 }),
    ]);
  });

  test("replays image user messages without adding images to text-only messages", () => {
    const projection = projectSessionHistory({
      sessionId,
      limit: 10,
      events: [
        {
          kind: "user_confirmed",
          eventId: deterministicTranscriptEventId(sessionId, "user_confirmed", "img-1"),
          sessionId,
          ts: 10,
          clientMessageId: "img-1",
          text: "what is this?",
          images: [{ data: "QUJD", mime: "image/jpeg" }],
        },
        user("txt-1", "plain", 11),
      ],
    });

    expect(projection.events[0]).toMatchObject({
      type: "user_input",
      id: "img-1",
      text: "what is this?",
      images: [{ data: "QUJD", mime: "image/jpeg" }],
    });
    expect(projection.events[1]).toMatchObject({ type: "user_input", id: "txt-1", text: "plain" });
    expect(projection.events[1]).not.toHaveProperty("images");
  });

  test("replays compaction markers", () => {
    const projection = projectSessionHistory({
      sessionId,
      limit: 10,
      events: [{
        kind: "compaction_recorded",
        eventId: deterministicTranscriptEventId(sessionId, "compaction_recorded", "1700"),
        sessionId,
        ts: 1700,
        summary: "summarised 10 turns",
        tokensBefore: 12345,
      }],
    });

    expect(projection.events).toEqual([
      { ts: 1700, type: "compaction", summary: "summarised 10 turns", tokens_before: 12345 },
    ]);
  });

  test("dedupes deterministic event ids for replay idempotence", () => {
    const event = user("u1", "hello", 1);
    const projection = projectSessionHistory({ sessionId, limit: 10, events: [event, event] });

    expect(projection.events).toHaveLength(1);
    expect(projection.events[0]).toMatchObject({ type: "user_input", id: "u1", text: "hello" });
  });

  test("legacy SDK-message adapter produces transcript events before history projection", () => {
    const transcriptEvents = mapLegacyAgentMessagesToTranscriptEvents({
      sessionId,
      messages: [
        { role: "user", content: [{ type: "image", data: "QUJD", mimeType: "image/jpeg" }, { type: "text", text: "describe" }], timestamp: 100 },
        { role: "assistant", content: [{ type: "text", text: "running" }, { type: "toolCall", id: "tc_1", name: "bash", arguments: { command: "ls" } }], timestamp: 200, usage: { input: 7, output: 3 } },
        { role: "toolResult", toolCallId: "tc_1", isError: false, content: [{ type: "text", text: "file" }], timestamp: 300 },
      ],
    });

    expect(transcriptEvents.map((event) => event.kind)).toEqual([
      "user_confirmed",
      "assistant_committed",
      "tool_requested",
      "tool_finished",
    ]);

    const projection = projectSessionHistory({ sessionId, events: transcriptEvents, limit: 10 });
    expect(projection.events).toEqual([
      expect.objectContaining({ type: "user_input", id: "sync_100", text: "describe", images: [{ data: "QUJD", mime: "image/jpeg" }] }),
      expect.objectContaining({ type: "agent_message", in_reply_to: "sync_100", text: "running", usage: { input_tokens: 7, output_tokens: 3 } }),
      expect.objectContaining({ type: "tool_request", tool_call_id: "tc_1", tool: "bash", args: { command: "ls" } }),
      expect.objectContaining({ type: "tool_result", tool_call_id: "tc_1", result: "file" }),
    ]);
  });

  test("tool result stringification is shared by live and replay paths", () => {
    expect(stringifyToolResult({ content: [{ type: "text", text: "ping failed" }], details: {} }))
      .toBe("ping failed");
    expect(stringifyToolResult({ code: 1 })).toBe('{"code":1}');
  });
});
