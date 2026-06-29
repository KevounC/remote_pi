import { describe, expect, test } from "vitest";
import {
  SESSION_SCOPED_CLIENT_TYPES,
  SESSION_SCOPED_SERVER_TYPES,
  SERVER_MESSAGE_TYPES,
  isServerMessageType,
  isSessionScopedClientType,
  isSessionScopedServerType,
} from "./session_scope.js";

describe("session-scoped protocol registry", () => {
  test("lists every server push that must carry session_id", () => {
    expect(SESSION_SCOPED_SERVER_TYPES).toEqual([
      "user_input",
      "user_message",
      "queued_message_state",
      "agent_chunk",
      "agent_done",
      "agent_message",
      "compaction",
      "tool_request",
      "tool_result",
      "error",
      "cancelled",
      "session_history",
    ]);
  });

  test("lists every client command scoped to an active session", () => {
    expect(SESSION_SCOPED_CLIENT_TYPES).toEqual([
      "user_message",
      "queued_message_set",
      "queued_message_clear",
      "approve_tool",
      "cancel",
      "session_sync",
      "session_new",
      "session_compact",
      "model_set",
      "thinking_set",
      "list_models",
    ]);
  });

  test("guards codec/server registry drift", () => {
    expect(isServerMessageType("models_list")).toBe(true);
    expect(isServerMessageType("action_ok")).toBe(true);
    expect(isServerMessageType("compaction")).toBe(true);
    expect(SERVER_MESSAGE_TYPES).toContain("user_message");
    expect(isServerMessageType("future_type")).toBe(false);
  });

  test("type predicates distinguish session-scoped families", () => {
    expect(isSessionScopedServerType("session_history")).toBe(true);
    expect(isSessionScopedServerType("pair_ok")).toBe(false);
    expect(isSessionScopedClientType("session_sync")).toBe(true);
    expect(isSessionScopedClientType("pair_request")).toBe(false);
    expect(isSessionScopedClientType("ping")).toBe(false);
  });
});
