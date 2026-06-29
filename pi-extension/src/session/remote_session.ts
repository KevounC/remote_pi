import { randomBytes } from "node:crypto";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { RemoteSessionId } from "../protocol/session_scope.js";
import type { ThinkingLevel } from "../protocol/types.js";

export type { RemoteSessionId };

export interface RemoteSession {
  sessionId: RemoteSessionId;
  peerId: string;
  roomId: string;
  cwd: string;
  name: string;
  startedAt: number;
  model?: string;
  thinking?: ThinkingLevel;
  working: boolean;
}

type SessionIdContext = Pick<ExtensionContext, "sessionManager">;

function hasSessionManager(value: unknown): value is SessionIdContext {
  return (
    typeof value === "object" &&
    value !== null &&
    "sessionManager" in value &&
    typeof (value as { sessionManager?: { getSessionId?: unknown } }).sessionManager?.getSessionId === "function"
  );
}

export function uuid7(): string {
  const bytes = randomBytes(16);
  const now = BigInt(Date.now());
  bytes[0] = Number((now >> 40n) & 0xffn);
  bytes[1] = Number((now >> 32n) & 0xffn);
  bytes[2] = Number((now >> 24n) & 0xffn);
  bytes[3] = Number((now >> 16n) & 0xffn);
  bytes[4] = Number((now >> 8n) & 0xffn);
  bytes[5] = Number(now & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function resolveRemoteSessionId(ctx: unknown): RemoteSessionId {
  if (hasSessionManager(ctx)) {
    const sdkId = ctx.sessionManager.getSessionId();
    if (typeof sdkId === "string" && sdkId.length > 0) return sdkId;
  }
  return uuid7();
}

export class RemoteSessionIssuer {
  private currentId: RemoteSessionId | null = null;

  current(): RemoteSessionId | null {
    return this.currentId;
  }

  capture(ctx: unknown): RemoteSessionId {
    const next = resolveRemoteSessionId(ctx);
    this.currentId = next;
    return next;
  }

  currentOrCapture(ctx: unknown): RemoteSessionId {
    return this.currentId ?? this.capture(ctx);
  }

  clear(): void {
    this.currentId = null;
  }
}
