import 'dart:convert';
import 'dart:io';

import 'package:app/protocol/generated/protocol.g.dart' as generated;
import 'package:app/protocol/protocol.dart' as hand;
import 'package:flutter_test/flutter_test.dart';

const _serverFixtureFiles = <String>{
  'action_error.jsonl',
  'action_ok.jsonl',
  'agent_message.jsonl',
  'agent_stream.jsonl',
  'bye.jsonl',
  'cancelled.jsonl',
  'compaction.jsonl',
  'error.jsonl',
  'models_list.jsonl',
  'pair_error.jsonl',
  'pair_ok.jsonl',
  'pong.jsonl',
  'queued_message_state.jsonl',
  'session_history.jsonl',
  'tool_request.jsonl',
  'tool_result.jsonl',
  'user_input.jsonl',
  'user_message.jsonl',
};

const _clientOnlyFixtureFiles = <String>{
  'approve_tool.jsonl',
  'cancel.jsonl',
  'pair_request.jsonl',
  'ping.jsonl',
  'session_sync.jsonl',
};

const _relayControlFixtureFiles = <String>{
  'peer_offline.jsonl',
  'peer_online.jsonl',
  'presence.jsonl',
  'presence_check.jsonl',
  'room_announced.jsonl',
  'room_ended.jsonl',
  'room_meta_updated.jsonl',
  'rooms.jsonl',
  'rooms_check.jsonl',
  'subscribe_presence.jsonl',
  'subscribe_rooms.jsonl',
  'unsubscribe_presence.jsonl',
  'unsubscribe_rooms.jsonl',
};

