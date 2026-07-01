import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
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

interface GeneratedProtocolModule {
  readonly CLIENT_MESSAGE_TYPES?: readonly string[];
  readonly SERVER_MESSAGE_TYPES?: readonly string[];
  readonly SESSION_HISTORY_EVENT_TYPES?: readonly string[];
  isClientMessage?(value: unknown): boolean;
  isServerMessage?(value: unknown): boolean;
  isSessionHistoryEvent?(value: unknown): boolean;
}

async function importGeneratedProtocol(output: string): Promise<GeneratedProtocolModule> {
  const root = await mkdtemp(join(tmpdir(), "remote-pi-generated-protocol-import-"));
  const file = join(root, "protocol.generated.ts");
  await writeFile(file, output, "utf8");
  return import(`${pathToFileURL(file).href}?cache=${Date.now()}`) as Promise<GeneratedProtocolModule>;
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
  assert.match(first, /export const CLIENT_MESSAGE_TYPES = \[/);
  assert.match(first, /export const appPiClientTypes = CLIENT_MESSAGE_TYPES;/);
  assert.match(first, /export function isClientMessage\(value: unknown\): value is ClientMessage/);

  const generated = await importGeneratedProtocol(first);
  assert.deepEqual(generated.CLIENT_MESSAGE_TYPES, ["pong", "error"]);
  assert.equal(generated.isClientMessage?.({ type: "pong", in_reply_to: "reply-1" }), true);
  assert.equal(generated.isClientMessage?.({ type: "error", message: "bad", code: "invalid_message" }), true);
  assert.equal(generated.isClientMessage?.({ in_reply_to: "reply-1" }), false);
  assert.equal(generated.isClientMessage?.({ type: "pong" }), false);
  assert.equal(generated.isClientMessage?.({ type: "error", message: "bad", code: "future_code" }), false);
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
  assert.match(output, /export const SERVER_MESSAGE_TYPES = \[/);
  assert.match(output, /"user_message",\n  "queued_message_state",/);
  assert.match(output, /"compaction",\n  "tool_request",/);
  assert.match(output, /"action_ok",\n  "action_error",\n  "models_list",/);
  assert.match(output, /export const SESSION_HISTORY_EVENT_TYPES = \[/);
  assert.match(output, /export function isServerMessage\(value: unknown\): value is ServerMessage/);
  assert.doesNotMatch(output, /ServerMessagePairOk|ClientMessageUserMessage/);
});

test("real Remote Pi generated validators accept current app/Pi variants and reject malformed objects", async () => {
  const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
  const manifest = await loadRemotePiManifest(join(repoRoot, "protocol", "schema", "manifest.json"));
  const ir = await buildRemotePiIr(manifest, { profile: "compat" });
  const generated = await importGeneratedProtocol(renderTypeScriptProtocol(ir));

  assert.deepEqual(generated.SERVER_MESSAGE_TYPES, [
    "pair_ok",
    "pair_error",
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
    "pong",
    "bye",
    "session_history",
    "action_ok",
    "action_error",
    "models_list",
  ]);
  assert.deepEqual(generated.SESSION_HISTORY_EVENT_TYPES, ["user_input", "tool_request", "tool_result", "agent_message", "compaction"]);

  const image = { data: "base64", mime: "image/jpeg" };
  const usage = { input_tokens: 1, output_tokens: 2 };
  const model = { id: "model-1", name: "Model One", provider: "provider", reasoning: true, context_window: 200000, vision: true };
  const clientFixtures: unknown[] = [
    { type: "pair_request", id: "c1", token: "token", device_name: "phone" },
    { type: "user_message", id: "c2", text: "hello", images: [image], streaming_behavior: "steer" },
    { type: "queued_message_set", id: "c3", text: "next" },
    { type: "queued_message_clear", id: "c4" },
    { type: "approve_tool", id: "c5", tool_call_id: "tool-1", decision: "allow" },
    { type: "cancel", id: "c6", target_id: "turn-1" },
    { type: "ping", id: "c7" },
    { type: "session_sync", id: "c8", limit: 25 },
    { type: "session_new", id: "c9" },
    { type: "session_compact", id: "c10" },
    { type: "model_set", id: "c11", provider: "openai", model_id: "gpt" },
    { type: "thinking_set", id: "c12", level: "high" },
    { type: "list_models", id: "c13" },
  ];
  for (const fixture of clientFixtures) assert.equal(generated.isClientMessage?.(fixture), true, JSON.stringify(fixture));

  const historyEvents = [
    { ts: 1, type: "user_input", id: "h1", text: "hi", images: [image] },
    { ts: 2, type: "tool_request", tool_call_id: "tool-1", tool: "read", args: { path: "README.md" } },
    { ts: 3, type: "tool_result", tool_call_id: "tool-1", result: ["ok"] },
    { ts: 4, type: "agent_message", in_reply_to: "h1", text: "done", usage },
    { ts: 5, type: "compaction", summary: "short", tokens_before: 100 },
  ];
  for (const event of historyEvents) assert.equal(generated.isSessionHistoryEvent?.(event), true, JSON.stringify(event));

  const serverFixtures: unknown[] = [
    { type: "pair_ok", in_reply_to: "c1", session_name: "main", session_started_at: 0, room_id: "room-1", harness: { name: "pi", version: "1" }, hostname: "host" },
    { type: "pair_error", in_reply_to: "c1", code: "token_expired", message: "expired" },
    { type: "user_input", id: "s1", text: "input", images: [image], streaming_behavior: "steer" },
    { type: "user_message", id: "s2", text: "echo" },
    { type: "queued_message_state" },
    { type: "agent_chunk", in_reply_to: "s1", delta: "d" },
    { type: "agent_done", in_reply_to: "s1", usage },
    { type: "agent_message", in_reply_to: "s1", text: "answer", usage },
    { type: "compaction", summary: "short", tokens_before: 100, ts: 10 },
    { type: "tool_request", tool_call_id: "tool-1", tool: "read", args: { path: "README.md" } },
    { type: "tool_result", tool_call_id: "tool-1", result: { ok: true } },
    { type: "error", code: "future_code", message: "future codes stay open" },
    { type: "cancelled", in_reply_to: "s1", target_id: "turn-1" },
    { type: "pong", in_reply_to: "ping-1" },
    { type: "bye", reason: "shutdown" },
    { type: "session_history", in_reply_to: "sync-1", session_started_at: 0, events: historyEvents, eos: true, truncated: false },
    { type: "action_ok", in_reply_to: "action-1", action: "session_new" },
    { type: "action_error", in_reply_to: "action-2", action: "model_set", error: "no model" },
    { type: "models_list", in_reply_to: "models-1", models: [model], current: model },
  ];
  for (const fixture of serverFixtures) assert.equal(generated.isServerMessage?.(fixture), true, JSON.stringify(fixture));

  assert.equal(generated.isClientMessage?.({ id: "missing-type" }), false);
  assert.equal(generated.isClientMessage?.({ type: "model_set", id: "bad", provider: 1, model_id: "gpt" }), false);
  assert.equal(generated.isServerMessage?.({ type: "models_list", in_reply_to: "bad", models: [{ id: "missing-required-model-fields" }] }), false);
  assert.equal(generated.isServerMessage?.({ type: "tool_request", tool_call_id: "tool-1", tool: "read" }), false);
  assert.equal(generated.isSessionHistoryEvent?.({ type: "compaction", ts: 1, summary: "bad", tokens_before: "many" }), false);
  assert.equal(generated.isServerMessage?.({ type: "future_type" }), false);
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
