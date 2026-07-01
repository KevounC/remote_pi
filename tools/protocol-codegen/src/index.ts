import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";

export interface RemotePiManifestFamily {
  id: string;
  transport: string;
  schema: string;
  description?: string;
}

export interface RemotePiManifest {
  schemaVersion?: number;
  source?: string;
  discriminator?: string;
  profiles?: string[];
  families: RemotePiManifestFamily[];
  manifestPath?: string;
  protocolRoot?: string;
}

export interface BuildRemotePiIrOptions {
  profile?: string;
  manifestPath?: string;
  protocolRoot?: string;
}

export interface RemotePiIrField {
  name: string;
  required: boolean;
  tsType: string;
}

export interface RemotePiIrVariant {
  type: string;
  discriminator: string;
  interfaceName: string;
  schemaRef: string;
  fields: RemotePiIrField[];
}

export interface RemotePiIrFamily {
  id: string;
  transport: string;
  schemaPath: string;
  unionName: string;
  variants: RemotePiIrVariant[];
}

export interface RemotePiIr {
  schemaVersion: number;
  source: string;
  profile: string;
  families: RemotePiIrFamily[];
}

export interface EmitTypeScriptProtocolOptions {
  outFile?: string;
  check?: boolean;
}

type JsonObject = Record<string, unknown>;

interface CatalogEntry {
  family: string;
  type: string;
  schemaRef: string;
  discriminator?: string;
}

interface DocumentCache {
  documents: Map<string, JsonObject>;
}

export class ProtocolCodegenError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProtocolCodegenError";
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asObject(value: unknown, label: string): JsonObject {
  if (!isObject(value)) throw new ProtocolCodegenError(`${label} must be an object`);
  return value;
}

function asArray(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) throw new ProtocolCodegenError(`${label} must be an array`);
  return value;
}

async function readJsonFile<T>(path: string): Promise<T> {
  return JSON.parse(await readFile(path, "utf8")) as T;
}

async function readDocument(path: string, cache: DocumentCache): Promise<JsonObject> {
  const absolute = resolve(path);
  const cached = cache.documents.get(absolute);
  if (cached) return cached;
  const document = asObject(await readJsonFile<unknown>(absolute), absolute);
  cache.documents.set(absolute, document);
  return document;
}

function protocolRootForManifestPath(manifestPath: string): string {
  const manifestDir = dirname(resolve(manifestPath));
  return manifestDir.endsWith("schema") ? dirname(manifestDir) : manifestDir;
}

export async function loadRemotePiManifest(manifestPath: string): Promise<RemotePiManifest> {
  const absoluteManifestPath = resolve(manifestPath);
  const manifest = asObject(await readJsonFile<unknown>(absoluteManifestPath), manifestPath);
  const families = asArray(manifest.families, "manifest.families").map((family, index) => {
    const object = asObject(family, `manifest.families[${index}]`);
    if (typeof object.id !== "string" || object.id.length === 0) {
      throw new ProtocolCodegenError(`manifest.families[${index}].id must be a non-empty string`);
    }
    if (typeof object.transport !== "string" || object.transport.length === 0) {
      throw new ProtocolCodegenError(`manifest.families[${index}].transport must be a non-empty string`);
    }
    if (typeof object.schema !== "string" || object.schema.length === 0) {
      throw new ProtocolCodegenError(`manifest.families[${index}].schema must be a non-empty string`);
    }
    return {
      id: object.id,
      transport: object.transport,
      schema: object.schema,
      ...(typeof object.description === "string" ? { description: object.description } : {}),
    };
  });

  return {
    schemaVersion: typeof manifest.schemaVersion === "number" ? manifest.schemaVersion : undefined,
    source: typeof manifest.source === "string" ? manifest.source : undefined,
    discriminator: typeof manifest.discriminator === "string" ? manifest.discriminator : undefined,
    profiles: Array.isArray(manifest.profiles) ? manifest.profiles.map(String) : undefined,
    families,
    manifestPath: absoluteManifestPath,
    protocolRoot: protocolRootForManifestPath(absoluteManifestPath),
  };
}

function decodePointerPart(part: string): string {
  return part.replaceAll("~1", "/").replaceAll("~0", "~");
}

