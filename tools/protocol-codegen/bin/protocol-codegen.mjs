#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname } from 'node:path';
import { mkdirSync } from 'node:fs';

function usage() {
  return [
    'Usage:',
    '  node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema <ir.json> --out <file.dart>',
    '  node tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema <list-types.json|-> --out-dir <dir> [--check true]',
  ].join('\n');
}

function parseArgs(argv) {
  const args = new Map();
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key?.startsWith('--')) throw new Error(usage());
    const next = argv[i + 1];
    if (next == null || next.startsWith('--')) {
      args.set(key.slice(2), 'true');
    } else {
      args.set(key.slice(2), next);
      i += 1;
    }
  }
  return args;
}

function assertIdentifier(value, label) {
  if (typeof value !== 'string' || !/^[A-Za-z][A-Za-z0-9]*$/.test(value)) {
    throw new Error(`${label} must be a Dart identifier, got ${JSON.stringify(value)}`);
  }
}

function assertWireName(value, label) {
  if (typeof value !== 'string' || !/^[a-z][a-z0-9_:-]*$/.test(value)) {
    throw new Error(`${label} must be a wire discriminator string, got ${JSON.stringify(value)}`);
  }
}

function requireArray(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
  }
  return value;
}

function dartLiteral(value) {
  return `'${String(value).replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'`;
}

function jsonReadExpression(field) {
  const access = `json[${dartLiteral(field.wireName)}]`;
  switch (field.dartType) {
    case 'String':
      return field.required ? `${access} as String` : `${access} as String?`;
    case 'bool':
      return field.required ? `${access} as bool` : `${access} as bool?`;
    case 'int':
      return field.required
        ? `(${access} as num).toInt()`
        : `(${access} as num?)?.toInt()`;
    case 'double':
      return field.required
        ? `(${access} as num).toDouble()`
        : `(${access} as num?)?.toDouble()`;
    case 'Object?':
    case 'Map<String, dynamic>':
      return field.required
        ? `${access} as ${field.dartType}`
        : `${access} as ${field.dartType}?`;
    case 'WireImage':
      return `WireImage.fromJson((${access} as Map).cast<String, dynamic>())`;
    case 'List<WireImage>':
      return `(${access} as List?)?.map((item) => WireImage.fromJson((item as Map).cast<String, dynamic>())).toList()`;
    case 'ApproveDecision':
      return `ApproveDecision.values.byName(${access} as String)`;
    case 'UserMessageStreamingBehavior':
      return `UserMessageStreamingBehavior.fromWire(${access} as String?)`;
    case 'ThinkingLevel':
      return field.required
        ? `ThinkingLevel.fromWire(${access} as String)!`
        : `(${access} as String?) == null ? null : ThinkingLevel.fromWire(${access} as String)`;
    default:
      throw new Error(`Unsupported Dart field type ${JSON.stringify(field.dartType)} for ${field.name}`);
  }
}

function dartJsonValueExpression(field, valueName = field.name) {
  switch (field.dartType) {
    case 'WireImage':
      return `${valueName}.toJson()`;
    case 'List<WireImage>':
      return `${valueName}.map((image) => image.toJson()).toList()`;
    case 'ApproveDecision':
      return `${valueName}.name`;
    case 'UserMessageStreamingBehavior':
      return `${valueName}.wireValue`;
    case 'ThinkingLevel':
      return `${valueName}.wire`;
    default:
      return valueName;
  }
}

function toJsonEntry(field) {
  const key = dartLiteral(field.wireName);
  if (field.required) {
    return `        ${key}: ${dartJsonValueExpression(field)},`;
  }
  if (field.dartType === 'List<WireImage>') {
    return [
      `        if (${field.name} case final ${field.name}? when ${field.name}.isNotEmpty)`,
      `          ${key}: ${dartJsonValueExpression(field)},`,
    ].join('\n');
  }
  return [
    `        if (${field.name} case final ${field.name}?)`,
    `          ${key}: ${dartJsonValueExpression(field)},`,
  ].join('\n');
}

