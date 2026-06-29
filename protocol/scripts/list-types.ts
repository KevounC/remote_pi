import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

interface ManifestFamily {
  id: string;
  transport: string;
  schema: string;
  description: string;
}

interface Manifest {
  families: ManifestFamily[];
}

interface CatalogEntry {
  family: string;
  transport: string;
  discriminator: "type" | "customType" | "untagged";
  type: string;
  schemaRef: string;
  profileRequired?: Record<string, string[]>;
  fixtureOptional?: boolean;
}

type JsonObject = Record<string, unknown>;

const protocolRoot = fileURLToPath(new URL("..", import.meta.url));
const schemaRoot = join(protocolRoot, "schema");

function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

function asObject(value: unknown): JsonObject | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonObject)
    : undefined;
}

function localDefName(ref: string): string | undefined {
  const prefix = "#/$defs/";
  return ref.startsWith(prefix) ? ref.slice(prefix.length) : undefined;
}

function extractProfileRequired(schema: JsonObject): Record<string, string[]> | undefined {
  const metadata = asObject(schema["x-remote-pi"]);
  const required = asObject(metadata?.profileRequired);
  if (!required) return undefined;
  return Object.fromEntries(
    Object.entries(required).map(([profile, fields]) => [
      profile,
      Array.isArray(fields) ? fields.map(String) : [],
    ]),
  );
}

function entryFromDefinition(
  family: ManifestFamily,
  schemaPath: string,
  defName: string,
  schema: JsonObject,
): CatalogEntry[] {
  const properties = asObject(schema.properties);
  const typeSchema = asObject(properties?.type);
  const customTypeSchema = asObject(properties?.customType);
  const typeConst = typeof typeSchema?.const === "string" ? typeSchema.const : undefined;
  const customTypeConst =
    typeof customTypeSchema?.const === "string" ? customTypeSchema.const : undefined;

  const profileRequired = extractProfileRequired(schema);
  const fixtureOptional = asObject(schema["x-remote-pi"])?.fixtureOptional === true;

  if (typeConst) {
    return [
      {
        family: family.id,
        transport: family.transport,
        discriminator: "type",
        type: typeConst,
        schemaRef: `${schemaPath}#/$defs/${defName}`,
        ...(profileRequired ? { profileRequired } : {}),
        ...(fixtureOptional ? { fixtureOptional } : {}),
      },
    ];
  }

  if (customTypeConst) {
    return [
      {
        family: family.id,
        transport: family.transport,
        discriminator: "customType",
        type: customTypeConst,
        schemaRef: `${schemaPath}#/$defs/${defName}`,
        ...(profileRequired ? { profileRequired } : {}),
        ...(fixtureOptional ? { fixtureOptional } : {}),
      },
    ];
  }

  const enumValues = Array.isArray(typeSchema?.enum) ? typeSchema.enum : [];
  return enumValues
    .filter((value): value is string => typeof value === "string")
    .map((type) => ({
      family: family.id,
      transport: family.transport,
      discriminator: "type" as const,
      type,
      schemaRef: `${schemaPath}#/$defs/${defName}`,
      ...(profileRequired ? { profileRequired } : {}),
      ...(fixtureOptional ? { fixtureOptional } : {}),
    }));
}

function catalogForFamily(family: ManifestFamily): CatalogEntry[] {
  const schema = readJson<JsonObject>(join(protocolRoot, family.schema));
  const defs = asObject(schema.$defs) ?? {};
  const oneOf = Array.isArray(schema.oneOf) ? schema.oneOf : [];
  const entries: CatalogEntry[] = [];

  for (const option of oneOf) {
    const optionObject = asObject(option);
    const ref = typeof optionObject?.$ref === "string" ? optionObject.$ref : undefined;
    if (!ref) continue;

    if (ref.startsWith("./")) {
      entries.push({
        family: family.id,
        transport: family.transport,
        discriminator: "untagged",
        type: ref.includes("relay-outer") ? "outer_envelope" : ref,
        schemaRef: ref,
      });
      continue;
    }

    const defName = localDefName(ref);
    if (!defName) continue;
    const def = asObject(defs[defName]);
    if (!def) continue;
    entries.push(...entryFromDefinition(family, family.schema, defName, def));
  }

  return entries.sort((a, b) => a.type.localeCompare(b.type));
}

const manifest = readJson<Manifest>(join(schemaRoot, "manifest.json"));
const catalog = manifest.families.flatMap(catalogForFamily).sort((a, b) => {
  const byFamily = a.family.localeCompare(b.family);
  return byFamily !== 0 ? byFamily : a.type.localeCompare(b.type);
});

console.log(JSON.stringify(catalog, null, 2));
