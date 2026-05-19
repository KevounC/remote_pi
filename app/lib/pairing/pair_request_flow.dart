// PairRequest flow — replaces the Noise XX handshake removed by plan 06.
//
// Sequence (over a connected PeerTransport):
//   1. App sends inner JSON {type:"pair_request", id, token, device_name}
//   2. Pi validates token, persists peer, replies pair_ok | pair_error
//   3. App persists PeerRecord on success
//
// No cipher, no safety number — the outer envelope's `ct` is base64 of
// the JSON in plaintext (transparent to PeerTransport implementations).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'qr_scanner.dart';
import 'storage.dart';

// ---------------------------------------------------------------------------
// PeerTransport — minimal byte-level interface (was NoiseTransport pre-rollback)
// ---------------------------------------------------------------------------

abstract class PeerTransport {
  Future<void> send(Uint8List data);
  Future<Uint8List> receive();
  Future<void> close();
}

// ---------------------------------------------------------------------------
// PairingError
// ---------------------------------------------------------------------------

class PairingError implements Exception {
  final String code;
  final String message;
  const PairingError({required this.code, required this.message});

  @override
  String toString() => 'PairingError($code): $message';
}

// ---------------------------------------------------------------------------
// performPairing
// ---------------------------------------------------------------------------

Future<PeerRecord> performPairing({
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  required String deviceName,
}) async {
  final id = _uuid7();
  final req = {
    'type': 'pair_request',
    'id': id,
    'token': qr.token,
    'device_name': deviceName,
  };
  await transport.send(Uint8List.fromList(utf8.encode(jsonEncode(req))));

  final raw = await transport.receive();
  final inner = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  final type = inner['type'] as String?;

  if (type == 'pair_ok' && inner['in_reply_to'] == id) {
    final peer = PeerRecord(
      remoteEpk: qr.epk,
      sessionName: inner['session_name'] as String,
      relayUrl: qr.relayUrl,
      pairedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await storage.savePeer(peer);
    return peer;
  }

  if (type == 'pair_error') {
    throw PairingError(
      code: inner['code'] as String,
      message: inner['message'] as String? ?? '',
    );
  }

  throw PairingError(
    code: 'unexpected_response',
    message: 'Unknown response type: $type',
  );
}

// ---------------------------------------------------------------------------
// UUIDv7 — random-based, sufficient for inner correlation IDs.
// Layout: 48-bit unix_ts_ms | ver=7 | 12-bit rand_a | variant=10 | 62-bit rand_b
// ---------------------------------------------------------------------------

final _rng = Random.secure();

String _uuid7() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final bytes = Uint8List(16);

  bytes[0] = (ms >> 40) & 0xff;
  bytes[1] = (ms >> 32) & 0xff;
  bytes[2] = (ms >> 24) & 0xff;
  bytes[3] = (ms >> 16) & 0xff;
  bytes[4] = (ms >> 8) & 0xff;
  bytes[5] = ms & 0xff;

  for (var i = 6; i < 16; i++) {
    bytes[i] = _rng.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant

  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