function fragmentLookup(document: JsonObject, fragment: string): unknown {
  if (fragment === "" || fragment === "#") return document;
  const parts = fragment.replace(/^#\/?/, "").split("/").filter(Boolean).map(decodePointerPart);
  let current: unknown = document;
  for (const part of parts) {
    current = asObject(current, `schema fragment ${fragment}`)[part];
  }
  return current;
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

async function resolveSchemaRef(ref: string, contextPath: string, protocolRoot: string, cache: DocumentCache): Promise<{ schema: unknown; path: string; ref: string }> {
  const [refPath = "", rawFragment = ""] = ref.split("#");
  const fragment = rawFragment.length > 0 ? `#${rawFragment}` : "#";
  let path: string;

  if (refPath.length === 0) {
    path = resolve(contextPath);
  } else if (isAbsolute(refPath)) {
    path = refPath;
  } else {
    const candidates = unique([
      resolve(dirname(contextPath), refPath),
      resolve(protocolRoot, refPath),
      resolve(protocolRoot, "schema", refPath),
    ]);
    let lastError: unknown;
    for (const candidate of candidates) {
      try {
        const document = await readDocument(candidate, cache);
        return { schema: fragmentLookup(document, fragment), path: resolve(candidate), ref };
      } catch (error) {
        lastError = error;
      }
    }
    throw new ProtocolCodegenError(
      `Unable to resolve schema ref ${JSON.stringify(ref)} from ${contextPath}: ${lastError instanceof Error ? lastError.message : String(lastError)}`,
    );
  }

  const document = await readDocument(path, cache);
  return { schema: fragmentLookup(document, fragment), path: resolve(path), ref };
}

async function dereferenceSchema(schema: unknown, contextPath: string, protocolRoot: string, cache: DocumentCache): Promise<{ schema: unknown; path: string }> {
  let current = schema;
  let currentPath = contextPath;
  const seen = new Set<string>();
  while (isObject(current) && typeof current.$ref === "string" && Object.keys(current).length === 1) {
    const key = `${currentPath}::${current.$ref}`;
    if (seen.has(key)) throw new ProtocolCodegenError(`Circular schema ref ${key}`);
    seen.add(key);
    const resolved = await resolveSchemaRef(current.$ref, currentPath, protocolRoot, cache);
    current = resolved.schema;
    currentPath = resolved.path;
  }
  return { schema: current, path: currentPath };
}

function placeholderDiagnostic(family: RemotePiManifestFamily): ProtocolCodegenError {
  return new ProtocolCodegenError(
    `schema family placeholder: ${family.id} (${family.schema}) does not define concrete ${"oneOf"} variants with a type/customType discriminator`,
  );
}

function literal(value: unknown): string {
  return JSON.stringify(value);
}

function propertyName(name: string): string {
  return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name) ? name : literal(name);
}

function pascalCase(value: string): string {
  const parts = value.split(/[^A-Za-z0-9]+/).filter(Boolean);
  const text = parts.map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`).join("");
  return text.length > 0 ? text : "Unknown";
}

function lowerCamel(value: string): string {
  const pascal = pascalCase(value);
  return `${pascal.charAt(0).toLowerCase()}${pascal.slice(1)}`;
}

function unionNameForFamily(family: string): string {
  switch (family) {
    case "appPiClient":
      return "ClientMessage";
    case "appPiServer":
      return "ServerMessage";
    case "relayControl":
      return "RelayControlFrame";
    case "crossPc":
      return "CrossPcFrame";
    case "cockpitControl":
      return "CockpitControlFrame";
    default:
      return `${pascalCase(family)}Frame`;
  }
}

function interfaceNameForVariant(unionName: string, type: string): string {
  return `${unionName}${pascalCase(type)}`;
}

function constOrEnumValues(schema: JsonObject): unknown[] | undefined {
  if (Object.hasOwn(schema, "const")) return [schema.const];
  if (Array.isArray(schema.enum)) return schema.enum;
  return undefined;
}

async function tsTypeForSchema(schemaInput: unknown, contextPath: string, protocolRoot: string, cache: DocumentCache, stack: string[]): Promise<string> {
  const { schema, path } = await dereferenceSchema(schemaInput, contextPath, protocolRoot, cache);
  if (schema === true) return "unknown";
  if (schema === false) return "never";
  const object = asObject(schema, "schema type");

  const values = constOrEnumValues(object);
  if (values) return values.map(literal).join(" | ");

  if (Array.isArray(object.oneOf) || Array.isArray(object.anyOf)) {
    const options = (Array.isArray(object.oneOf) ? object.oneOf : object.anyOf) as unknown[];
    const parts = await Promise.all(options.map((option, index) => tsTypeForSchema(option, path, protocolRoot, cache, [...stack, String(index)])));
    return [...new Set(parts)].join(" | ");
  }

  if (Array.isArray(object.allOf)) {
    const parts = await Promise.all(object.allOf.map((option, index) => tsTypeForSchema(option, path, protocolRoot, cache, [...stack, String(index)])));
    return parts.join(" & ");
  }

  if (Array.isArray(object.type)) {
    const parts = await Promise.all(object.type.map((type) => tsTypeForSchema({ ...object, type }, path, protocolRoot, cache, stack)));
    return [...new Set(parts)].join(" | ");
  }

  switch (object.type) {
    case "string":
      return "string";
    case "integer":
    case "number":
      return "number";
    case "boolean":
      return "boolean";
    case "null":
      return "null";
    case "array": {
      const itemType = await tsTypeForSchema(object.items ?? true, path, protocolRoot, cache, [...stack, "items"]);
      return `Array<${itemType}>`;
    }
    case "object":
    case undefined: {
      if (!isObject(object.properties)) return "Record<string, unknown>";
      const required = new Set(Array.isArray(object.required) ? object.required.map(String) : []);
      const entries = await Promise.all(
        Object.entries(object.properties).map(async ([name, propertySchema]) => {
          const optional = required.has(name) ? "" : "?";
          const type = await tsTypeForSchema(propertySchema, path, protocolRoot, cache, [...stack, name]);
          return `  readonly ${propertyName(name)}${optional}: ${type};`;
        }),
      );
      const indexSignature = object.additionalProperties === false ? [] : ["  readonly [key: string]: unknown;"];
      return `{\n${[...entries, ...indexSignature].join("\n")}\n}`;
    }
    default:
      throw new ProtocolCodegenError(`Unsupported JSON Schema type ${JSON.stringify(object.type)} at ${path}`);
  }
}

async function fieldsForVariant(schemaInput: unknown, contextPath: string, protocolRoot: string, cache: DocumentCache): Promise<RemotePiIrField[]> {
  const { schema, path } = await dereferenceSchema(schemaInput, contextPath, protocolRoot, cache);
  const object = asObject(schema, "variant schema");
  const properties = asObject(object.properties, "variant.properties");
  const required = new Set(Array.isArray(object.required) ? object.required.map(String) : []);
  const fields: RemotePiIrField[] = [];
  for (const [name, propertySchema] of Object.entries(properties)) {
    fields.push({
      name,
      required: required.has(name),
      tsType: await tsTypeForSchema(propertySchema, path, protocolRoot, cache, [name]),
    });
  }
  return fields;
}

function discriminatorValues(schema: JsonObject): Array<{ discriminator: string; type: string }> {
  const properties = isObject(schema.properties) ? schema.properties : undefined;
  if (!properties) return [];
  const typeSchema = isObject(properties.type) ? properties.type : undefined;
  const customTypeSchema = isObject(properties.customType) ? properties.customType : undefined;
  const typeValues = typeSchema ? constOrEnumValues(typeSchema)?.filter((value): value is string => typeof value === "string") : undefined;
  if (typeValues && typeValues.length > 0) return typeValues.map((type) => ({ discriminator: "type", type }));
  const customTypeValues = customTypeSchema ? constOrEnumValues(customTypeSchema)?.filter((value): value is string => typeof value === "string") : undefined;
  if (customTypeValues && customTypeValues.length > 0) return customTypeValues.map((type) => ({ discriminator: "customType", type }));
  return [];
}

async function variantsForFamily(family: RemotePiManifestFamily, familySchemaPath: string, protocolRoot: string, cache: DocumentCache): Promise<RemotePiIrVariant[]> {
  const root = await readDocument(familySchemaPath, cache);
  const oneOf = Array.isArray(root.oneOf) ? root.oneOf : undefined;
  if (!oneOf || oneOf.length === 0) throw placeholderDiagnostic(family);

  const unionName = unionNameForFamily(family.id);
  const variants: RemotePiIrVariant[] = [];
  const seenTypes = new Set<string>();
  for (const [index, option] of oneOf.entries()) {
    const optionObject = isObject(option) ? option : undefined;
    const ref = typeof optionObject?.$ref === "string" ? optionObject.$ref : undefined;
    if (!ref) continue;
    const resolved = await resolveSchemaRef(ref, familySchemaPath, protocolRoot, cache);
    const { schema, path } = await dereferenceSchema(resolved.schema, resolved.path, protocolRoot, cache);
    if (!isObject(schema)) continue;
    const discriminators = discriminatorValues(schema);
    for (const discriminator of discriminators) {
      // Some compatibility schemas describe the same custom event both as its
      // structured event payload and as the historical Pi `custom` message
      // wrapper. The spike target keeps the first manifest-ordered shape as
      // the canonical registry entry and leaves wrapper expansion to later
      // TS-codegen steps.
      if (seenTypes.has(discriminator.type)) continue;
      seenTypes.add(discriminator.type);
      variants.push({
        type: discriminator.type,
        discriminator: discriminator.discriminator,
        interfaceName: interfaceNameForVariant(unionName, discriminator.type),
        schemaRef: `${family.schema}#oneOf/${index}`,
        fields: await fieldsForVariant(schema, path, protocolRoot, cache),
      });
    }
  }

  if (variants.length === 0) throw placeholderDiagnostic(family);
  return variants;
}

