import 'dart:convert';
import 'dart:io';

import 'package:app/protocol/codec.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decode fixtures', () {
    final fixtureDir = Directory('../.orchestration/contracts/fixtures');

    test('fixture directory exists', () {
      expect(fixtureDir.existsSync(), isTrue,
          reason: 'fixtures dir not found at ${fixtureDir.path}');
    });

    test('all fixture lines parse or throw UnsupportedTypeException', () {
      final files = fixtureDir.listSync().whereType<File>().toList();
      expect(files, isNotEmpty, reason: 'no fixture files found');

      for (final file in files) {
        final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
        for (final line in lines) {
          try {
            final msg = decodeServer(line);
            expect(msg, isNotNull);
          } on UnsupportedTypeException {
            // client-only types (user_message, approve_tool, etc.) — expected
          }
        }
      }
    });
  });

  group('AgentChunk', () {
    test('parses in_reply_to and delta', () {
      final msg = ServerMessage.fromJson({
        'type': 'agent_chunk',
        'in_reply_to': '018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6e',
        'delta': 'Vou olhar o ',
      });

      expect(msg, isA<AgentChunk>());
      final chunk = msg as AgentChunk;
      expect(chunk.inReplyTo, '018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6e');
      expect(chunk.delta, 'Vou olhar o ');
    });
  });

  group('AgentDone', () {
    test('parses usage', () {
      final msg = ServerMessage.fromJson({
        'type': 'agent_done',
        'in_reply_to': 'x',
        'usage': {'input_tokens': 120, 'output_tokens': 340},
      });
      final done = msg as AgentDone;
      expect(done.usage!.inputTokens, 120);
      expect(done.usage!.outputTokens, 340);
    });

    test('usage is optional', () {
      final msg = ServerMessage.fromJson({
        'type': 'agent_done',
        'in_reply_to': 'x',
      });
      expect((msg as AgentDone).usage, isNull);
    });
  });

  group('ToolRequest', () {
    test('parses tool_call_id, tool, args', () {
      final msg = ServerMessage.fromJson({
        'type': 'tool_request',
        'tool_call_id': 'tc_018f9c2b',
        'tool': 'Bash',
        'args': {'command': 'rm -rf node_modules'},
      });
      final req = msg as ToolRequest;
      expect(req.toolCallId, 'tc_018f9c2b');
      expect(req.tool, 'Bash');
    });
  });

  group('ToolResult', () {
    test('parses result', () {
      final msg = ServerMessage.fromJson({
        'type': 'tool_result',
        'tool_call_id': 'tc_1',
        'result': {'exit_code': 0},
      });
      expect((msg as ToolResult).toolCallId, 'tc_1');
      expect(msg.error, isNull);
    });

    test('parses error field', () {
      final msg = ServerMessage.fromJson({
        'type': 'tool_result',
        'tool_call_id': 'tc_2',
        'error': 'command timed out after 60s',
      });
      expect((msg as ToolResult).error, 'command timed out after 60s');
      expect(msg.result, isNull);
    });
  });

  group('UnsupportedTypeException', () {
    test('thrown for unknown type', () {
      expect(
        () => ServerMessage.fromJson({'type': 'future_type'}),
        throwsA(isA<UnsupportedTypeException>()),
      );
    });

    test('thrown for null type', () {
      expect(
        () => ServerMessage.fromJson({'data': 1}),
        throwsA(isA<UnsupportedTypeException>()),
      );
    });
  });

  group('Pair messages', () {
    test('PairOk fixture parses', () {
      final file = File('../.orchestration/contracts/fixtures/pair_ok.jsonl');
      final line = file.readAsLinesSync().firstWhere((l) => l.trim().isNotEmpty);
      final msg = decodeServer(line) as PairOk;
      expect(msg.inReplyTo, isNotEmpty);
      expect(msg.sessionName, contains('remote_pi'));
    });

    test('PairError fixture parses', () {
      final file = File('../.orchestration/contracts/fixtures/pair_error.jsonl');
      final line = file.readAsLinesSync().firstWhere((l) => l.trim().isNotEmpty);
      final msg = decodeServer(line) as PairError;
      expect(msg.code, isNotEmpty);
      expect(msg.message, isNotEmpty);
    });

    test('PairRequest encodes correctly', () {
      final msg = PairRequest(
        id: '018f9c3a-0000-7000-9a3b-1c2d3e4f5a01',
        token: 'qBcD3fG4h5J6k7L8m9N0pQ',
        deviceName: 'iPhone do Jacob',
      );
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'pair_request');
      expect(decoded['device_name'], 'iPhone do Jacob');
      expect(decoded['token'], 'qBcD3fG4h5J6k7L8m9N0pQ');
    });
  });

  group('encodeClient', () {
    test('UserMessage roundtrip', () {
      final msg = UserMessage(id: 'test-id-1', text: 'hello world');
      final line = encodeClient(msg);
      expect(line, endsWith('\n'));
      final decoded = jsonDecode(line.trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'user_message');
      expect(decoded['id'], 'test-id-1');
      expect(decoded['text'], 'hello world');
    });

    test('ApproveTool encodes decision as string', () {
      final msg = ApproveTool(
        id: 'x',
        toolCallId: 'tc_1',
        decision: ApproveDecision.allow,
      );
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['decision'], 'allow');
      expect(decoded['tool_call_id'], 'tc_1');
    });

    test('Ping encodes correctly', () {
      final msg = Ping(id: 'ping-id');
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'ping');
      expect(decoded['id'], 'ping-id');
    });

    test('Cancel encodes target_id', () {
      final msg = Cancel(id: 'c1', targetId: 'target-x');
      final decoded =
          jsonDecode(encodeClient(msg).trim()) as Map<String, dynamic>;
      expect(decoded['type'], 'cancel');
      expect(decoded['target_id'], 'target-x');
    });
  });
}
