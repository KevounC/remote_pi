import type { ClientMessage } from "../protocol/types.js";
import { isSessionScopedClientType } from "../protocol/session_scope.js";

export type SessionGateResult =
  | { ok: true }
  | {
      ok: false;
      code: "session_mismatch";
      message: string;
      currentSessionId: string;
      receivedSessionId: string | null;
    };

export function validateClientSession(
  msg: ClientMessage,
  currentSessionId: string,
): SessionGateResult {
  if (!isSessionScopedClientType(msg.type)) return { ok: true };

  const receivedSessionId = sessionIdFromClientMessage(msg);
  if (receivedSessionId !== currentSessionId) {
    return {
      ok: false,
      code: "session_mismatch",
      message: receivedSessionId === null || receivedSessionId.length === 0
        ? "Session-scoped command is missing session_id"
        : "Session-scoped command targets a stale session",
      currentSessionId,
      receivedSessionId,
    };
  }

  return { ok: true };
}

function sessionIdFromClientMessage(msg: ClientMessage): string | null {
  const candidate = msg as ClientMessage & { session_id?: unknown };
  return typeof candidate.session_id === "string" ? candidate.session_id : null;
}
