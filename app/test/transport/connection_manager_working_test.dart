// Plan/32 — ConnectionManager propagates `meta.working` from
// `room_announced` / `room_meta_updated` / `rooms` into RoomInfo.working and
// exposes it via `isRoomWorking`, so Home can show the blue "working" dot for
// EVERY subscribed room (not just the single connected one).

import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

PeerRecord _fakePeer() => const PeerRecord(
  remoteEpk: 'epk_test',
  sessionName: 'pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> peers;
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord r) async {}

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {}

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async => const [];

  @override
  Future<void> deleteRooms(String epk) async {}
}

class _ControllableChannel implements IChannel, IControlLink {
  final _serverCtrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _serverCtrl.stream;

  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  void sendControl(Map<String, dynamic> json) {}

  @override
  Future<void> close() async {
    await _serverCtrl.close();
    await _controlCtrl.close();
  }

  void pushControl(ControlInbound m) => _controlCtrl.add(m);

  void pushServer(ServerMessage m) => _serverCtrl.add(m);

  // Avoid analyzer "unused" on the import.
  // ignore: unused_element
  Uint8List _placeholder() => Uint8List(0);
}

Future<ConnectionManager> _connected(_ControllableChannel ch) async {
  final cm = ConnectionManager(
    factory: (_, _) async => ch,
    storage: _FakeStorage([_fakePeer()]),
    emitDebounce: Duration.zero,
  );
  await cm.connectTo(_fakePeer());
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return cm;
}

void main() {
  group('ConnectionManager — Plan/32 working propagation', () {
    test(
      'RoomAnnounced with working seeds RoomInfo.working + isRoomWorking',
      () async {
        final ch = _ControllableChannel();
        final cm = await _connected(ch);

        ch.pushControl(
          const RoomAnnounced(
            peer: 'epk_test',
            roomId: 'r1',
            startedAt: 1,
            working: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(cm.roomsFor('epk_test').single.working, isTrue);
        expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);

        cm.dispose();
      },
    );

    test('room_meta_updated flips working on then off', () async {
      final ch = _ControllableChannel();
      final cm = await _connected(ch);

      ch.pushControl(
        const RoomAnnounced(
          peer: 'epk_test',
          roomId: 'r1',
          startedAt: 1,
          model: 'claude-opus-4-8',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);

      // turn_start → working=true
      ch.pushControl(
        const RoomMetaUpdated(
          peer: 'epk_test',
          roomId: 'r1',
          working: true,
          hasModel: false,
          hasThinking: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);
      expect(
        cm.roomsFor('epk_test').single.model,
        'claude-opus-4-8',
        reason: 'working-only update must NOT clobber model',
      );

      // turn_end → working=false
      ch.pushControl(
        const RoomMetaUpdated(
          peer: 'epk_test',
          roomId: 'r1',
          working: false,
          hasModel: false,
          hasThinking: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);

      cm.dispose();
    });

    test('model-only update preserves a previously-set working=true', () async {
      final ch = _ControllableChannel();
      final cm = await _connected(ch);

      ch.pushControl(
        const RoomAnnounced(
          peer: 'epk_test',
          roomId: 'r1',
          startedAt: 1,
          working: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // A model swap mid-turn: meta carries model only, working absent.
      ch.pushControl(
        const RoomMetaUpdated(
          peer: 'epk_test',
          roomId: 'r1',
          model: 'gpt-4o',
          hasModel: true,
          hasThinking: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        cm.isRoomWorking('epk_test', 'r1'),
        isTrue,
        reason: 'absent working in a meta update must not clear it',
      );
      expect(cm.roomsFor('epk_test').single.model, 'gpt-4o');

      cm.dispose();
    });

    test('rooms snapshot carries working per room', () async {
      final ch = _ControllableChannel();
      final cm = await _connected(ch);

      ch.pushControl(
        const RoomsSnapshot(
          peer: 'epk_test',
          rooms: [
            RoomInfo(roomId: 'r1', startedAt: 1, working: true),
            RoomInfo(roomId: 'r2', startedAt: 1, working: false),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);
      expect(cm.isRoomWorking('epk_test', 'r2'), isFalse);

      cm.dispose();
    });

    test('room_ended clears cached working and projects stale', () async {
      final ch = _ControllableChannel();
      final cm = await _connected(ch);

      ch.pushControl(
        const RoomAnnounced(
          peer: 'epk_test',
          roomId: 'r1',
          startedAt: 1,
          working: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);

      ch.pushControl(
        const RoomEnded(peer: 'epk_test', roomId: 'r1', sinceTs: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        cm.roomTurnProjection('epk_test', 'r1').status,
        AppTurnStatus.stale,
      );
      expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);
      expect(cm.roomsFor('epk_test').single.working, isFalse);

      cm.dispose();
    });

    test(
      'room missing from rooms snapshot clears working and projects stale',
      () async {
        final ch = _ControllableChannel();
        final cm = await _connected(ch);

        ch.pushControl(
          const RoomAnnounced(
            peer: 'epk_test',
            roomId: 'r1',
            startedAt: 1,
            working: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);

        ch.pushControl(
          const RoomsSnapshot(
            peer: 'epk_test',
            rooms: [RoomInfo(roomId: 'r2', startedAt: 2, working: false)],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(
          cm.roomTurnProjection('epk_test', 'r1').status,
          AppTurnStatus.stale,
        );
        expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);
        expect(
          cm.roomsFor('epk_test').singleWhere((r) => r.roomId == 'r1').working,
          isFalse,
        );

        cm.dispose();
      },
    );

    test(
      'late attach hydrates working true then terminal false without history reviving room working',
      () async {
        final ch = _ControllableChannel();
        final cm = await _connected(ch);

        ch.pushControl(
          const RoomAnnounced(
            peer: 'epk_test',
            roomId: 'r1',
            startedAt: 1,
            working: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);

        ch.pushControl(
          const RoomMetaUpdated(
            peer: 'epk_test',
            roomId: 'r1',
            working: false,
            hasModel: false,
            hasThinking: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);
        expect(
          cm.roomTurnProjection('epk_test', 'r1').status,
          AppTurnStatus.idle,
        );

        ch.pushServer(
          const SessionHistory(
            inReplyTo: 'turn-1',
            sessionStartedAt: 1,
            events: [AgentMessageEvt(ts: 2, inReplyTo: 'turn-1', text: 'done')],
            eos: true,
            truncated: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);
        expect(
          cm.roomTurnProjection('epk_test', 'r1').status,
          AppTurnStatus.idle,
        );

        cm.dispose();
      },
    );

    test('isRoomWorking is false when the WS is offline', () async {
      final ch = _ControllableChannel();
      final cm = await _connected(ch);

      ch.pushControl(
        const RoomAnnounced(
          peer: 'epk_test',
          roomId: 'r1',
          startedAt: 1,
          working: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);

      // Dropping the connection → no fresh signal → report not-working.
      await cm.disconnect();
      expect(
        cm.roomTurnProjection('epk_test', 'r1').status,
        AppTurnStatus.stale,
      );
      expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);

      cm.dispose();
    });
  });
}
