import 'dart:convert';

import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PiRpcProcess cockpit control serialization', () {
    test(
      'emits relay controls as schema envelopes on the prompt transport',
      () {
        final prompt = schemaControlPromptForTesting(
          PiControlCommand.relay(PiRelayControlAction.status),
        );

        expect(prompt['type'], 'prompt');
        expect(prompt['message'], isA<String>());
        expect(prompt['message'], isNot(contains('\u0000remote-pi-ctrl:')));

        final envelope = jsonDecode(prompt['message'] as String);
        expect(envelope, <String, Object>{
          'type': 'remote_pi_control',
          'command': 'relay_status',
        });
      },
    );

    test('emits rename controls with the schema name argument', () {
      final prompt = schemaControlPromptForTesting(
        PiControlCommand.rename('  desk-agent  '),
      );

      final envelope = jsonDecode(prompt['message'] as String);
      expect(envelope, <String, Object>{
        'type': 'remote_pi_control',
        'command': 'rename',
        'name': 'desk-agent',
      });
    });
  });
}