function pascalCase(value) {
  return String(value)
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`)
    .join('');
}

function unionNameForFamily(family) {
  switch (family) {
    case 'appPiClient':
      return 'ClientMessage';
    case 'appPiServer':
      return 'ServerMessage';
    case 'relayControl':
      return 'RelayControlFrame';
    case 'crossPc':
      return 'CrossPcFrame';
    case 'cockpitControl':
      return 'CockpitControlFrame';
    default:
      return `${pascalCase(family)}Frame`;
  }
}

function classNameForType(type, unionName) {
  const base = pascalCase(type);
  const candidate = base.length > 0 ? base : 'Unknown';
  const reserved = new Set(['Error', 'Type', 'Object', 'String', 'List', 'Map', unionName]);
  return reserved.has(candidate) ? `${candidate}Frame` : candidate;
}

function normalizeListTypesCatalog(catalog, schemaPath) {
  const entries = requireArray(catalog, 'list-types catalog');
  const byFamily = new Map();
  for (const entry of entries) {
    if (!entry || typeof entry !== 'object') continue;
    if (entry.discriminator === 'untagged') continue;
    assertWireName(entry.type, 'catalog.entry.type');
    const family = typeof entry.family === 'string' ? entry.family : 'protocol';
    const bucket = byFamily.get(family) ?? [];
    bucket.push(entry);
    byFamily.set(family, bucket);
  }

  const globalClassNames = new Set();
  const unions = [...byFamily.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([family, familyEntries]) => {
      const unionName = unionNameForFamily(family);
      const variants = familyEntries
        .slice()
        .sort((a, b) => a.type.localeCompare(b.type))
        .map((entry) => {
          const baseClassName = classNameForType(entry.type, unionName);
          let className = baseClassName;
          if (globalClassNames.has(className)) className = `${baseClassName}${pascalCase(family)}`;
          let suffix = 2;
          while (globalClassNames.has(className)) {
            className = `${baseClassName}${pascalCase(family)}${suffix}`;
            suffix += 1;
          }
          globalClassNames.add(className);
          return {
            type: entry.type,
            className,
            fields: [],
            sourceSchemaRef: entry.schemaRef,
          };
        });
      return { name: unionName, variants };
    });

  if (unions.length === 0) {
    throw new Error(`${schemaPath} did not contain any typed list-types entries`);
  }
  return { unions };
}

function normalizeSchemaInput(schema, schemaPath) {
  if (Array.isArray(schema)) return normalizeListTypesCatalog(schema, schemaPath);
  return schema;
}

function validateSchema(schema) {
  const unions = requireArray(schema.unions, 'schema.unions');
  for (const union of unions) {
    assertIdentifier(union.name, 'union.name');
    const variants = requireArray(union.variants, `${union.name}.variants`);
    const seenTypes = new Set();
    const seenClasses = new Set();
    for (const variant of variants) {
      assertWireName(variant.type, `${union.name}.variant.type`);
      assertIdentifier(variant.className, `${union.name}.variant.className`);
      if (seenTypes.has(variant.type)) {
        throw new Error(`Duplicate wire type ${variant.type} in ${union.name}`);
      }
      if (seenClasses.has(variant.className)) {
        throw new Error(`Duplicate className ${variant.className} in ${union.name}`);
      }
      seenTypes.add(variant.type);
      seenClasses.add(variant.className);
      for (const field of requireArray(variant.fields ?? [], `${variant.className}.fields`)) {
        assertIdentifier(field.name, `${variant.className}.field.name`);
        assertWireName(field.wireName, `${variant.className}.field.wireName`);
        if (typeof field.dartType !== 'string') {
          throw new Error(`${variant.className}.${field.name}.dartType must be a string`);
        }
        if (typeof field.required !== 'boolean') {
          throw new Error(`${variant.className}.${field.name}.required must be a boolean`);
        }
      }
    }
  }
}

function emitUnion(union) {
  const registryName = `generated${union.name}Types`;
  const lines = [];
  lines.push(`const Set<String> ${registryName} = {`);
  for (const variant of union.variants) {
    lines.push(`  ${dartLiteral(variant.type)},`);
  }
  lines.push('};');
  lines.push('');
  lines.push(`sealed class ${union.name} {`);
  lines.push(`  const ${union.name}();`);
  lines.push('  String get type;');
  lines.push('');
  lines.push(`  static ${union.name} fromJson(Map<String, dynamic> json) {`);
  lines.push("    final type = json['type'] as String?;");
  lines.push('    return switch (type) {');
  for (const variant of union.variants) {
    lines.push(`      ${dartLiteral(variant.type)} => ${variant.className}.fromJson(json),`);
  }
  lines.push("      final unknown => throw UnsupportedTypeException(unknown ?? ''),");
  lines.push('    };');
  lines.push('  }');
  lines.push('');
  lines.push('  Map<String, dynamic> toJson();');
  lines.push('}');
  lines.push('');

  for (const variant of union.variants) {
    const fields = variant.fields ?? [];
    const requiredParams = fields.map((field) => {
      const prefix = field.required ? 'required ' : '';
      return `${prefix}this.${field.name}`;
    });
    const params = requiredParams.length > 0 ? `{${requiredParams.join(', ')}}` : '';

    lines.push(`final class ${variant.className} extends ${union.name} {`);
    lines.push(`  const ${variant.className}(${params});`);
    lines.push('');
    lines.push('  @override');
    lines.push(`  String get type => ${dartLiteral(variant.type)};`);
    lines.push('');
    for (const field of fields) {
      const nullableSuffix = field.required ? '' : '?';
      lines.push(`  final ${field.dartType}${nullableSuffix} ${field.name};`);
    }
    if (fields.length > 0) {
      lines.push('');
    }
    lines.push(`  factory ${variant.className}.fromJson(Map<String, dynamic> json) => ${variant.className}(`);
    for (const field of fields) {
      lines.push(`        ${field.name}: ${jsonReadExpression(field)},`);
    }
    lines.push('      );');
    lines.push('');
    lines.push('  @override');
    lines.push('  Map<String, dynamic> toJson() => {');
    lines.push("        'type': type,");
    for (const field of fields) {
      lines.push(toJsonEntry(field));
    }
    lines.push('      };');
    lines.push('}');
    lines.push('');
  }

  return lines.join('\n');
}

function emitDartSharedTypes() {
  return String.raw`
final class WireImage {
  const WireImage({required this.data, required this.mime});

  final String data;
  final String mime;

  factory WireImage.fromJson(Map<String, dynamic> json) => WireImage(
        data: json['data'] as String,
        mime: json['mime'] as String,
      );

  Map<String, dynamic> toJson() => {'data': data, 'mime': mime};

  @override
  bool operator ==(Object other) =>
      other is WireImage && other.data == data && other.mime == mime;

  @override
  int get hashCode => Object.hash(data, mime);
}

enum UserMessageStreamingBehavior {
  steer;

  static UserMessageStreamingBehavior? fromWire(String? raw) => switch (raw) {
        'steer' => UserMessageStreamingBehavior.steer,
        _ => null,
      };

  String get wireValue => switch (this) {
        UserMessageStreamingBehavior.steer => 'steer',
      };
}

enum ApproveDecision { allow, deny }

enum ActionName {
  sessionNew('session_new'),
  sessionCompact('session_compact'),
  modelSet('model_set'),
  thinkingSet('thinking_set');

  const ActionName(this.wire);
  final String wire;

  static ActionName? fromWire(String raw) {
    for (final action in values) {
      if (action.wire == raw) return action;
    }
    return null;
  }
}

enum ThinkingLevel {
  off('off'),
  minimal('minimal'),
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh');

  const ThinkingLevel(this.wire);
  final String wire;

  static ThinkingLevel? fromWire(String raw) {
    for (final level in values) {
      if (level.wire == raw) return level;
    }
    return null;
  }
}

final class WireModel {
  const WireModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.reasoning,
    required this.contextWindow,
    this.vision = false,
  });

  final String id;
  final String name;
  final String provider;
  final bool reasoning;
  final int contextWindow;
  final bool vision;

  factory WireModel.fromJson(Map<String, dynamic> json) => WireModel(
        id: json['id'] as String,
        name: json['name'] as String,
        provider: json['provider'] as String,
        reasoning: (json['reasoning'] as bool?) ?? false,
        contextWindow: (json['context_window'] as num?)?.toInt() ?? 0,
        vision: (json['vision'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'reasoning': reasoning,
        'context_window': contextWindow,
        'vision': vision,
      };

  @override
  bool operator ==(Object other) =>
      other is WireModel &&
      other.id == id &&
      other.provider == provider &&
      other.name == name &&
      other.reasoning == reasoning &&
      other.contextWindow == contextWindow &&
      other.vision == vision;

  @override
  int get hashCode =>
      Object.hash(id, provider, name, reasoning, contextWindow, vision);
}
`.trim();
}

function emitDart(schema) {
  const sections = [];
  sections.push('// GENERATED CODE - DO NOT MODIFY BY HAND.');
  sections.push('// Generated by tools/protocol-codegen/bin/protocol-codegen.mjs.');
  sections.push('// ignore_for_file: use_null_aware_elements');
  sections.push('');
  if (schema.includeAppPiSharedTypes === true) {
    sections.push(emitDartSharedTypes());
    sections.push('');
  }
  sections.push('class UnsupportedTypeException implements Exception {');
  sections.push('  const UnsupportedTypeException(this.type);');
  sections.push('');
  sections.push('  final String type;');
  sections.push('');
  sections.push('  @override');
  sections.push("  String toString() => 'UnsupportedTypeException($type)';");
  sections.push('}');
  sections.push('');
  for (const union of schema.unions) {
    sections.push(emitUnion(union).trimEnd());
    sections.push('');
  }
  return `${sections.join('\n').trimEnd()}\n`;
}


function rustModuleForFamily(family) {
  switch (family) {
    case 'relayControl':
      return 'control';
    case 'crossPc':
      return 'cross_pc';
    case 'appPiClient':
    case 'appPiServer':
      return null;
    case 'cockpitControl':
      return null;
    default:
      return null;
  }
}

function rustHeader(moduleName) {
  return [
    '// GENERATED CODE - DO NOT EDIT BY HAND.',
    '// Source: protocol/schema/manifest.json via protocol-codegen IR.',
    `// Module: ${moduleName}.`,
    '',
    '#![allow(dead_code)]',
    '',
  ];
}

function rustVariantName(type) {
  const name = pascalCase(type);
  return name.length > 0 ? name : 'Unknown';
}

function emitRustControl(entries) {
  const lines = rustHeader('control');
  lines.push('use serde::{Deserialize, Serialize};');
  lines.push('use serde_json::{Map, Value};');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct RawRelayControlFrame {');
  lines.push('    #[serde(rename = "type")]');
  lines.push('    pub frame_type: String,');
  lines.push('    #[serde(flatten)]');
  lines.push('    pub fields: Map<String, Value>,');
  lines.push('}');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('#[serde(tag = "type", rename_all = "snake_case")]');
  lines.push('pub enum RelayControlFrame {');
  for (const entry of entries) {
    lines.push(`    #[serde(rename = "${entry.type}")]`);
    lines.push(`    ${rustVariantName(entry.type)} {`);
    lines.push('        #[serde(flatten)]');
    lines.push('        fields: Map<String, Value>,');
    lines.push('    },');
  }
  lines.push('}');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function emitRustCrossPc(entries) {
  const lines = rustHeader('cross_pc');
  lines.push('use serde::{Deserialize, Serialize};');
  lines.push('use serde_json::Value;');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct AgentEnvelope {');
  lines.push('    pub from: String,');
  lines.push('    pub to: Value,');
  lines.push('    pub id: String,');
  lines.push('    pub re: Option<String>,');
  lines.push('    pub body: Value,');
  lines.push('}');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct PiEnvelopeFrame {');
  lines.push('    pub to_pc: String,');
  lines.push('    pub envelope: AgentEnvelope,');
  lines.push('}');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct PiEnvelopeInFrame {');
  lines.push('    pub from_pc: String,');
  lines.push('    pub envelope: AgentEnvelope,');
  lines.push('}');
  lines.push('');
  lines.push('pub const CROSS_PC_TYPES: &[&str] = &[');
  for (const entry of entries) lines.push(`    "${entry.type}",`);
  lines.push('];');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function emitRustOuter() {
  const lines = rustHeader('outer');
  lines.push('use serde::{Deserialize, Serialize};');
  lines.push('');
  lines.push('fn default_room() -> String { "main".to_owned() }');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct OuterEnvelope {');
  lines.push('    pub peer: String,');
  lines.push('    #[serde(default = "default_room")]');
  lines.push('    pub room: String,');
  lines.push('    pub ct: String,');
  lines.push('}');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function emitRustRoom() {
  const lines = rustHeader('room');
  lines.push('use serde::{Deserialize, Serialize};');
  lines.push('');
  lines.push('#[derive(Debug, Default, Clone, Serialize, Deserialize)]');
  lines.push('pub struct RoomMeta {');
  lines.push('    pub model: Option<String>,');
  lines.push('    pub thinking: Option<String>,');
  lines.push('    #[serde(default)]');
  lines.push('    pub working: bool,');
  lines.push('}');
  lines.push('');
  lines.push('#[derive(Debug, Default, Clone, Serialize, Deserialize)]');
  lines.push('pub struct RoomMetaPatch {');
  lines.push('    pub model: Option<Option<String>>,');
  lines.push('    pub thinking: Option<Option<String>>,');
  lines.push('    pub working: Option<bool>,');
  lines.push('}');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function emitRustMesh() {
  const lines = rustHeader('mesh');
  lines.push('use serde::{Deserialize, Serialize};');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct MeshEnvelopeWire {');
  lines.push('    pub blob: String,');
  lines.push('    pub sig: String,');
  lines.push('}');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct MeshGetResponse {');
  lines.push('    pub blob: String,');
  lines.push('    pub sig: String,');
  lines.push('    pub version: u64,');
  lines.push('    pub updated_at: i64,');
  lines.push('}');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function emitRustMod() {
  return [
    '// GENERATED CODE - DO NOT EDIT BY HAND.',
    '// Source: protocol/schema/manifest.json via protocol-codegen IR.',
    '',
    'pub mod control;',
    'pub mod cross_pc;',
    'pub mod mesh;',
    'pub mod outer;',
    'pub mod room;',
    '',
  ].join('\n');
}

function emitRust(schema) {
  const entries = requireArray(schema, 'list-types catalog');
  const byModule = new Map();
  for (const entry of entries) {
    const module = rustModuleForFamily(entry.family);
    if (!module) continue;
    const bucket = byModule.get(module) ?? [];
    bucket.push(entry);
    byModule.set(module, bucket);
  }
  return new Map([
    ['mod.rs', emitRustMod()],
    ['outer.rs', emitRustOuter()],
    ['room.rs', emitRustRoom()],
    ['control.rs', emitRustControl((byModule.get('control') ?? []).sort((a, b) => a.type.localeCompare(b.type)))],
    ['cross_pc.rs', emitRustCrossPc((byModule.get('cross_pc') ?? []).sort((a, b) => a.type.localeCompare(b.type)))],
    ['mesh.rs', emitRustMesh()],
  ]);
}

function readSchemaInput(schemaPath) {
  if (schemaPath === '-') {
    return JSON.parse(readFileSync(0, 'utf8'));
  }
  return JSON.parse(readFileSync(schemaPath, 'utf8'));
}

function rustfmtContent(content) {
  return execFileSync('rustfmt', ['--emit', 'stdout'], {
    input: content,
    encoding: 'utf8',
  });
}

function writeRustOutputs(outputs, outDir, check) {
  mkdirSync(outDir, { recursive: true });
  const stale = [];
  for (const [file, rawContent] of outputs.entries()) {
    const content = rustfmtContent(rawContent);
    const path = `${outDir}/${file}`;
    if (check) {
      let current = '';
      try {
        current = readFileSync(path, 'utf8');
      } catch (_) {
        stale.push(file);
        continue;
      }
      if (current !== content) stale.push(file);
    } else {
      writeFileSync(path, content, 'utf8');
    }
  }
  if (stale.length > 0) {
    throw new Error(`Generated Rust protocol is stale: ${stale.join(', ')}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const target = args.get('target');
  const schemaPath = args.get('schema');
  const outPath = args.get('out');
  const outDir = args.get('out-dir');
  const check = args.get('check') === 'true';

  if (target === 'dart') {
    if (!schemaPath || !outPath) throw new Error(usage());
    const rawSchema = readSchemaInput(schemaPath);
    const schema = normalizeSchemaInput(rawSchema, schemaPath);
    validateSchema(schema);
    const output = emitDart(schema);
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, output, 'utf8');
    return;
  }

  if (target === 'rust') {
    if (!schemaPath || !outDir) throw new Error(usage());
    const rawSchema = readSchemaInput(schemaPath);
    const outputs = emitRust(rawSchema);
    writeRustOutputs(outputs, outDir, check);
    return;
  }

  throw new Error(usage());
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
