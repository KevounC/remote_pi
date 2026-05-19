// Tests for Ed25519 device singleton in PairingStorage.

import 'dart:convert';

import 'package:app/pairing/storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake FlutterSecureStorage backed by a map
// ---------------------------------------------------------------------------

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.from(_store);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.clear();

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PairingStorage — device Ed25519 key', () {
    late PairingStorage storage;
    late _FakeSecureStorage fakeStore;

    setUp(() {
      fakeStore = _FakeSecureStorage();
      storage = PairingStorage(fakeStore);
    });

    test('generates key on first call', () async {
      final identity = await storage.loadOrCreateDeviceEd25519Key();
      expect(identity.pk, isNotEmpty);
      expect(identity.sk, isNotEmpty);
      expect(() => base64Url.decode(_pad(identity.pk)), returnsNormally);
      expect(() => base64Url.decode(_pad(identity.sk)), returnsNormally);
    });

    test('returns same key on second call (persisted)', () async {
      final id1 = await storage.loadOrCreateDeviceEd25519Key();
      final id2 = await storage.loadOrCreateDeviceEd25519Key();
      expect(id1.pk, id2.pk);
      expect(id1.sk, id2.sk);
    });

    test('different storage instance loads same key', () async {
      final id1 = await storage.loadOrCreateDeviceEd25519Key();
      final storage2 = PairingStorage(fakeStore);
      final id2 = await storage2.loadOrCreateDeviceEd25519Key();
      expect(id1.pk, id2.pk);
    });

    test('pk is 32 bytes (Ed25519 pubkey)', () async {
      final identity = await storage.loadOrCreateDeviceEd25519Key();
      final pkBytes = base64Url.decode(_pad(identity.pk));
      expect(pkBytes.length, 32);
    });
  });

  group('PeerRecord — minimal post-rollback shape', () {
    test('serializes and deserializes the 4 retained fields', () {
      const record = PeerRecord(
        remoteEpk: 'pk_ed25519',
        sessionName: 'test',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      );

      final json = record.toJson();
      expect(json['remote_epk'], 'pk_ed25519');
      expect(json['session_name'], 'test');
      expect(json['relay_url'], 'ws://localhost');
      expect(json['paired_at'], '2026-01-01T00:00:00Z');

      final restored = PeerRecord.fromJson(json);
      expect(restored.remoteEpk, 'pk_ed25519');
      expect(restored.sessionName, 'test');
    });

    test('list/save/load round-trips through fake storage', () async {
      final storage = PairingStorage(_FakeSecureStorage());
      const r = PeerRecord(
        remoteEpk: 'epk1',
        sessionName: 'sess',
        relayUrl: 'ws://x',
        pairedAt: '2026-01-01T00:00:00Z',
      );
      await storage.savePeer(r);

      final loaded = await storage.loadPeer('epk1');
      expect(loaded?.sessionName, 'sess');

      final all = await storage.listPeers();
      expect(all, hasLength(1));

      await storage.deletePeer('epk1');
      expect(await storage.listPeers(), isEmpty);
    });
  });
}

String _pad(String s) {
  final p = (4 - s.length % 4) % 4;
  return s + '=' * p;
}