export async function buildRemotePiIr(manifest: RemotePiManifest, options: BuildRemotePiIrOptions = {}): Promise<RemotePiIr> {
  const protocolRoot = resolve(options.protocolRoot ?? manifest.protocolRoot ?? (options.manifestPath ? protocolRootForManifestPath(options.manifestPath) : process.cwd()));
  const cache: DocumentCache = { documents: new Map() };
  const families: RemotePiIrFamily[] = [];
  for (const family of manifest.families) {
    const schemaPath = isAbsolute(family.schema) ? family.schema : join(protocolRoot, family.schema);
    const variants = await variantsForFamily(family, schemaPath, protocolRoot, cache);
    families.push({
      id: family.id,
      transport: family.transport,
      schemaPath,
      unionName: unionNameForFamily(family.id),
      variants,
    });
  }
  return {
    schemaVersion: manifest.schemaVersion ?? 1,
    source: manifest.source ?? "json-schema-2020-12",
    profile: options.profile ?? "compat",
    families,
  };
}

function familyConstName(familyId: string): string {
  return `${lowerCamel(familyId)}Types`;
}

function familyTypeName(familyId: string): string {
  return `${pascalCase(familyId)}Type`;
}

function emitInterface(variant: RemotePiIrVariant): string {
  const lines = [`export interface ${variant.interfaceName} {`];
  for (const field of variant.fields) {
    const optional = field.required ? "" : "?";
    lines.push(`  readonly ${propertyName(field.name)}${optional}: ${field.tsType};`);
  }
  lines.push("}");
  return lines.join("\n");
}