void main() {
  group('generated Dart server protocol', () {
    test('generated registry is derived from the app protocol IR', () {
      final schema =
          jsonDecode(
                File(
                  '../tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final serverUnion = (schema['unions'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((union) => union['name'] == 'ServerMessage');
      final historyUnion = (schema['unions'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((union) => union['name'] == 'SessionHistoryEvent');

      expect(
        generated.generatedServerMessageTypes,
        (serverUnion['variants'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((variant) => variant['type'] as String)
            .toSet(),
      );
      expect(
        generated.generatedSessionHistoryEventTypes,
        (historyUnion['variants'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((variant) => variant['type'] as String)
            .toSet(),
      );
    });

    test('generated server dispatch narrows every server variant', () {
      final cases = <String, Type>{
        'pair_ok': generated.PairOk,
        'pair_error': generated.PairError,
        'user_input': generated.UserInput,
        'user_message': generated.UserInput,
        'queued_message_state': generated.QueuedMessageState,
        'agent_chunk': generated.AgentChunk,
        'agent_done': generated.AgentDone,
        'agent_message': generated.AgentMessage,
        'compaction': generated.Compaction,
        'tool_request': generated.ToolRequest,
        'tool_result': generated.ToolResult,
        'error': generated.ErrorMessage,
        'cancelled': generated.Cancelled,
        'pong': generated.Pong,
        'bye': generated.Bye,
        'session_history': generated.SessionHistory,
        'action_ok': generated.ActionOk,
        'action_error': generated.ActionError,
        'models_list': generated.ModelsList,
      };

      expect(cases.keys.toSet(), generated.generatedServerMessageTypes);
      for (final entry in cases.entries) {
        final payload = _firstServerPayloadOfType(entry.key);
        final decoded = generated.ServerMessage.fromJson(payload);
        expect(
          decoded.runtimeType,
          entry.value,
          reason: '${entry.key} should narrow to ${entry.value}',
        );
      }
    });

    test('hand protocol delegates top-level narrowing to generated dispatch', () {
      expect(
        hand.ServerMessage.fromJson(_firstServerPayloadOfType('user_message')),
        isA<hand.UserInput>(),
      );
      expect(
        hand.ServerMessage.fromJson(_firstServerPayloadOfType('models_list')),
        isA<hand.ModelsList>(),
      );
      expect(
        () => hand.ServerMessage.fromJson({'type': 'future_server_type'}),
        throwsA(isA<hand.UnsupportedTypeException>()),
      );
    });

    test('generated history dispatch narrows every nested event variant', () {
      final cases = <String, Type>{
        'user_input': generated.UserInputEvt,
        'tool_request': generated.ToolRequestEvt,
        'tool_result': generated.ToolResultEvt,
        'agent_message': generated.AgentMessageEvt,
        'compaction': generated.CompactionEvt,
      };

      expect(cases.keys.toSet(), generated.generatedSessionHistoryEventTypes);
      for (final entry in cases.entries) {
        final decoded = generated.SessionHistoryEvent.fromJson(
          _historyPayloadOfType(entry.key),
        );
        expect(
          decoded.runtimeType,
          entry.value,
          reason: '${entry.key} should narrow to ${entry.value}',
        );
      }
    });

    test('unknown top-level and nested generated types reject', () {
      expect(
        () => generated.ServerMessage.fromJson({'type': 'future_type'}),
        throwsA(isA<generated.UnsupportedTypeException>()),
      );
      expect(
        () => generated.SessionHistoryEvent.fromJson({
          'type': 'future_history_type',
          'ts': 1716234601000,
        }),
        throwsA(isA<generated.UnsupportedTypeException>()),
      );
      expect(
        () => hand.SessionHistoryEvent.fromJson({
          'type': 'future_history_type',
          'ts': 1716234601000,
        }),
        throwsA(isA<hand.UnsupportedTypeException>()),
      );
    });

    test('server fixtures all decode and fixture files are classified', () {
      final fixtureDir = Directory('../.orchestration/contracts/fixtures');
      final fixtureFiles = fixtureDir
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.jsonl'))
          .toSet();
      final classifiedFiles = {
        ..._serverFixtureFiles,
        ..._clientOnlyFixtureFiles,
        ..._relayControlFixtureFiles,
      };

      expect(classifiedFiles, fixtureFiles);

      final observedServerTypes = <String>{};
      for (final fileName in _serverFixtureFiles) {
        for (final payload in _fixturePayloads(fileName)) {
          observedServerTypes.add(payload['type'] as String);
          expect(generated.ServerMessage.fromJson(payload), isA<generated.ServerMessage>());
          expect(hand.ServerMessage.fromJson(payload), isA<hand.ServerMessage>());
        }
      }
      expect(observedServerTypes, generated.generatedServerMessageTypes);

      for (final fileName in _clientOnlyFixtureFiles) {
        for (final payload in _fixturePayloads(fileName)) {
          expect(generated.ClientMessage.fromJson(payload), isA<generated.ClientMessage>());
          expect(
            () => generated.ServerMessage.fromJson(payload),
            throwsA(isA<generated.UnsupportedTypeException>()),
            reason: '$fileName is client-only, not a server message',
          );
        }
      }

      for (final fileName in _relayControlFixtureFiles) {
        for (final payload in _fixturePayloads(fileName)) {
          expect(
            () => generated.ServerMessage.fromJson(payload),
            throwsA(isA<generated.UnsupportedTypeException>()),
            reason: '$fileName is a relay-control fixture, not a server message',
          );
          expect(
            () => generated.ClientMessage.fromJson(payload),
            throwsA(isA<generated.UnsupportedTypeException>()),
            reason: '$fileName is a relay-control fixture, not a client message',
          );
        }
      }
    });
  });
}

Map<String, dynamic> _firstServerPayloadOfType(String type) {
  for (final fileName in _serverFixtureFiles) {
    for (final payload in _fixturePayloads(fileName)) {
      if (payload['type'] == type) return payload;
    }
  }
  throw StateError('No server fixture payload for type $type');
}

Map<String, dynamic> _historyPayloadOfType(String type) {
  final sessionHistory = _firstServerPayloadOfType('session_history');
  final historyEvents = sessionHistory['events'] as List<dynamic>;
  final event = historyEvents
      .cast<Map<String, dynamic>>()
      .firstWhere((event) => event['type'] == type, orElse: () => {});
  if (event.isNotEmpty) return event;

  if (type == 'compaction') {
    return {
      'ts': 1716234610000,
      'type': 'compaction',
      'summary': 'Dropped stale tool logs.',
      'tokens_before': 12000,
    };
  }
  throw StateError('No session_history fixture payload for type $type');
}

Iterable<Map<String, dynamic>> _fixturePayloads(String fileName) sync* {
  final file = File('../.orchestration/contracts/fixtures/$fileName');
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    yield jsonDecode(trimmed) as Map<String, dynamic>;
  }
}
