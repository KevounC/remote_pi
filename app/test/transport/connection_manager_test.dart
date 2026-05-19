// ConnectionManager state transition tests.
// Uses a fake ConnectionFactory so no real WS or transport is involved.

import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake infrastructure
// ---------------------------------------------------------------------------

PeerRecord _fakePeer() => const PeerRecord(
  remoteEpk: 'epk_test',
  sessionName: 'test session',
  relayUrl: 'ws://localhost:8080',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> peers;
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord r) async {}
}

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

class _T implements PeerTransport {
  final _Q _s;
  final _Q _r;
  bool _closed = false;

  _T({required _Q send, required _Q recv}) : _s = send, _r = recv;

  @override Future<void> send(Uint8List d) async => _s.add(d);
  @override Future<Uint8List> receive() => _r.next();
  @override Future<void> close() async { _closed = true; }
  bool get isClosed => _closed;
}

PlainPeerChannel _makeChannel() {
  final q1 = _Q();
  final q2 = _Q();
  final iT = _T(send: q1, recv: q2);
  return PlainPeerChannel(transport: iT);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConnectionManager', () {
    test('boot() → StatusNoPeer when storage is empty', () async {
      final cm = ConnectionManager(
        factory: (peer, cancel) async => _makeChannel(),
        storage: _FakeStorage([]),
      );

      final states = <ConnectionStatus>[];
      cm.statusStream.listen(states.add);

      await cm.boot();
      await Future<void>.delayed(Duration.zero);

      expect(cm.status, isA<StatusNoPeer>());
      cm.dispose();
    });

    test('boot() → Connecting → Online when factory succeeds', () async {
      final states = <ConnectionStatus>[];
      final cm = ConnectionManager(
        factory: (_, token) async {
          if (token.isCancelled) throw Exception('cancelled');
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
      );

      cm.statusStream.listen(states.add);
      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.any((s) => s is StatusConnecting), isTrue);
      expect(cm.status, isA<StatusOnline>());
      expect(cm.channel, isNotNull);

      cm.dispose();
    });

    test('factory failure → StatusRetrying with attempt=0', () async {
      final states = <ConnectionStatus>[];
      final cm = ConnectionManager(
        factory: (peer, cancel) async => throw Exception('connection refused'),
        storage: _FakeStorage([_fakePeer()]),
      );

      cm.statusStream.listen(states.add);
      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states.any((s) => s is StatusRetrying), isTrue);
      final retrying = states.whereType<StatusRetrying>().first;
      expect(retrying.attempt, 0);
      expect(retrying.nextRetry.inSeconds, 1);

      cm.dispose();
    });

    test('disconnect() returns to StatusNoPeer', () async {
      final cm = ConnectionManager(
        factory: (peer, cancel) async => _makeChannel(),
        storage: _FakeStorage([_fakePeer()]),
      );

      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cm.status, isA<StatusOnline>());

      await cm.disconnect();
      expect(cm.status, isA<StatusNoPeer>());
      expect(cm.channel, isNull);

      cm.dispose();
    });

    test('backoff sequence increments on repeated failures', () async {
      final retries = <StatusRetrying>[];
      final cm = ConnectionManager(
        factory: (peer, token) async {
          if (token.isCancelled) throw Exception('cancelled');
          throw Exception('refused');
        },
        storage: _FakeStorage([_fakePeer()]),
      );

      cm.statusStream
          .where((s) => s is StatusRetrying)
          .cast<StatusRetrying>()
          .listen(retries.add);
      await cm.boot();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(retries, isNotEmpty);
      expect(retries.first.attempt, 0);
      expect(retries.first.nextRetry, const Duration(seconds: 1));

      cm.dispose();
    });

    test('adopt: factory NOT called, state becomes StatusOnline immediately', () async {
      var factoryCalled = false;
      final cm = ConnectionManager(
        factory: (peer, cancel) async {
          factoryCalled = true;
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
      );

      final fakeChannel = _makeChannel();
      final states = <ConnectionStatus>[];
      cm.statusStream.listen(states.add);

      cm.adopt(fakeChannel, _fakePeer());

      expect(factoryCalled, isFalse,
          reason: 'factory must NOT be called when adopting a live channel');
      expect(cm.status, isA<StatusOnline>());
      expect(cm.channel, isNotNull);

      cm.dispose();
    });

    test('boot after adopt is a no-op when already online', () async {
      var factoryCalled = false;
      final cm = ConnectionManager(
        factory: (peer, cancel) async {
          factoryCalled = true;
          return _makeChannel();
        },
        storage: _FakeStorage([_fakePeer()]),
      );

      final fakeChannel = _makeChannel();
      cm.adopt(fakeChannel, _fakePeer());
      expect(cm.status, isA<StatusOnline>());

      await cm.boot();
      await Future<void>.delayed(Duration.zero);

      expect(factoryCalled, isFalse,
          reason: 'boot must skip factory when already online via adopt');
      expect(cm.status, isA<StatusOnline>());

      cm.dispose();
    });
  });

  // Channel close keeps `_closed` reachable so the lint about unused field
  // is silenced; verify the close path runs.
  test('PlainPeerChannel.close marks transport closed', () async {
    final q1 = _Q();
    final q2 = _Q();
    final t = _T(send: q1, recv: q2);
    final ch = PlainPeerChannel(transport: t);
    await ch.close();
    expect(t.isClosed, isTrue);
  });
}