export function renderTypeScriptProtocol(ir: RemotePiIr): string {
  const sections: string[] = [];
  sections.push("// GENERATED CODE - DO NOT EDIT BY HAND.");
  sections.push("// Source: protocol/schema/manifest.json via protocol-codegen IR.");
  sections.push("/* eslint-disable */");
  sections.push("");
  sections.push("export type JsonValue = null | boolean | number | string | JsonValue[] | { readonly [key: string]: JsonValue };");
  sections.push("");
  sections.push("export const protocolManifest = {");
  sections.push(`  schemaVersion: ${ir.schemaVersion},`);
  sections.push(`  source: ${literal(ir.source)},`);
  sections.push(`  profile: ${literal(ir.profile)},`);
  sections.push("  families: [");
  for (const family of ir.families) {
    sections.push(`    { id: ${literal(family.id)}, union: ${literal(family.unionName)}, transport: ${literal(family.transport)} },`);
  }
  sections.push("  ],");
  sections.push("} as const;");
  sections.push("");

  for (const family of ir.families) {
    const constName = familyConstName(family.id);
    const typeName = familyTypeName(family.id);
    sections.push(`export const ${constName} = [`);
    for (const variant of family.variants) sections.push(`  ${literal(variant.type)},`);
    sections.push("] as const;");
    sections.push(`export type ${typeName} = (typeof ${constName})[number];`);
    sections.push("");
    for (const variant of family.variants) {
      sections.push(emitInterface(variant));
      sections.push("");
    }
    sections.push(`export type ${family.unionName} =`);
    for (const [index, variant] of family.variants.entries()) {
      const prefix = index === 0 ? "  |" : "  |";
      sections.push(`${prefix} ${variant.interfaceName}`);
    }
    sections[sections.length - 1] += ";";
    sections.push("");
  }

  return `${sections.join("\n").trimEnd()}\n`;
}

