import { isServerMessageType, isSessionScopedServerType } from "./session_scope.js";
import type { ClientMessage, ServerMessage } from "./types.js";

export class DecodeError extends Error {
  constructor(
    public readonly code: "invalid_message" | "unsupported_type",
    message: string,
  ) {
    super(message);
    this.name = "DecodeError";
  }
}

export function encodeClient(msg: ClientMessage): string {
  return JSON.stringify(msg) + "\n";
}

export function decodeServer(line: string): ServerMessage {
  let obj: unknown;
  try {
    obj = JSON.parse(line.trim());
  } catch (e) {
    throw new DecodeError("invalid_message", `not JSON: ${(e as Error).message}`);
  }
  if (
    !obj ||
    typeof obj !== "object" ||
    typeof (obj as Record<string, unknown>).type !== "string"
  ) {
    throw new DecodeError("invalid_message", "missing 'type'");
  }
  const t = (obj as Record<string, unknown>).type as string;
  if (!isServerMessageType(t)) {
    throw new DecodeError("unsupported_type", `unknown type: ${t}`);
  }
  if (isSessionScopedServerType(t)) {
    const sessionId = (obj as Record<string, unknown>).session_id;
    if (typeof sessionId !== "string" || sessionId.length === 0) {
      throw new DecodeError("invalid_message", `missing 'session_id' for ${t}`);
    }
  }
  return obj as ServerMessage;
}
