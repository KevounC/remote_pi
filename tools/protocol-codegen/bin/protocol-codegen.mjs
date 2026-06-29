#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { mkdirSync } from 'node:fs';

function usage() {
  return [
    'Usage:',
    '  node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema <ir.json> --out <file.dart>',
  ].join('\n');
}

function parseArgs(argv) {
  const args = new Map();
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (!key?.startsWith('--') || value == null || value.startsWith('--')) {
      throw new Error(usage());
    }
    args.set(key.slice(2), value);
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
    default:
      throw new Error(`Unsupported Dart field type ${JSON.stringify(field.dartType)} for ${field.name}`);
  }
}

function toJsonEntry(field) {
  const key = dartLiteral(field.wireName);
  if (field.required) {
    return `        ${key}: ${field.name},`;
  }
  return [
    `        if (${field.name} case final ${field.name}?)`,
    `          ${key}: ${field.name},`,
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

function emitDart(schema) {
  const sections = [];
  sections.push('// GENERATED CODE - DO NOT MODIFY BY HAND.');
  sections.push('// Generated by tools/protocol-codegen/bin/protocol-codegen.mjs.');
  sections.push('// ignore_for_file: use_null_aware_elements');
  sections.push('');
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

function main() {
  const args = parseArgs(process.argv.slice(2));
  const target = args.get('target');
  const schemaPath = args.get('schema');
  const outPath = args.get('out');
  if (target !== 'dart' || !schemaPath || !outPath) {
    throw new Error(usage());
  }

  const rawSchema = JSON.parse(readFileSync(schemaPath, 'utf8'));
  const schema = normalizeSchemaInput(rawSchema, schemaPath);
  validateSchema(schema);
  const output = emitDart(schema);
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, output, 'utf8');
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
