import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
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

export interface ClientMessagePong {
  readonly type: "pong";
  readonly in_reply_to: string;
}

export interface ClientMessageError {
  readonly type: "error";
  readonly message: string;
  readonly code?: "invalid_message" | "internal_error";
}

export type ClientMessage =
  | ClientMessagePong
  | ClientMessageError;
`,
  );
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