export async function emitTypeScriptProtocol(ir: RemotePiIr, options: EmitTypeScriptProtocolOptions): Promise<string> {
  const output = renderTypeScriptProtocol(ir);
  if (options.outFile) {
    if (options.check) {
      let current: string;
      try {
        current = await readFile(options.outFile, "utf8");
      } catch {
        throw new ProtocolCodegenError(`Generated TypeScript protocol is stale: ${options.outFile}`);
      }
      if (current !== output) {
        throw new ProtocolCodegenError(`Generated TypeScript protocol is stale: ${options.outFile}`);
      }
    } else {
      await mkdir(dirname(options.outFile), { recursive: true });
      await writeFile(options.outFile, output, "utf8");
    }
  }
  return output;
}

function defaultManifestCandidates(schemaPath?: string): string[] {
  const cwd = process.cwd();
  const candidates = [
    join(cwd, "schema", "manifest.json"),
    join(cwd, "protocol", "schema", "manifest.json"),
  ];
  if (schemaPath && schemaPath !== "-") {
    candidates.unshift(join(dirname(resolve(schemaPath)), "manifest.json"));
    candidates.unshift(join(dirname(dirname(resolve(schemaPath))), "schema", "manifest.json"));
  }
  return unique(candidates.map((candidate) => resolve(candidate)));
}

async function loadDefaultManifest(schemaPath?: string): Promise<RemotePiManifest> {
  let lastError: unknown;
  for (const candidate of defaultManifestCandidates(schemaPath)) {
    try {
      return await loadRemotePiManifest(candidate);
    } catch (error) {
      lastError = error;
    }
  }
  throw new ProtocolCodegenError(`Unable to locate protocol/schema/manifest.json: ${lastError instanceof Error ? lastError.message : String(lastError)}`);
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks).toString("utf8");
}

async function readSchemaInput(schemaPath: string): Promise<unknown> {
  if (schemaPath === "-") return JSON.parse(await readStdin()) as unknown;
  return readJsonFile<unknown>(schemaPath);
}

function isCatalog(value: unknown): value is CatalogEntry[] {
  return Array.isArray(value) && value.every((entry) => isObject(entry) && typeof entry.family === "string" && typeof entry.type === "string" && typeof entry.schemaRef === "string");
}

export async function buildRemotePiIrFromSchemaInput(schemaPath: string, options: BuildRemotePiIrOptions = {}): Promise<RemotePiIr> {
  const input = await readSchemaInput(schemaPath);
  if (isCatalog(input)) {
    const manifest = await loadDefaultManifest(schemaPath);
    return buildRemotePiIr(manifest, { ...options, protocolRoot: manifest.protocolRoot });
  }
  if (isObject(input) && Array.isArray(input.families)) {
    const manifestPath = schemaPath === "-" ? undefined : resolve(schemaPath);
    const manifest = input as RemotePiManifest;
    manifest.manifestPath = manifestPath;
    manifest.protocolRoot = options.protocolRoot ?? (manifestPath ? protocolRootForManifestPath(manifestPath) : process.cwd());
    return buildRemotePiIr(manifest, options);
  }
  throw new ProtocolCodegenError("TypeScript target expects a list-types catalog or protocol manifest JSON schema input");
}
