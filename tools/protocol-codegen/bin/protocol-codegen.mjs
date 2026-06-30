#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, isAbsolute, join } from 'node:path';
import { mkdirSync } from 'node:fs';

function usage() {
  return [
    'Usage:',
    '  node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema <ir.json> --out <file.dart>',
    '  node tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema <list-types.json|-> --out-dir <dir> [--check true]',
    '  node tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema <relay-outer.schema.json> --out <file.rs>',
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
  switch (field.read) {
    case 'sessionIdRequired':
      return '_sessionIdFromJson(json)';
    case 'sessionIdOptional':
      return '_optionalSessionIdFromJson(json)';
    case 'firstImage':
      return `_firstImage(${access})`;
    case 'actionNameWithFallback':
      return `ActionName.fromWire((${access} as String?) ?? '') ?? ActionName.sessionCompact`;
    case 'byeReason':
      return `ByeReason.fromWire((${access} as String?) ?? '')`;
    case 'sessionHistoryEvents':
      return `(${access} as List<dynamic>).map((item) => SessionHistoryEvent.fromJson((item as Map).cast<String, dynamic>())).toList()`;
    case 'nonEmptyStringOptional':
      return `${access} is String && ${access}.isNotEmpty ? ${access} : null`;
    default:
      break;
  }

  switch (field.dartType) {
    case 'String':
      if (field.defaultValue !== undefined) return `(${access} as String?) ?? ${dartLiteral(field.defaultValue)}`;
      return field.required ? `${access} as String` : `${access} as String?`;
    case 'bool':
      if (field.defaultValue !== undefined) return `(${access} as bool?) ?? ${field.defaultValue ? 'true' : 'false'}`;
      return field.required ? `${access} as bool` : `${access} as bool?`;
    case 'int':
      if (field.defaultValue !== undefined) return `(${access} as num?)?.toInt() ?? ${Number(field.defaultValue)}`;
      return field.required
        ? `(${access} as num).toInt()`
        : `(${access} as num?)?.toInt()`;
    case 'double':
      return field.required
        ? `(${access} as num).toDouble()`
        : `(${access} as num?)?.toDouble()`;
    case 'dynamic':
      return access;
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
    case 'Usage':
      return field.required
        ? `Usage.fromJson((${access} as Map).cast<String, dynamic>())`
        : `${access} == null ? null : Usage.fromJson((${access} as Map).cast<String, dynamic>())`;
    case 'PiHarness':
      return `${access} is Map ? PiHarness.fromJson(${access}.cast<String, dynamic>()) : null`;
    case 'List<WireModel>':
      return `(${access} as List<dynamic>? ?? const <dynamic>[]).map((item) => WireModel.fromJson((item as Map).cast<String, dynamic>())).toList()`;
    case 'WireModel':
      return field.required
        ? `WireModel.fromJson((${access} as Map).cast<String, dynamic>())`
        : `${access} is Map ? WireModel.fromJson(${access}.cast<String, dynamic>()) : null`;
    case 'ActionName':
      return `ActionName.fromWire((${access} as String?) ?? '')`;
    case 'ByeReason':
      return `ByeReason.fromWire((${access} as String?) ?? '')`;
    case 'List<SessionHistoryEvent>':
      return `(${access} as List<dynamic>).map((item) => SessionHistoryEvent.fromJson((item as Map).cast<String, dynamic>())).toList()`;
    default:
      throw new Error(`Unsupported Dart field type ${JSON.stringify(field.dartType)} for ${field.name}`);
  }
}

function dartJsonValueExpression(field, valueName = field.name) {
  switch (field.write) {
    case 'firstImageList':
      return `[${dartJsonValueExpression({ ...field, write: undefined, dartType: 'WireImage' }, valueName)}]`;
    default:
      break;
  }

  switch (field.dartType) {
    case 'WireImage':
      return `${valueName}.toJson()`;
    case 'List<WireImage>':
      return `${valueName}.map((image) => image.toJson()).toList()`;
    case 'Usage':
      return `${valueName}.toJson()`;
    case 'PiHarness':
      return `${valueName}.toJson()`;
    case 'List<WireModel>':
      return `${valueName}.map((model) => model.toJson()).toList()`;
    case 'WireModel':
      return `${valueName}.toJson()`;
    case 'List<SessionHistoryEvent>':
      return `${valueName}.map((event) => event.toJson()).toList()`;
    case 'ApproveDecision':
      return `${valueName}.name`;
    case 'UserMessageStreamingBehavior':
      return `${valueName}.wireValue`;
    case 'ThinkingLevel':
    case 'ActionName':
    case 'ByeReason':
      return `${valueName}.wire`;
    default:
      return valueName;
  }
}

function toJsonEntry(field) {
  if (field.includeInJson === false) return null;
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

function dartFieldType(field) {
  if (field.required || field.dartType === 'dynamic' || field.dartType.endsWith('?')) return field.dartType;
  return `${field.dartType}?`;
}

function pascalCase(value) {
  return String(value)
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`)
    .join('');
}

function lowerCamel(value) {
  const text = String(value);
  return `${text.charAt(0).toLowerCase()}${text.slice(1)}`;
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
      if (variant.aliasOf !== undefined) assertIdentifier(variant.aliasOf, `${union.name}.variant.aliasOf`);
      if (seenTypes.has(variant.type)) {
        throw new Error(`Duplicate wire type ${variant.type} in ${union.name}`);
      }
      if (seenClasses.has(variant.className) && variant.aliasOf === undefined) {
        throw new Error(`Duplicate className ${variant.className} in ${union.name}`);
      }
      seenTypes.add(variant.type);
      if (variant.aliasOf === undefined) seenClasses.add(variant.className);
      if (variant.sessionScoped !== undefined && typeof variant.sessionScoped !== 'boolean') {
        throw new Error(`${variant.className}.sessionScoped must be a boolean when present`);
      }
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

function targetClassName(variant) {
  return variant.aliasOf ?? variant.className;
}

function emitAdapterDecoder(union) {
  const decoderName = `Generated${union.name}Decoders`;
  const functionName = `decodeGenerated${union.name}`;
  const typedefName = `Generated${union.name}JsonDecoder`;
  const emittedClasses = union.variants.filter((variant) => variant.aliasOf === undefined).map((variant) => variant.className);
  const lines = [];
  lines.push(`typedef ${typedefName}<T> = T Function(Map<String, dynamic> json);`);
  lines.push('');
  lines.push(`final class ${decoderName}<T> {`);
  lines.push(`  const ${decoderName}({`);
  for (const className of emittedClasses) {
    lines.push(`    required this.${lowerCamel(className)},`);
  }
  lines.push('  });');
  lines.push('');
  for (const className of emittedClasses) {
    lines.push(`  final ${typedefName}<T> ${lowerCamel(className)};`);
  }
  lines.push('}');
  lines.push('');
  lines.push(`T ${functionName}<T>(`);
  lines.push('  Map<String, dynamic> json,');
  lines.push(`  ${decoderName}<T> decoders,`);
  lines.push(') {');
  lines.push("  final type = json['type'] as String?;");
  lines.push('  return switch (type) {');
  for (const variant of union.variants) {
    lines.push(`    ${dartLiteral(variant.type)} => decoders.${lowerCamel(targetClassName(variant))}(json),`);
  }
  lines.push("    final unknown => throw UnsupportedTypeException(unknown ?? ''),");
  lines.push('  };');
  lines.push('}');
  lines.push('');
  return lines.join('\n');
}

function dartDefaultLiteral(value) {
  if (typeof value === 'string') return dartLiteral(value);
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value === null) return 'null';
  throw new Error(`Unsupported Dart constructor default ${JSON.stringify(value)}`);
}

function constructorParam(field) {
  if (field.constructorDefault !== undefined) {
    return `this.${field.name} = ${dartDefaultLiteral(field.constructorDefault)}`;
  }
  const prefix = field.required ? 'required ' : '';
  return `${prefix}this.${field.name}`;
}

function emitSessionScopedRegistry(union) {
  const sessionScoped = union.variants.filter((variant) => variant.sessionScoped === true);
  if (sessionScoped.length === 0) return '';
  const lines = [];
  const registryName = `generatedSessionScoped${union.name}Types`;
  lines.push(`const Set<String> ${registryName} = {`);
  for (const variant of sessionScoped) {
    lines.push(`  ${dartLiteral(variant.type)},`);
  }
  lines.push('};');
  lines.push('');
  lines.push(`bool isGeneratedSessionScoped${union.name}Type(String type) =>`);
  lines.push(`    ${registryName}.contains(type);`);
  return lines.join('\n');
}

function emitServerMessageHelpers(union) {
  if (union.name !== 'ServerMessage') return '';
  if (!union.variants.some((variant) => variant.sessionScoped === true)) return '';
  const emittedWithSessionId = union.variants
    .filter((variant) => variant.aliasOf === undefined)
    .filter((variant) => (variant.fields ?? []).some((field) => field.name === 'sessionId'));
  const lines = [];
  lines.push('String typeOfServerMessage(ServerMessage message) => message.type;');
  lines.push('');
  lines.push('String? sessionIdOfServerMessage(ServerMessage message) => switch (message) {');
  for (const variant of emittedWithSessionId) {
    if (variant.className === 'PairOk') {
      lines.push('      PairOk(:final sessionId) => sessionId.isEmpty ? null : sessionId,');
    } else {
      lines.push(`      ${variant.className}(:final sessionId) => sessionId,`);
    }
  }
  lines.push('      _ => null,');
  lines.push('    };');
  return lines.join('\n');
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
  const sessionScopedRegistry = emitSessionScopedRegistry(union);
  if (sessionScopedRegistry.length > 0) {
    lines.push(sessionScopedRegistry);
    lines.push('');
  }
  lines.push(`sealed class ${union.name} {`);
  lines.push(`  const ${union.name}();`);
  lines.push('  String get type;');
  if (union.name === 'SessionHistoryEvent') {
    lines.push('  int get ts;');
  }
  lines.push('');
  lines.push(`  static ${union.name} fromJson(Map<String, dynamic> json) {`);
  lines.push("    final type = json['type'] as String?;");
  lines.push('    return switch (type) {');
  for (const variant of union.variants) {
    lines.push(`      ${dartLiteral(variant.type)} => ${targetClassName(variant)}.fromJson(json),`);
  }
  lines.push("      final unknown => throw UnsupportedTypeException(unknown ?? ''),");
  lines.push('    };');
  lines.push('  }');
  lines.push('');
  lines.push('  Map<String, dynamic> toJson();');
  lines.push('}');
  lines.push('');

  for (const variant of union.variants) {
    if (variant.aliasOf !== undefined) continue;
    const fields = variant.fields ?? [];
    const requiredParams = fields.map((field) => constructorParam(field));
    const params = requiredParams.length > 0 ? `{${requiredParams.join(', ')}}` : '';

    lines.push(`final class ${variant.className} extends ${union.name} {`);
    lines.push(`  const ${variant.className}(${params});`);
    lines.push('');
    lines.push('  @override');
    lines.push(`  String get type => ${dartLiteral(variant.type)};`);
    lines.push('');
    for (const field of fields) {
      if (union.name === 'SessionHistoryEvent' && field.name === 'ts') {
        lines.push('  @override');
      }
      lines.push(`  final ${dartFieldType(field)} ${field.name};`);
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
      const entry = toJsonEntry(field);
      if (entry) lines.push(entry);
    }
    lines.push('      };');
    lines.push('}');
    lines.push('');
  }

  if (union.emitAdapterDecoder === true) {
    lines.push(emitAdapterDecoder(union).trimEnd());
    lines.push('');
  }

  const helpers = emitServerMessageHelpers(union);
  if (helpers.length > 0) {
    lines.push(helpers);
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

final class Usage {
  const Usage({required this.inputTokens, required this.outputTokens});

  final int inputTokens;
  final int outputTokens;

  factory Usage.fromJson(Map<String, dynamic> json) => Usage(
        inputTokens: (json['input_tokens'] as num).toInt(),
        outputTokens: (json['output_tokens'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
      };
}

final class PiHarness {
  const PiHarness({required this.name, required this.version});

  final String name;
  final String version;

  static const PiHarness piCodingAgentUnknown = PiHarness(
    name: 'Pi coding agent',
    version: '—',
  );

  factory PiHarness.fromJson(Map<String, dynamic> json) => PiHarness(
        name: (json['name'] as String?) ?? piCodingAgentUnknown.name,
        version: (json['version'] as String?) ?? piCodingAgentUnknown.version,
      );

  Map<String, dynamic> toJson() => {'name': name, 'version': version};

  @override
  bool operator ==(Object other) =>
      other is PiHarness && other.name == name && other.version == version;

  @override
  int get hashCode => Object.hash(name, version);
}

enum ByeReason {
  peerStop('peer_stop'),
  sessionReplaced('session_replaced'),
  shutdown('shutdown'),
  unknown('');

  const ByeReason(this.wire);
  final String wire;

  static ByeReason fromWire(String raw) => switch (raw) {
        'peer_stop' => ByeReason.peerStop,
        'session_replaced' => ByeReason.sessionReplaced,
        'shutdown' => ByeReason.shutdown,
        _ => ByeReason.unknown,
      };
}

String _sessionIdFromJson(Map<String, dynamic> json) {
  final sessionId = json['session_id'];
  if (sessionId is String && sessionId.isNotEmpty) return sessionId;
  throw const FormatException('missing required field session_id');
}

String _optionalSessionIdFromJson(Map<String, dynamic> json) {
  final sessionId = json['session_id'];
  return sessionId is String ? sessionId : '';
}

WireImage? _firstImage(dynamic raw) {
  if (raw is! List || raw.isEmpty) return null;
  final first = raw.first;
  if (first is! Map) return null;
  return WireImage.fromJson(first.cast<String, dynamic>());
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

const RELAY_CLIENT_CONTROL_TYPES = [
  'subscribe_presence',
  'unsubscribe_presence',
  'presence_check',
  'subscribe_rooms',
  'unsubscribe_rooms',
  'rooms_check',
  'room_meta_update',
];

function schemaForCatalogEntry(entry, schemaPath) {
  if (typeof entry.schemaRef !== 'string') {
    throw new Error(`Catalog entry ${entry.type} is missing schemaRef`);
  }
  return requireObject(readJsonSchemaRef(entry.schemaRef, schemaPath), `${entry.type} schema`);
}

function schemaHasProperty(schema, propertyName) {
  return Object.hasOwn(requireObject(schema.properties, `${schema.title ?? 'schema'}.properties`), propertyName);
}

function emitRustControlPeerVariant(lines, type, schema) {
  if (!schemaHasProperty(schema, 'peers')) {
    throw new Error(`Relay control frame ${type} must declare a peers property in schema`);
  }
  lines.push(`    #[serde(rename = "${type}")]`);
  lines.push(`    ${rustVariantName(type)} {`);
  lines.push('        #[serde(default)]');
  lines.push('        peers: Vec<String>,');
  lines.push('    },');
}

function emitRustControl(entries, schemaPath) {
  const lines = rustHeader('control');
  const byType = new Map(entries.map((entry) => [entry.type, entry]));
  const schemasByType = new Map(entries.map((entry) => [entry.type, schemaForCatalogEntry(entry, schemaPath)]));
  const hasType = (type) => byType.has(type);
  const clientControlTypes = RELAY_CLIENT_CONTROL_TYPES.filter(hasType);

  lines.push('use serde::{Deserialize, Serialize};');
  if (hasType('room_meta_update')) {
    lines.push('use super::room::RoomMetaPatch;');
  }
  lines.push('');

  if (hasType('hello') || hasType('auth')) {
    lines.push('#[derive(Debug, Clone, Deserialize)]');
    lines.push('#[serde(tag = "type", rename_all = "snake_case")]');
    lines.push('pub enum ClientAuthMsg {');
    if (hasType('hello')) {
      const helloSchema = schemasByType.get('hello');
      if (!schemaHasProperty(helloSchema, 'pubkey')) throw new Error('hello schema must declare pubkey');
      if (!schemaHasProperty(helloSchema, 'room_id')) throw new Error('hello schema must declare room_id');
      if (!schemaHasProperty(helloSchema, 'room_meta')) throw new Error('hello schema must declare room_meta');
      lines.push('    Hello {');
      lines.push('        pubkey: String,');
      lines.push('        #[serde(default = "default_room")]');
      lines.push('        room_id: String,');
      lines.push('        #[serde(default)]');
      lines.push('        room_meta: Option<HelloRoomMeta>,');
      lines.push('    },');
    }
    if (hasType('auth')) {
      const authSchema = schemasByType.get('auth');
      if (!schemaHasProperty(authSchema, 'sig')) throw new Error('auth schema must declare sig');
      lines.push('    Auth { sig: String },');
    }
    lines.push('}');
    lines.push('');
  }

  if (hasType('hello')) {
    lines.push('#[derive(Debug, Default, Clone, Deserialize)]');
    lines.push('pub struct HelloRoomMeta {');
    lines.push('    pub name: Option<String>,');
    lines.push('    pub cwd: Option<String>,');
    lines.push('    pub model: Option<String>,');
    lines.push('    pub thinking: Option<String>,');
    lines.push('    pub session_id: Option<String>,');
    lines.push('    #[serde(default)]');
    lines.push('    pub working: bool,');
    lines.push('}');
    lines.push('');
    lines.push('fn default_room() -> String {');
    lines.push('    "main".to_string()');
    lines.push('}');
    lines.push('');
  }

  if (hasType('challenge')) {
    const challengeSchema = schemasByType.get('challenge');
    if (!schemaHasProperty(challengeSchema, 'nonce')) throw new Error('challenge schema must declare nonce');
    lines.push('#[derive(Debug, Clone, Serialize)]');
    lines.push('#[serde(tag = "type", rename_all = "snake_case")]');
    lines.push('pub enum ServerAuthMsg {');
    lines.push('    Challenge { nonce: String },');
    lines.push('}');
    lines.push('');
  }

  if (hasType('room_meta_update')) {
    const updateSchema = schemasByType.get('room_meta_update');
    if (!schemaHasProperty(updateSchema, 'room_id')) throw new Error('room_meta_update schema must declare room_id');
    if (!schemaHasProperty(updateSchema, 'meta')) throw new Error('room_meta_update schema must declare meta');
    lines.push('#[derive(Debug, Clone, Deserialize)]');
    lines.push('pub struct RoomMetaUpdateFrame {');
    lines.push('    #[serde(default)]');
    lines.push('    pub room_id: Option<String>,');
    lines.push('    pub meta: RoomMetaPatch,');
    lines.push('}');
    lines.push('');
  }

  lines.push('#[derive(Debug, Clone, Deserialize)]');
  lines.push('#[serde(tag = "type", rename_all = "snake_case")]');
  lines.push('pub enum RelayControlFrame {');
  for (const type of clientControlTypes) {
    const schema = schemasByType.get(type);
    if (type === 'room_meta_update') {
      if (!schemaHasProperty(schema, 'room_id')) throw new Error('room_meta_update schema must declare room_id');
      lines.push('    #[serde(rename = "room_meta_update")]');
      lines.push('    RoomMetaUpdate(RoomMetaUpdateFrame),');
    } else {
      emitRustControlPeerVariant(lines, type, schema);
    }
  }
  lines.push('}');
  lines.push('');
  lines.push('pub const RELAY_CONTROL_FRAME_TYPES: &[&str] = &[');
  for (const type of clientControlTypes) lines.push(`    "${type}",`);
  lines.push('];');
  lines.push('');
  lines.push('pub fn is_relay_control_frame_type(frame_type: &str) -> bool {');
  lines.push('    RELAY_CONTROL_FRAME_TYPES.contains(&frame_type)');
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

function requireObject(value, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value;
}

function fragmentLookup(schema, fragment) {
  if (!fragment || fragment === '#') return schema;
  const parts = fragment.replace(/^#\/?/, '').split('/').filter(Boolean);
  let current = schema;
  for (const rawPart of parts) {
    const part = rawPart.replaceAll('~1', '/').replaceAll('~0', '~');
    current = requireObject(current, `schema fragment ${fragment}`)[part];
  }
  return current;
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function readJsonSchemaRef(ref, schemaPath) {
  const [refPath = '', fragment = ''] = String(ref).split('#');
  if (refPath.length === 0) {
    if (!schemaPath || schemaPath === '-') {
      throw new Error(`Cannot resolve in-document schema ref ${JSON.stringify(ref)} without a schema file`);
    }
    const schema = readSchemaInput(schemaPath);
    return fragmentLookup(schema, `#${fragment}`);
  }

  const candidates = [];
  if (isAbsolute(refPath)) {
    candidates.push(refPath);
  } else {
    if (schemaPath && schemaPath !== '-') candidates.push(join(dirname(schemaPath), refPath));
    candidates.push(join(process.cwd(), refPath));
    candidates.push(join(process.cwd(), 'protocol', refPath));
    if (refPath.startsWith('./')) {
      candidates.push(join(process.cwd(), 'schema', refPath.slice(2)));
      candidates.push(join(process.cwd(), 'protocol', 'schema', refPath.slice(2)));
    } else {
      candidates.push(join(process.cwd(), 'schema', refPath));
      candidates.push(join(process.cwd(), 'protocol', 'schema', refPath));
    }
  }

  let lastError;
  for (const path of unique(candidates)) {
    try {
      const schema = JSON.parse(readFileSync(path, 'utf8'));
      return fragmentLookup(schema, fragment ? `#${fragment}` : '#');
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(
    `Unable to resolve schema ref ${JSON.stringify(ref)} from ${schemaPath}: ${
      lastError instanceof Error ? lastError.message : String(lastError)
    }`,
  );
}

function resolveOuterEnvelopeSchema(schema, schemaPath) {
  if (Array.isArray(schema)) {
    const entry = schema.find(
      (candidate) =>
        candidate &&
        typeof candidate === 'object' &&
        candidate.family === 'relayControl' &&
        candidate.type === 'outer_envelope' &&
        typeof candidate.schemaRef === 'string',
    );
    if (!entry) {
      throw new Error('Rust outer generation requires a relayControl outer_envelope entry in the shared IR');
    }
    return resolveOuterEnvelopeSchema(readJsonSchemaRef(entry.schemaRef, schemaPath), schemaPath);
  }

  const root = requireObject(schema, 'relay outer schema');
  if (typeof root.$ref === 'string') {
    return requireObject(fragmentLookup(root, root.$ref), root.$ref);
  }
  if (requireObject(root.$defs ?? {}, 'relay outer schema.$defs').outerEnvelope) {
    return requireObject(root.$defs.outerEnvelope, 'relay outer schema.$defs.outerEnvelope');
  }
  return root;
}

function assertRustFieldIdentifier(value, label) {
  if (typeof value !== 'string' || !/^[a-z_][A-Za-z0-9_]*$/.test(value)) {
    throw new Error(`${label} must be a Rust field identifier, got ${JSON.stringify(value)}`);
  }
}

function rustTypeForOuterField(fieldName, fieldSchema) {
  const field = requireObject(fieldSchema, `OuterEnvelope.${fieldName}`);
  if (field.type === 'string') return 'String';
  throw new Error(`Unsupported OuterEnvelope.${fieldName} schema type ${JSON.stringify(field.type)}`);
}

function emitRustOuter(schema, schemaPath) {
  const outerSchema = resolveOuterEnvelopeSchema(schema, schemaPath);
  const properties = requireObject(outerSchema.properties, 'OuterEnvelope.properties');
  const requiredFields = new Set(requireArray(outerSchema.required ?? [], 'OuterEnvelope.required').map(String));
  const lines = rustHeader('outer');
  lines.push('use serde::{Deserialize, Serialize};');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  if (outerSchema.additionalProperties === false) {
    lines.push('#[serde(deny_unknown_fields)]');
  }
  lines.push('pub struct OuterEnvelope {');
  for (const [fieldName, fieldSchema] of Object.entries(properties)) {
    assertRustFieldIdentifier(fieldName, `OuterEnvelope field ${fieldName}`);
    if (!requiredFields.has(fieldName)) {
      throw new Error(
        `OuterEnvelope.${fieldName} is optional in schema; update the schema/IR or teach the Rust generator the intended optional/default semantics`,
      );
    }
    lines.push(`    pub ${fieldName}: ${rustTypeForOuterField(fieldName, fieldSchema)},`);
  }
  lines.push('}');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function relayControlRootSchemaFromCatalog(entries, schemaPath) {
  const relayEntry = entries.find(
    (entry) =>
      entry &&
      entry.family === 'relayControl' &&
      typeof entry.schemaRef === 'string' &&
      entry.schemaRef.includes('relay-control.schema.json'),
  );
  if (!relayEntry) {
    throw new Error('Rust room generation requires a relayControl entry from relay-control.schema.json');
  }
  const relaySchemaPath = relayEntry.schemaRef.split('#')[0];
  return requireObject(readJsonSchemaRef(relaySchemaPath, schemaPath), 'relay control schema');
}

function relayRoomDef(rootSchema, defName) {
  return requireObject(
    requireObject(rootSchema.$defs ?? {}, 'relay control schema.$defs')[defName],
    `relay control schema.$defs.${defName}`,
  );
}

function rustTypeForRoomMetaField(fieldName, fieldSchema) {
  const field = requireObject(fieldSchema, `RoomMeta.${fieldName}`);
  if (field.type === 'string') return 'String';
  if (field.type === 'boolean') return 'bool';
  if (field.type === 'integer') return 'i64';
  if (typeof field.$ref === 'string') {
    if (field.$ref.endsWith('/epochMillis')) return 'i64';
    if (field.$ref.endsWith('/roomId') || field.$ref.endsWith('/sessionId')) return 'String';
  }
  throw new Error(`Unsupported RoomMeta.${fieldName} schema ${JSON.stringify(field)}`);
}

function nullableStringPatchFields(patchSchema) {
  const metadata = requireObject(patchSchema['x-remote-pi'] ?? {}, 'roomMetaPatch.x-remote-pi');
  const semantics = requireObject(metadata.mergePatchSemantics ?? {}, 'roomMetaPatch.mergePatchSemantics');
  return new Set(requireArray(semantics.nullableStrings ?? [], 'roomMetaPatch.nullableStrings').map(String));
}

function nonNullableBoolPatchFields(patchSchema) {
  const metadata = requireObject(patchSchema['x-remote-pi'] ?? {}, 'roomMetaPatch.x-remote-pi');
  const semantics = requireObject(metadata.mergePatchSemantics ?? {}, 'roomMetaPatch.mergePatchSemantics');
  return new Set(requireArray(semantics.nonNullableBooleans ?? [], 'roomMetaPatch.nonNullableBooleans').map(String));
}

function emitRustRoom(entries, schemaPath) {
  const rootSchema = relayControlRootSchemaFromCatalog(entries, schemaPath);
  const roomMeta = relayRoomDef(rootSchema, 'roomMeta');
  const roomMetaPatch = relayRoomDef(rootSchema, 'roomMetaPatch');
  const roomRequired = new Set(requireArray(roomMeta.required ?? [], 'roomMeta.required').map(String));
  const roomProperties = requireObject(roomMeta.properties, 'roomMeta.properties');
  const patchProperties = requireObject(roomMetaPatch.properties, 'roomMetaPatch.properties');
  const nullableStrings = nullableStringPatchFields(roomMetaPatch);
  const nonNullableBooleans = nonNullableBoolPatchFields(roomMetaPatch);

  const lines = rustHeader('room');
  lines.push('use serde::de::{self, MapAccess, Visitor};');
  lines.push('use serde::{Deserialize, Deserializer, Serialize};');
  lines.push('');
  lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
  lines.push('pub struct RoomMeta {');
  for (const [fieldName, fieldSchema] of Object.entries(roomProperties)) {
    assertRustFieldIdentifier(fieldName, `RoomMeta field ${fieldName}`);
    const rustType = rustTypeForRoomMetaField(fieldName, fieldSchema);
    if (roomRequired.has(fieldName)) {
      if (fieldName === 'working') lines.push('    #[serde(default)]');
      lines.push(`    pub ${fieldName}: ${rustType},`);
    } else {
      lines.push('    #[serde(skip_serializing_if = "Option::is_none")]');
      lines.push(`    pub ${fieldName}: Option<${rustType}>,`);
    }
  }
  lines.push('}');
  lines.push('');
  const patchFieldNames = Object.keys(patchProperties);
  lines.push('#[derive(Debug, Default, Clone)]');
  lines.push('pub struct RoomMetaPatch {');
  for (const [fieldName, fieldSchema] of Object.entries(patchProperties)) {
    assertRustFieldIdentifier(fieldName, `RoomMetaPatch field ${fieldName}`);
    if (nullableStrings.has(fieldName)) {
      lines.push(`    pub ${fieldName}: Option<Option<String>>,`);
      continue;
    }
    if (nonNullableBooleans.has(fieldName)) {
      const field = requireObject(fieldSchema, `RoomMetaPatch.${fieldName}`);
      if (field.type !== 'boolean') {
        throw new Error(`RoomMetaPatch.${fieldName} must be a boolean schema for non-nullable bool patches`);
      }
      lines.push(`    pub ${fieldName}: Option<bool>,`);
      continue;
    }
    throw new Error(`Unsupported RoomMetaPatch.${fieldName} schema ${JSON.stringify(fieldSchema)}`);
  }
  lines.push('}');
  lines.push('');
  lines.push(`const ROOM_META_PATCH_FIELDS: &[&str] = &[${patchFieldNames.map((name) => `"${name}"`).join(', ')}];`);
  lines.push('');
  lines.push('impl<\'de> Deserialize<\'de> for RoomMetaPatch {');
  lines.push('    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>');
  lines.push('    where');
  lines.push('        D: Deserializer<\'de>,');
  lines.push('    {');
  lines.push('        deserializer.deserialize_map(RoomMetaPatchVisitor)');
  lines.push('    }');
  lines.push('}');
  lines.push('');
  lines.push('struct RoomMetaPatchVisitor;');
  lines.push('');
  lines.push('impl<\'de> Visitor<\'de> for RoomMetaPatchVisitor {');
  lines.push('    type Value = RoomMetaPatch;');
  lines.push('');
  lines.push('    fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {');
  lines.push('        formatter.write_str("a room metadata patch object")');
  lines.push('    }');
  lines.push('');
  lines.push('    fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>');
  lines.push('    where');
  lines.push('        A: MapAccess<\'de>,');
  lines.push('    {');
  lines.push('        let mut patch = RoomMetaPatch::default();');
  lines.push('        while let Some(key) = map.next_key::<String>()? {');
  lines.push('            match key.as_str() {');
  for (const fieldName of patchFieldNames) {
    if (nullableStrings.has(fieldName)) {
      lines.push(`                "${fieldName}" => {`);
      lines.push(`                    if patch.${fieldName}.is_some() {`);
      lines.push(`                        return Err(de::Error::duplicate_field("${fieldName}"));`);
      lines.push('                    }');
      lines.push(`                    patch.${fieldName} = Some(map.next_value::<Option<String>>()?);`);
      lines.push('                }');
    } else if (nonNullableBooleans.has(fieldName)) {
      lines.push(`                "${fieldName}" => {`);
      lines.push(`                    if patch.${fieldName}.is_some() {`);
      lines.push(`                        return Err(de::Error::duplicate_field("${fieldName}"));`);
      lines.push('                    }');
      lines.push(`                    patch.${fieldName} = Some(map.next_value::<bool>()?);`);
      lines.push('                }');
    }
  }
  lines.push('                other => return Err(de::Error::unknown_field(other, ROOM_META_PATCH_FIELDS)),');
  lines.push('            }');
  lines.push('        }');
  lines.push('        Ok(patch)');
  lines.push('    }');
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

function emitRust(schema, schemaPath) {
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
    ['outer.rs', emitRustOuter(schema, schemaPath)],
    ['room.rs', emitRustRoom(entries, schemaPath)],
    ['control.rs', emitRustControl((byModule.get('control') ?? []).sort((a, b) => a.type.localeCompare(b.type)), schemaPath)],
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
    if (!schemaPath || (!outDir && !outPath)) throw new Error(usage());
    const rawSchema = readSchemaInput(schemaPath);
    if (outPath) {
      const content = rustfmtContent(emitRustOuter(rawSchema, schemaPath));
      mkdirSync(dirname(outPath), { recursive: true });
      writeFileSync(outPath, content, 'utf8');
      return;
    }
    const outputs = emitRust(rawSchema, schemaPath);
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
