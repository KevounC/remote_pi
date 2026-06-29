import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/main.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> peers;
  final Map<String, List<PersistedRoom>> _roomsByEpk = {};

  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord record) async {
    peers.removeWhere((p) => p.remoteEpk == record.remoteEpk);
    peers.add(record);
  }

  @override
  Future<void> saveRooms(String remoteEpk, List<PersistedRoom> rooms) async {
    _roomsByEpk[remoteEpk] = rooms;
  }

  @override
  Future<List<PersistedRoom>> loadRooms(String remoteEpk) async =>
      _roomsByEpk[remoteEpk] ?? const [];

  @override
  Future<void> deleteRooms(String remoteEpk) async {
    _roomsByEpk.remove(remoteEpk);
  }
}

class _TrackingChannel implements IChannel, IControlLink {
  final _server = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();
  final List<Map<String, dynamic>> sentControl = [];

  @override
  Stream<ServerMessage> get serverMessages => _server.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() async {
    if (!_server.isClosed) await _server.close();
    if (!_control.isClosed) await _control.close();
  }

  @override
  Stream<ControlInbound> get controlFrames => _control.stream;

  @override
  void sendControl(Map<String, dynamic> json) {
    sentControl.add(json);
  }
}

class _FakeSyncService {
  int sessionSyncCalls = 0;

  void requestSync() {
    sessionSyncCalls += 1;
  }
}

void main() {
  test(
    'resume on online cached state replays subscriptions and requests sync',
    () async {
      final peers = <PeerRecord>[
        const PeerRecord(
          remoteEpk: 'peer_A',
          sessionName: 'pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
        ),
      ];
      final channel = _TrackingChannel();
      final storage = _FakeStorage(peers);
      final connectionManager = ConnectionManager(
        factory: (_, _) async => throw StateError('not expected'),
        storage: storage,
        emitDebounce: Duration.zero,
      );
      final sync = _FakeSyncService();

      connectionManager.adopt(channel, peers.single);

      await reconcileOnAppResume(
        connectionManager: connectionManager,
        requestSessionSync: sync.requestSync,
      );

      final controlTypes = channel.sentControl.map((m) => m['type']).toList();
      expect(controlTypes, contains('subscribe_presence'));
      expect(controlTypes, contains('subscribe_rooms'));
      expect(controlTypes, contains('presence_check'));
      expect(controlTypes, contains('rooms_check'));
      expect(sync.sessionSyncCalls, equals(1));

      connectionManager.dispose();
    },
  );
}
