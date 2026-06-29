import { describe, expect, test } from "vitest";
import { RemoteSessionIssuer, resolveRemoteSessionId, uuid7 } from "./remote_session.js";

function ctx(id: unknown) {
  return { sessionManager: { getSessionId: () => id } };
}

describe("remote session identity", () => {
  test("resolves the Pi SDK session id when available", () => {
    expect(resolveRemoteSessionId(ctx("sdk-session-1"))).toBe("sdk-session-1");
  });

  test("falls back to UUIDv7 for legacy/test seams", () => {
    const id = resolveRemoteSessionId(ctx(undefined));
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  test("UUIDv7 helper emits version 7 ids", () => {
    expect(uuid7().split("-")[2]?.startsWith("7")).toBe(true);
  });

  test("issuer preserves id across reconnect-style current reads and rotates on replacement capture", () => {
    const issuer = new RemoteSessionIssuer();
    expect(issuer.capture(ctx("session-a"))).toBe("session-a");
    expect(issuer.currentOrCapture(ctx("session-a"))).toBe("session-a");
    expect(issuer.capture(ctx("session-b"))).toBe("session-b");
    expect(issuer.current()).toBe("session-b");
  });
});
