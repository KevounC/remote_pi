import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/ws_transport.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ws_transport — post-auth inbound demux', () {
    final envelopePayload = Uint8List.fromList([1, 2, 3, 4]);
    final envelopeCt = base64.encode(envelopePayload);

    test('returns enqueue for matching-room chat envelope', () {
      final raw = jsonEncode({
        'peer': 'peer-a',
        'room': 'active-room',
        'ct': envelopeCt,
      });

      final decision = demuxPostAuthInboundFrame(
        raw: raw,
        activeRoom: 'active-room',
      );

      expect(decision.kind, WsInboundFrameKind.enqueue);
      expect(decision.envelopeBytes, envelopePayload);
    });

    test('returns dropMissingRoom for envelope without room', () {
      final raw = jsonEncode({'peer': 'peer-a', 'ct': envelopeCt});

      final decision = demuxPostAuthInboundFrame(
        raw: raw,
        activeRoom: 'active-room',
      );

      expect(decision.kind, WsInboundFrameKind.dropMissingRoom);
      expect(decision.envelopeBytes, isNull);
    });

    test('returns dropRoomMismatch when room does not match active room', () {
      final raw = jsonEncode({
        'peer': 'peer-a',
        'room': 'other-room',
        'ct': envelopeCt,
      });

      final decision = demuxPostAuthInboundFrame(
        raw: raw,
        activeRoom: 'active-room',
      );

      expect(decision.kind, WsInboundFrameKind.dropRoomMismatch);
      expect(decision.senderRoom, 'other-room');
    });

    test('returns control for control frames on the control stream', () {
      final raw = jsonEncode({'type': 'peer_online', 'peer': 'peer-a'});

      final decision = demuxPostAuthInboundFrame(
        raw: raw,
        activeRoom: 'active-room',
      );

      expect(decision.kind, WsInboundFrameKind.control);
      expect(decision.controlType, 'peer_online');
      expect(decision.control, isA<PeerOnline>());
    });

    test('returns dropMalformed for malformed envelope payloads', () {
      final decision = demuxPostAuthInboundFrame(
        raw: 'not-json',
        activeRoom: 'active-room',
      );

      expect(decision.kind, WsInboundFrameKind.dropMalformed);
      expect(decision.error, isNotNull);
      expect(decision.envelopeBytes, isNull);
    });
  });
}
