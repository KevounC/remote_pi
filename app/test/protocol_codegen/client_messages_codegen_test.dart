import 'dart:convert';
import 'dart:io';

import 'package:app/protocol/generated/protocol.g.dart' as generated;
import 'package:app/protocol/protocol.dart' as hand;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generated Dart client protocol', () {
    test('generator output is deterministic for the app client IR', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'app_client_protocol_codegen_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final outFile = File('${tempDir.path}/protocol.g.dart');
      final result = await Process.run('node', [
        '../tools/protocol-codegen/bin/protocol-codegen.mjs',
        '--target',
        'dart',
        '--schema',
        '../tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json',
        '--out',
        outFile.path,
      ]);

      expect(
        result.exitCode,
        0,
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
      expect(
        outFile.readAsStringSync(),
        File('lib/protocol/generated/protocol.g.dart').readAsStringSync(),
      );
    });

    test('generated registry covers every current client variant', () {
      expect(generated.generatedClientMessageTypes, <String>{
        'pair_request',
        'user_message',
        'queued_message_set',
        'queued_message_clear',
        'approve_tool',
        'cancel',
        'ping',
        'session_sync',
        'session_new',
        'session_compact',
        'model_set',
        'thinking_set',
        'list_models',
      });
    });

    test('generated toJson matches handwritten client messages', () {
      final cases =
          <
            ({hand.ClientMessage handMsg, generated.ClientMessage generatedMsg})
          >[
            (
              handMsg: hand.PairRequest(
                id: 'pair-1',
                token: 'token',
                deviceName: 'phone',
              ),
              generatedMsg: const generated.PairRequest(
                id: 'pair-1',
                token: 'token',
                deviceName: 'phone',
              ),
            ),
            (
              handMsg: hand.UserMessage(
                id: 'u-1',
                sessionId: 'sess-1',
                text: 'hello',
                streamingBehavior: hand.UserMessageStreamingBehavior.steer,
                images: const [
                  hand.WireImage(data: 'aGVsbG8=', mime: 'image/jpeg'),
                ],
              ),
              generatedMsg: const generated.UserMessage(
                id: 'u-1',
                sessionId: 'sess-1',
                text: 'hello',
                streamingBehavior: generated.UserMessageStreamingBehavior.steer,
                images: [
                  generated.WireImage(data: 'aGVsbG8=', mime: 'image/jpeg'),
                ],
              ),
            ),
            (
              handMsg: hand.UserMessage(
                id: 'u-2',
                sessionId: 'sess-1',
                text: 'no optional fields',
                images: const [],
              ),
              generatedMsg: const generated.UserMessage(
                id: 'u-2',
                sessionId: 'sess-1',
                text: 'no optional fields',
                images: [],
              ),
            ),
            (
              handMsg: hand.QueuedMessageSet(
                id: 'q-1',
                sessionId: 'sess-1',
                text: 'next',
              ),
              generatedMsg: const generated.QueuedMessageSet(
                id: 'q-1',
                sessionId: 'sess-1',
                text: 'next',
              ),
            ),
            (
              handMsg: hand.QueuedMessageClear(id: 'qc-1', sessionId: 'sess-1'),
              generatedMsg: const generated.QueuedMessageClear(
                id: 'qc-1',
                sessionId: 'sess-1',
              ),
            ),
            (
              handMsg: hand.ApproveTool(
                id: 'approve-1',
                sessionId: 'sess-1',
                toolCallId: 'tool-1',
                decision: hand.ApproveDecision.allow,
              ),
              generatedMsg: const generated.ApproveTool(
                id: 'approve-1',
                sessionId: 'sess-1',
                toolCallId: 'tool-1',
                decision: generated.ApproveDecision.allow,
              ),
            ),
            (
              handMsg: hand.Cancel(
                id: 'cancel-1',
                sessionId: 'sess-1',
                targetId: 'turn-1',
              ),
              generatedMsg: const generated.Cancel(
                id: 'cancel-1',
                sessionId: 'sess-1',
                targetId: 'turn-1',
              ),
            ),
            (
              handMsg: hand.Ping(id: 'ping-1'),
              generatedMsg: const generated.Ping(id: 'ping-1'),
            ),
            (
              handMsg: hand.SessionSync(
                id: 'sync-1',
                sessionId: 'sess-1',
                limit: 25,
              ),
              generatedMsg: const generated.SessionSync(
                id: 'sync-1',
                sessionId: 'sess-1',
                limit: 25,
              ),
            ),
            (
              handMsg: hand.SessionSync(id: 'sync-2', sessionId: 'sess-1'),
              generatedMsg: const generated.SessionSync(
                id: 'sync-2',
                sessionId: 'sess-1',
              ),
            ),
            (
              handMsg: hand.SessionNew(id: 'new-1', sessionId: 'sess-1'),
              generatedMsg: const generated.SessionNew(
                id: 'new-1',
                sessionId: 'sess-1',
              ),
            ),
            (
              handMsg: hand.SessionCompact(
                id: 'compact-1',
                sessionId: 'sess-1',
              ),
              generatedMsg: const generated.SessionCompact(
                id: 'compact-1',
                sessionId: 'sess-1',
              ),
            ),
            (
              handMsg: hand.ModelSet(
                id: 'model-1',
                sessionId: 'sess-1',
                provider: 'openai',
                modelId: 'gpt-test',
              ),
              generatedMsg: const generated.ModelSet(
                id: 'model-1',
                sessionId: 'sess-1',
                provider: 'openai',
                modelId: 'gpt-test',
              ),
            ),
            (
              handMsg: hand.ThinkingSet(
                id: 'thinking-1',
                sessionId: 'sess-1',
                level: hand.ThinkingLevel.xhigh,
              ),
              generatedMsg: const generated.ThinkingSet(
                id: 'thinking-1',
                sessionId: 'sess-1',
                level: generated.ThinkingLevel.xhigh,
              ),
            ),
            (
              handMsg: hand.ListModels(id: 'models-1', sessionId: 'sess-1'),
              generatedMsg: const generated.ListModels(
                id: 'models-1',
                sessionId: 'sess-1',
              ),
            ),
          ];

      for (final pair in cases) {
        expect(
          pair.generatedMsg.toJson(),
          pair.handMsg.toJson(),
          reason:
              'generated ${pair.generatedMsg.type} matches handwritten JSON',
        );
      }
    });

    test('shared generated value types preserve wire strings and equality', () {
      expect(
        const generated.WireImage(data: 'abc', mime: 'image/png'),
        const generated.WireImage(data: 'abc', mime: 'image/png'),
      );
      expect(generated.UserMessageStreamingBehavior.steer.wireValue, 'steer');
      expect(generated.ActionName.sessionCompact.wire, 'session_compact');
      expect(generated.ThinkingLevel.xhigh.wire, 'xhigh');
      expect(
        const generated.WireModel(
          id: 'm',
          name: 'Model',
          provider: 'p',
          reasoning: true,
          contextWindow: 128,
          vision: true,
        ),
        const generated.WireModel(
          id: 'm',
          name: 'Model',
          provider: 'p',
          reasoning: true,
          contextWindow: 128,
          vision: true,
        ),
      );
    });

    test('generated client fromJson round-trips representative payloads', () {
      final payloads = <Map<String, dynamic>>[
        {'type': 'ping', 'id': 'ping-1'},
        {
          'type': 'user_message',
          'id': 'u-1',
          'session_id': 'sess-1',
          'text': 'hello',
          'streaming_behavior': 'steer',
          'images': [
            {'data': 'aGVsbG8=', 'mime': 'image/jpeg'},
          ],
        },
        {
          'type': 'thinking_set',
          'id': 'thinking-1',
          'session_id': 'sess-1',
          'level': 'xhigh',
        },
      ];

      for (final payload in payloads) {
        final decoded = generated.ClientMessage.fromJson(payload);
        expect(jsonDecode(jsonEncode(decoded.toJson())), payload);
      }
    });
  });
}
