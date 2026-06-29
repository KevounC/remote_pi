import { describe, expect, test } from "vitest";
import type { ClientMessage } from "../protocol/types.js";
import { validateClientSession } from "./session_gate.js";

describe("validateClientSession", () => {
  test("accepts non-session-scoped messages", () => {
    const msg: ClientMessage = { type: "ping", id: "ping-1" };

    expect(validateClientSession(msg, "session-a")).toEqual({ ok: true });
  });

  test("accepts matching session-scoped commands", () => {
    const msg: ClientMessage = {
      type: "session_sync",
      id: "sync-1",
      session_id: "session-a",
    };

    expect(validateClientSession(msg, "session-a")).toEqual({ ok: true });
  });

  test("rejects missing or stale session ids", () => {
    const stale: ClientMessage = {
      type: "cancel",
      id: "cancel-1",
      session_id: "session-b",
      target_id: "turn-1",
    };
    const missing = {
      type: "session_compact",
      id: "compact-1",
    } as ClientMessage;

    expect(validateClientSession(stale, "session-a")).toMatchObject({
      ok: false,
      code: "session_mismatch",
      currentSessionId: "session-a",
      receivedSessionId: "session-b",
    });
    expect(validateClientSession(missing, "session-a")).toMatchObject({
      ok: false,
      code: "session_mismatch",
      currentSessionId: "session-a",
      receivedSessionId: null,
    });
  });
});
