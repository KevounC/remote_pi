import 'package:cockpit/app/cockpit/data/adapters/rpc_event_mapper.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = RpcEventMapper();

  group('RpcEventMapper cockpit control overlay', () {
    test('maps existing relay-state payload without changing fields', () {
      final event = mapper.fromJson(
        _customMessage('remote-pi:relay-state', <String, Object?>{
          'status': 'connected',
          'connected': true,
          'relayUrl': 'https://relay.example',
          'room': 'main',
        }),
      );

      expect(event, isA<RpcRelayState>());
      final relayState = event as RpcRelayState;
      expect(relayState.status, RelayStatus.connected);
      expect(relayState.connected, isTrue);
      expect(relayState.relayUrl, 'https://relay.example');
      expect(relayState.room, 'main');
    });

    test('maps existing name-assigned payload without changing fields', () {
      final event = mapper.fromJson(
        _customMessage('remote-pi:name-assigned', <String, Object?>{
          'requested': 'desk-agent',
          'assigned': 'desk-agent#2',
          'changed': true,
        }),
      );

      expect(event, isA<RpcNameAssigned>());
      final nameAssigned = event as RpcNameAssigned;
      expect(nameAssigned.requested, 'desk-agent');
      expect(nameAssigned.assigned, 'desk-agent#2');
      expect(nameAssigned.changed, isTrue);
    });

    test('maps pair-code, paired, and mesh-revoked schema neighbors', () {
      final pairCode = mapper.fromJson(
        _customMessage('remote-pi:pair-code', <String, Object?>{
          'uri': 'remote-pi://pair?token=abc',
          'token': 'abc',
          'expiresAt': 1760000000000,
          'roomId': 'main',
          'name': 'desk-agent',
        }),
      );
      expect(pairCode, isA<RpcPairCode>());
      final pairCodeEvent = pairCode as RpcPairCode;
      expect(pairCodeEvent.uri, 'remote-pi://pair?token=abc');
      expect(pairCodeEvent.token, 'abc');
      expect(pairCodeEvent.expiresAt, 1760000000000);
      expect(pairCodeEvent.roomId, 'main');
      expect(pairCodeEvent.name, 'desk-agent');

      final paired = mapper.fromJson(
        _customMessage('remote-pi:paired', <String, Object?>{
          'name': 'Phone',
          'peerId': 'owner-peer',
          'pairedAt': 1760000000001,
        }),
      );
      expect(paired, isA<RpcPaired>());
      final pairedEvent = paired as RpcPaired;
      expect(pairedEvent.name, 'Phone');
      expect(pairedEvent.peerId, 'owner-peer');
      expect(pairedEvent.pairedAt, 1760000000001);

      final pairedWithoutSchemaDetails = mapper.fromJson(
        _customMessage('remote-pi:paired', <String, Object?>{}),
      );
      expect(pairedWithoutSchemaDetails, isA<RpcUnknown>());
      expect(
        (pairedWithoutSchemaDetails as RpcUnknown).type,
        'message_start:paired:invalid-details',
      );

      final meshRevoked = mapper.fromJson(
        _customMessage('remote-pi:mesh-revoked', null),
      );
      expect(meshRevoked, isA<RpcMeshRevoked>());
      expect((meshRevoked as RpcMeshRevoked).details, isNull);
    });

    test('keeps unknown custom event types isolated as RpcUnknown', () {
      final event = mapper.fromJson(
        _customMessage('remote-pi:future-event', <String, Object?>{
          'newField': 'kept raw by pi but ignored by cockpit',
        }),
      );

      expect(event, isA<RpcUnknown>());
      expect(
        (event as RpcUnknown).type,
        'message_start:custom:remote-pi:future-event',
      );
    });
  });
}

Map<String, dynamic> _customMessage(
  String customType,
  Map<String, Object?>? details,
) {
  final message = <String, dynamic>{
    'role': 'custom',
    'customType': customType,
    'content': '',
  };
  if (details != null) message['details'] = details;
  return <String, dynamic>{'type': 'message_start', 'message': message};
}
