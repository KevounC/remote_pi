import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'generated/minimal_protocol.g.dart' as generated;

void main() {
  group('minimal Dart protocol codegen', () {
    test('generator output is deterministic and matches the golden', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'protocol_codegen_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final outFile = File('${tempDir.path}/minimal_protocol.g.dart');
      final result = await Process.run('node', [
        '../tools/protocol-codegen/bin/protocol-codegen.mjs',
        '--target',
        'dart',
        '--schema',
        '../tools/protocol-codegen/fixtures/minimal_dart_ir.json',
        '--out',
        outFile.path,
      ]);

      expect(
        result.exitCode,
        0,
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );

      final golden = File(
        'test/protocol_codegen/goldens/minimal_protocol.g.dart.golden',
      ).readAsStringSync();
      expect(outFile.readAsStringSync(), golden);
      expect(
        File(
          'test/protocol_codegen/generated/minimal_protocol.g.dart',
        ).readAsStringSync(),
        golden,
        reason: 'The checked-in compile fixture must match the generator.',
      );
    });

    test('fixture variants appear once in dispatch and type getters', () {
      final schema =
          jsonDecode(
                File(
                  '../tools/protocol-codegen/fixtures/minimal_dart_ir.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final union =
          (schema['unions'] as List<dynamic>).single as Map<String, dynamic>;
      final variants = union['variants'] as List<dynamic>;
      final output = File(
        'test/protocol_codegen/generated/minimal_protocol.g.dart',
      ).readAsStringSync();

      expect(generated.generatedServerMessageTypes, {'pong', 'error'});
      for (final rawVariant in variants) {
        final variant = rawVariant as Map<String, dynamic>;
        final wireType = variant['type'] as String;
        final className = variant['className'] as String;

        expect(
          _count(output, "'$wireType' => $className.fromJson(json)"),
          1,
          reason: '$wireType should be dispatched exactly once',
        );
        expect(
          _count(output, "String get type => '$wireType';"),
          1,
          reason: '$wireType should have exactly one type getter',
        );
      }
    });

    test('generated union narrows fromJson and round-trips toJson', () {
      final pong = generated.ServerMessage.fromJson({
        'type': 'pong',
        'in_reply_to': 'req-1',
      });
      expect(pong, isA<generated.Pong>());
      expect(pong.toJson(), {'type': 'pong', 'in_reply_to': 'req-1'});

      final error = generated.ServerMessage.fromJson({
        'type': 'error',
        'message': 'boom',
        'code': 'bad_request',
      });
      expect(error, isA<generated.ErrorMessage>());
      expect(error.toJson(), {
        'type': 'error',
        'message': 'boom',
        'code': 'bad_request',
      });

      expect(
        () => generated.ServerMessage.fromJson({'type': 'future_type'}),
        throwsA(isA<generated.UnsupportedTypeException>()),
      );
    });

    test('generated sealed union supports an exhaustive switch', () {
      String describe(generated.ServerMessage message) => switch (message) {
        generated.Pong(:final inReplyTo) => 'pong:$inReplyTo',
        generated.ErrorMessage(:final message, :final code) =>
          'error:$message:${code ?? 'none'}',
      };

      expect(describe(const generated.Pong(inReplyTo: 'req-1')), 'pong:req-1');
      expect(
        describe(const generated.ErrorMessage(message: 'boom')),
        'error:boom:none',
      );
    });
  });
}

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;
