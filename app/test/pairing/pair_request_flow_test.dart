import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _Q {
  final _buf = <Uint8List>[];
  final _wait = <Completer<Uint8List>>[];
  void add(Uint8List d) {
    if (_wait.isNotEmpty) {
      _wait.removeAt(0).complete(d);
    } else {
      _buf.add(d);
    }
  }
  Future<Uint8List> next() {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    final c = Completer<Uint8List>();
    _wait.add(c);
    return c.future;
  }
}

class _MemTransport implements PeerTransport {
  final _Q _s;
  final _Q _r;
  _MemTransport({required _Q send, required _Q recv}) : _s = send, _r = recv;
  @override
  Future<void> send(Uint8List d) async => _s.add(d);
  @override
  Future<Uint8List> receive() => _r.next();
  @override
  Future<void> close() async {}
}

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> saved = [];

  @override
  Future<List<PeerRecord>> listPeers() async => saved;

  @override
  Future<void> savePeer(PeerRecord r) async => saved.add(r);

  @override
  Future<DeviceIdentity> loadOrCreateDeviceEd25519Key() async {
    final kp = await Ed25519().newKeyPair();
    final pub = await kp.extractPublicKey();
    return DeviceIdentity(pk: base64Url.encode(pub.bytes), sk: 'x');
  }
}

QrPairPayload _qr({String? relayUrl}) => QrPairPayload(
      token: 'AAAAAAAAAAAAAAAAAAAAAA',
      epk: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionName: 'Pi',
      relayUrl: relayUrl,
    );

void main() {
  group('performPairing — relay mismatch (plan 14)', () {
    test(
      'throws PairingError(relay_mismatch) when qr.relayUrl differs '
      'from currentRelayUrl',
      () async {
        final q1 = _Q();
        final q2 = _Q();
        final transport = _MemTransport(send: q1, recv: q2);
        final qr = _qr(relayUrl: 'wss://other-relay.example');

        await expectLater(
          performPairing(
            qr: qr,
            transport: transport,
            storage: _FakeStorage(),
            deviceName: 'phone',
            currentRelayUrl: 'wss://my-relay.example',
          ),
          throwsA(
            isA<PairingError>().having(
              (e) => e.code,
              'code',
              'relay_mismatch',
            ),
          ),
        );
      },
    );

    test(
      'proceeds when qr.relayUrl matches currentRelayUrl (legacy QR)',
      () async {
        final q1 = _Q();
        final q2 = _Q();
        final pi = _MemTransport(send: q1, recv: q2);
        final app = _MemTransport(send: q2, recv: q1);
        final qr = _qr(relayUrl: 'ws://localhost');
        final storage = _FakeStorage();

        // Pi-side responder.
        unawaited(() async {
          final raw = await pi.receive();
          final req = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
          await pi.send(Uint8List.fromList(utf8.encode(jsonEncode({
            'type': 'pair_ok',
            'in_reply_to': req['id'],
            'session_name': 'Pi',
          }))));
        }());

        final peer = await performPairing(
          qr: qr,
          transport: app,
          storage: storage,
          deviceName: 'phone',
          currentRelayUrl: 'ws://localhost',
        );
        expect(peer.sessionName, 'Pi');
        expect(peer.relayUrl, 'ws://localhost');
        expect(storage.saved, hasLength(1));
      },
    );

    test(
      'proceeds when qr.relayUrl is null (new-format QR) — saves '
      'currentRelayUrl on the PeerRecord',
      () async {
        final q1 = _Q();
        final q2 = _Q();
        final pi = _MemTransport(send: q1, recv: q2);
        final app = _MemTransport(send: q2, recv: q1);
        final qr = _qr();
        final storage = _FakeStorage();

        unawaited(() async {
          final raw = await pi.receive();
          final req = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
          await pi.send(Uint8List.fromList(utf8.encode(jsonEncode({
            'type': 'pair_ok',
            'in_reply_to': req['id'],
            'session_name': 'Pi',
          }))));
        }());

        final peer = await performPairing(
          qr: qr,
          transport: app,
          storage: storage,
          deviceName: 'phone',
          currentRelayUrl: 'wss://relay.remote-pi.dev',
        );
        expect(peer.relayUrl, 'wss://relay.remote-pi.dev',
            reason: 'when QR lacks r=, persist currentRelayUrl');
      },
    );
  });
}
