import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { DecodeError, decodeClient, decodeServer, encodeClient } from "./codec.js";
import {
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
} from "./generated/protocol.generated.js";

const fixtureDir = fileURLToPath(
  new URL("../../../.orchestration/contracts/fixtures", import.meta.url),
);

const SERVER_TYPES = new Set<string>(SERVER_MESSAGE_TYPES);
const CLIENT_TYPES = new Set<string>(CLIENT_MESSAGE_TYPES);
const FILE_TYPE_ALIASES: Record<string, string> = {
  "agent_stream.jsonl": "agent_chunk",
};
function fixtureType(file: string): string {
  return FILE_TYPE_ALIASES[file] ?? file.replace(/\.jsonl$/, "");
}
function isServerFixture(file: string): boolean {
  return SERVER_TYPES.has(fixtureType(file));
}
function isClientFixture(file: string): boolean {
  return CLIENT_TYPES.has(fixtureType(file));
}

function captureDecodeError(fn: () => unknown): DecodeError {
  let caught: unknown;
  try {
    fn();
  } catch (e) {
    caught = e;
  }
  expect(caught).toBeInstanceOf(DecodeError);
  return caught as DecodeError;
}

describe("fixtures", () => {
  const files = readdirSync(fixtureDir).filter((f) => f.endsWith(".jsonl"));

  test("36 fixture files present", () => {
    expect(files).toHaveLength(36);
  });

  for (const file of files) {
    test(`${file} server decode classification`, () => {
      const lines = readFileSync(`${fixtureDir}/${file}`, "utf8")
        .split("\n")
        .filter(Boolean);

      for (const line of lines) {
        if (isServerFixture(file)) {
          const msg = decodeServer(line);
          expect(SERVER_TYPES.has(msg.type)).toBe(true);
        } else {
          const caught = captureDecodeError(() => decodeServer(line));
          expect(caught.code).toBe("unsupported_type");
        }
      }
    });

    test(`${file} client decode classification`, () => {
      const lines = readFileSync(`${fixtureDir}/${file}`, "utf8")
        .split("\n")
        .filter(Boolean);

      for (const line of lines) {
        if (isClientFixture(file)) {
          const msg = decodeClient(line);
          expect(CLIENT_TYPES.has(msg.type)).toBe(true);
        } else {
          const caught = captureDecodeError(() => decodeClient(line));
          expect(caught.code).toBe("unsupported_type");
        }
      }
    });
  }
});

describe("decodeServer validator-backed compatibility", () => {
  test("accepts drifted schema-valid server variants", () => {
    const messages = [
      { type: "user_message", id: "msg-1", session_id: "session-1", text: "hello" },
      { type: "compaction", session_id: "session-1", summary: "short", tokens_before: 42 },
      { type: "action_ok", session_id: "session-1", in_reply_to: "action-1", action: "session_compact" },
      { type: "action_error", session_id: "session-1", in_reply_to: "action-2", action: "model_set", error: "no model" },
      {
        type: "models_list",
        session_id: "session-1",
        in_reply_to: "models-1",
        models: [{ id: "gpt-test", name: "GPT Test", provider: "openai", reasoning: true, context_window: 128000, vision: true }],
        current: { id: "gpt-test", name: "GPT Test", provider: "openai", reasoning: true, context_window: 128000, vision: true },
      },
    ];

    for (const message of messages) {
      expect(decodeServer(JSON.stringify(message))).toEqual(message);
    }
  });

  test("does not require compatibility-profile session_id", () => {
    expect(decodeServer(JSON.stringify({ type: "action_ok", in_reply_to: "action-1", action: "session_compact" }))).toEqual({
      type: "action_ok",
      in_reply_to: "action-1",
      action: "session_compact",
    });
  });
});

describe("decodeClient validator-backed compatibility", () => {
  test("accepts current app-origin messages", () => {
    const messages = [
      { type: "pair_request", id: "pair-1", token: "token", device_name: "phone" },
      { type: "user_message", id: "msg-1", session_id: "session-1", text: "hello", streaming_behavior: "steer" },
      { type: "session_sync", id: "sync-1", session_id: "session-1", limit: 25 },
      { type: "model_set", id: "model-1", session_id: "session-1", provider: "openai", model_id: "gpt" },
      { type: "thinking_set", id: "thinking-1", session_id: "session-1", level: "high" },
      { type: "list_models", id: "models-1", session_id: "session-1" },
    ];

    for (const message of messages) {
      expect(decodeClient(JSON.stringify(message))).toEqual(message);
    }
  });

  test("rejects malformed known app-origin messages", () => {
    const caught = captureDecodeError(() => decodeClient('{"type":"model_set","id":"bad","provider":1,"model_id":"gpt"}'));
    expect(caught.code).toBe("invalid_message");
    expect(caught.message).toMatch(/invalid client message: model_set/);
  });
});

describe("rejects junk", () => {
  test("invalid JSON → DecodeError invalid_message", () => {
    const err = captureDecodeError(() => decodeServer("not json {{{"));
    expect(err.code).toBe("invalid_message");
  });

  test("missing type field → DecodeError invalid_message", () => {
    const err = captureDecodeError(() => decodeServer('{"foo":1}'));
    expect(err.code).toBe("invalid_message");
    expect(err.message).toMatch(/missing 'type'/);
  });

  test("unknown type → DecodeError unsupported_type", () => {
    const err = captureDecodeError(() => decodeServer('{"type":"made_up"}'));
    expect(err.code).toBe("unsupported_type");
    expect(err.message).toMatch(/unknown type/);
  });

  test("malformed known server messages → DecodeError invalid_message", () => {
    const err = captureDecodeError(() => decodeServer('{"type":"agent_chunk","in_reply_to":"r1"}'));
    expect(err.code).toBe("invalid_message");
    expect(err.message).toMatch(/invalid server message: agent_chunk/);
  });
});

describe("encodeClient roundtrip", () => {
  test("ping", () => {
    const msg = { type: "ping" as const, id: "018f9c2a" };
    const encoded = encodeClient(msg);
    expect(encoded.endsWith("\n")).toBe(true);
    expect(JSON.parse(encoded.trim())).toEqual(msg);
  });

  test("user_message", () => {
    const msg = { type: "user_message" as const, id: "018f9c2a", session_id: "session-1", text: "hello" };
    expect(JSON.parse(encodeClient(msg).trim())).toEqual(msg);
  });

  test("user_message with steer streaming behavior", () => {
    const msg = {
      type: "user_message" as const,
      id: "018f9c2a",
      session_id: "session-1",
      text: "refine this",
      streaming_behavior: "steer" as const,
    };
    expect(JSON.parse(encodeClient(msg).trim())).toEqual(msg);
  });
});
