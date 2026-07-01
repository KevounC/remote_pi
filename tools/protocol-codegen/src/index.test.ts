import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";

import {
  buildRemotePiIr,
  emitTypeScriptProtocol,
  loadRemotePiManifest,
  renderTypeScriptProtocol,
} from "./index.ts";

async function writeJson(path: string, value: unknown): Promise<void> {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function writeFixtureProtocol(schema: unknown): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "remote-pi-protocol-codegen-"));
  const schemaRoot = join(root, "schema");
  await writeFile(join(root, ".keep"), "", "utf8");
  await mkdir(schemaRoot, { recursive: true });
  await writeJson(join(schemaRoot, "manifest.json"), {
    schemaVersion: 1,
    source: "json-schema-2020-12",
    discriminator: "type",
    profiles: ["compat"],
    families: [
      {
        id: "appPiClient",
        transport: "relay-jsonl",
        schema: "schema/minimal.schema.json",
        description: "Minimal test family",
      },
    ],
  });
  await writeJson(join(schemaRoot, "minimal.schema.json"), schema);
  return root;
}

test("minimal manifest schema emits deterministic TypeScript output", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [{ $ref: "#/$defs/pong" }, { $ref: "#/$defs/error" }],
    $defs: {
      pong: {
        type: "object",
        required: ["type", "in_reply_to"],
        properties: {
          type: { const: "pong" },
          in_reply_to: { type: "string" },
        },
        additionalProperties: false,
      },
      error: {
        type: "object",
        required: ["type", "message"],
        properties: {
          type: { const: "error" },
          message: { type: "string" },
          code: { enum: ["invalid_message", "internal_error"] },
        },
        additionalProperties: false,
      },
    },
  });

  const manifest = await loadRemotePiManifest(join(protocolRoot, "schema", "manifest.json"));
  const ir = await buildRemotePiIr(manifest, { profile: "compat" });
  const first = renderTypeScriptProtocol(ir);
  const second = renderTypeScriptProtocol(ir);

  assert.equal(second, first);
  assert.equal(
    first,
    `// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
/* eslint-disable */

export type JsonValue = null | boolean | number | string | JsonValue[] | { readonly [key: string]: JsonValue };

export const protocolManifest = {
  schemaVersion: 1,
  source: "json-schema-2020-12",
  profile: "compat",
  families: [
    { id: "appPiClient", union: "ClientMessage", transport: "relay-jsonl" },
  ],
} as const;

export const appPiClientTypes = [
  "pong",
  "error",
] as const;
export type AppPiClientType = (typeof appPiClientTypes)[number];

export interface Pong {
  readonly type: "pong";
  readonly in_reply_to: string;
}

export interface ErrorMessage {
  readonly type: "error";
  readonly message: string;
  readonly code?: "invalid_message" | "internal_error";
}

export type ClientMessage =
  | Pong
  | ErrorMessage;
`,
  );
});

test("real Remote Pi schema emits generated app/Pi unions and shared value types", async () => {
  const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
  const manifest = await loadRemotePiManifest(join(repoRoot, "protocol", "schema", "manifest.json"));
  const ir = await buildRemotePiIr(manifest, { profile: "compat" });
  const output = renderTypeScriptProtocol(ir);

  assert.match(output, /export interface WireImage \{\n  readonly data: string;\n  readonly mime: string;\n\}/);
  assert.match(output, /export interface Usage \{\n  readonly input_tokens: number;\n  readonly output_tokens: number;\n\}/);
  assert.match(output, /export interface WireModel \{[\s\S]*readonly vision\?: boolean;[\s\S]*\}/);
  assert.match(output, /export type ThinkingLevel = "off" \| "minimal" \| "low" \| "medium" \| "high" \| "xhigh";/);
  assert.match(output, /export type StreamingBehavior = "steer";/);
  assert.match(output, /export type ByeReason = "peer_stop" \| "session_replaced" \| "shutdown";/);
  assert.match(output, /export type PairErrorCode = "token_expired" \| "token_consumed" \| "token_unknown" \| "internal_error";/);
  assert.match(output, /export type KnownErrorCode = "tool_approval_required"[\s\S]*"session_mismatch";/);
  assert.match(output, /export type ErrorCode = KnownErrorCode \| \(string & \{\}\);/);
  assert.match(output, /export type SessionHistoryEvent =\n  \| HistoryUserInput\n  \| HistoryToolRequest\n  \| HistoryToolResult\n  \| HistoryAgentMessage\n  \| HistoryCompaction;/);

  assert.match(output, /export interface PairOk \{[\s\S]*readonly session_id\?: string;[\s\S]*readonly room_id: string;[\s\S]*\}/);
  assert.match(output, /readonly images\?: Array<WireImage>;/);
  assert.match(output, /readonly usage\?: Usage;/);
  assert.match(output, /readonly events: Array<SessionHistoryEvent>;/);
  assert.match(output, /readonly level: ThinkingLevel;/);
  assert.match(output, /readonly reason: ByeReason;/);
  assert.match(output, /readonly code: PairErrorCode;/);
  assert.match(output, /readonly code: ErrorCode;/);
  assert.match(output, /readonly models: Array<WireModel>;/);

  assert.match(output, /export type ClientMessage =\n  \| PairRequest\n  \| UserMessage\n  \| QueuedMessageSet\n  \| QueuedMessageClear\n  \| ApproveTool\n  \| Cancel\n  \| Ping\n  \| SessionSync\n  \| SessionNew\n  \| SessionCompact\n  \| ModelSet\n  \| ThinkingSet\n  \| ListModels;/);
  assert.match(output, /export type ServerMessage =\n  \| PairOk\n  \| PairError\n  \| UserInput\n  \| UserMessage\n  \| QueuedMessageState\n  \| AgentChunk\n  \| AgentDone\n  \| AgentMessage\n  \| Compaction\n  \| ToolRequest\n  \| ToolResult\n  \| ErrorMessage\n  \| Cancelled\n  \| Pong\n  \| Bye\n  \| SessionHistory\n  \| ActionOk\n  \| ActionError\n  \| ModelsList;/);
  assert.doesNotMatch(output, /ServerMessagePairOk|ClientMessageUserMessage/);
});

test("placeholder schema families fail with a clear diagnostic", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [],
    $defs: {},
    "x-remote-pi": { family: "appPiClient" },
  });
  const manifest = await loadRemotePiManifest(join(protocolRoot, "schema", "manifest.json"));
  await assert.rejects(
    () => buildRemotePiIr(manifest, { profile: "compat" }),
    /schema family placeholder: appPiClient \(schema\/minimal\.schema\.json\)/,
  );
});

test("emitTypeScriptProtocol check detects stale generated output", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [{ $ref: "#/$defs/ping" }],
    $defs: {
      ping: {
        type: "object",
        required: ["type", "id"],
        properties: { type: { const: "ping" }, id: { type: "string" } },
        additionalProperties: false,
      },
    },
  });
  const manifest = await loadRemotePiManifest(join(protocolRoot, "schema", "manifest.json"));
  const ir = await buildRemotePiIr(manifest, { profile: "compat" });
  const outFile = join(protocolRoot, "generated", "protocol.generated.ts");

  await emitTypeScriptProtocol(ir, { outFile });
  await emitTypeScriptProtocol(ir, { outFile, check: true });
  await writeFile(outFile, "stale\n", "utf8");
  await assert.rejects(
    () => emitTypeScriptProtocol(ir, { outFile, check: true }),
    /Generated TypeScript protocol is stale/,
  );
});
