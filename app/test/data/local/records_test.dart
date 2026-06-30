// Plan/31 — record roundtrips + volatile runtime wipe on boot.

import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/domain/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('record roundtrips', () {
    test('MessageRecord (user + image) survives toJson/fromJson', () {
      final r = MessageRecord(
        id: 'u1',
        seq: 3,
        role: MsgRole.user,
        text: 'hello',
        image: const MessageImage(data: 'QUJD', mime: 'image/jpeg'),
        ts: DateTime.fromMillisecondsSinceEpoch(1700),
        pending: true,
      );
      final back = MessageRecord.fromJson(r.toJson());
      expect(back.id, 'u1');
      expect(back.seq, 3);
      expect(back.role, MsgRole.user);
      expect(back.text, 'hello');
      expect(back.image?.data, 'QUJD');
      expect(back.pending, isTrue);
      // Projects to the domain UserMsg the UI renders.
      final msg = back.toChatMessage() as UserMsg;
      expect(msg.status, UserMsgStatus.pending);
      expect(msg.image, isNotNull);
    });

    test('MessageRecord (tool) survives roundtrip', () {
      final r = MessageRecord(
        id: 'tc1',
        seq: 0,
        role: MsgRole.tool,
        ts: DateTime.fromMillisecondsSinceEpoch(1),
        tool: const ToolEventData(
          toolCallId: 'tc1',
          tool: 'Bash',
          args: {'cmd': 'ls'},
          status: ToolEventStatus.completed,
          result: {'exit': 0},
        ),
      );
      final back = MessageRecord.fromJson(r.toJson());
      expect(back.tool?.tool, 'Bash');
      expect(back.tool?.status, ToolEventStatus.completed);
      final evt = back.toChatMessage() as ToolEvent;
      expect(evt.toolCallId, 'tc1');
      expect(evt.status, ToolEventStatus.completed);
    });

    test('SessionIndexRecord survives roundtrip', () {
      final r = SessionIndexRecord(
        epk: 'epk1',
        roomId: 'main',
        sessionId: 'session-1',
        displayName: 'proj',
        status: SessionActivity.working,
        lastMessageAt: DateTime.fromMillisecondsSinceEpoch(99),
        lastMessagePreview: 'hi',
        sessionStartedAt: DateTime.fromMillisecondsSinceEpoch(10),
      );
      final back = SessionIndexRecord.fromJson(r.toJson());
      expect(back, r);
      expect(back.key, 'epk1:main:session-1');
      expect(back.status, SessionActivity.working);
    });

    test('legacy SessionIndexRecord without session_id is rejected', () {
      final legacy = {'epk': 'epk1', 'room_id': 'main', 'status': 'working'};
      expect(SessionIndexRecord.tryFromJson(legacy), isNull);
      expect(
        () => SessionIndexRecord.fromJson(legacy),
        throwsA(isA<FormatException>()),
      );
    });

    test('RuntimeRecord survives roundtrip', () {
      const r = RuntimeRecord(
        connection: RuntimeConnection.online,
        presence: RuntimePresence.alive,
      );
      final back = RuntimeRecord.fromJson(r.toJson());
      expect(back, r);
    });
  });

  group('volatile runtime wipe (#3)', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('rp_v2_wipe_');
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('runtime box opens EMPTY after a simulated restart', () async {
      await LocalBoxes.initForTest(dir.path);
      final boxes = LocalBoxes();
      // Seed runtime as if a prior run left an "online" record.
      await boxes.runtimeBox().put(
        'epk1:main',
        const RuntimeRecord(connection: RuntimeConnection.online).toJson(),
      );
      expect(boxes.runtimeBox().isEmpty, isFalse);

      // "Restart": re-init wipes the volatile box.
      await LocalBoxes.initForTest(dir.path);
      expect(
        boxes.runtimeBox().isEmpty,
        isTrue,
        reason: 'runtime must never survive a boot (#3)',
      );
    });
  });
}
