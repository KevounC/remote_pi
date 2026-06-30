// Plan/31 — read repos project the DB reactively. Write to a box → the watch
// stream emits the updated list (incremental projection).

import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/repositories/home_read_repository.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

int _c = 0;
late Directory _dir;

MessageRecord _msg(int seq, String id, String text) => MessageRecord(
  id: id,
  seq: seq,
  role: MsgRole.user,
  text: text,
  ts: DateTime.fromMillisecondsSinceEpoch(seq + 1),
);

void main() {
  setUpAll(() async {
    _dir = Directory.systemTemp.createTempSync('rp_v2_read_');
    await LocalBoxes.initForTest(_dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await _dir.delete(recursive: true);
  });

  test(
    'watchMessages emits the current snapshot then updates on write',
    () async {
      final boxes = LocalBoxes();
      final repo = SessionReadRepository(boxes);
      final epk = 'epk_read_${++_c}';
      final ref = RemoteSessionRef(
        peerEpk: epk,
        roomId: 'main',
        sessionId: 'session-a',
      );
      final box = await boxes.msgsBox(ref);
      await box.put(0, _msg(0, 'a', 'first').toJson());

      final stream = repo.watchMessages(ref);
      final emissions = <List<MessageRecord>>[];
      final sub = stream.listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, hasLength(1));
      expect(emissions.last.first.text, 'first');

      // Incremental update: a single new row → next emit has both, ordered.
      await box.put(1, _msg(1, 'b', 'second').toJson());
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, hasLength(2));
      expect(emissions.last.map((m) => m.text), ['first', 'second']);

      await sub.cancel();
    },
  );

  test('watchRuntime reflects writes for the (epk, room) key', () async {
    final boxes = LocalBoxes();
    final repo = SessionReadRepository(boxes);
    final epk = 'epk_rt_${++_c}';
    final got = <RuntimeRecord>[];
    final sub = repo.watchRuntime(epk, 'main').listen(got.add);
    await Future<void>.delayed(Duration.zero);
    expect(got.last.connection, RuntimeConnection.connecting); // default

    await boxes.runtimeBox().put(
      LocalBoxes.runtimeKey(epk, 'main'),
      const RuntimeRecord(
        connection: RuntimeConnection.online,
        presence: RuntimePresence.alive,
      ).toJson(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(got.last.connection, RuntimeConnection.online);
    expect(got.last.presence, RuntimePresence.alive);
    await sub.cancel();
  });

  test('watchSessions emits the session index reactively', () async {
    final boxes = LocalBoxes();
    final repo = HomeReadRepository(boxes);
    final epk = 'epk_idx_${++_c}';
    final got = <List<SessionIndexRecord>>[];
    final sub = repo.watchSessions().listen(got.add);
    await Future<void>.delayed(Duration.zero);
    final initialCount = got.last.length;

    await boxes.sessionsIndexBox().put(
      '$epk:main:session-a',
      SessionIndexRecord(
        epk: epk,
        roomId: 'main',
        sessionId: 'session-a',
        status: SessionActivity.working,
      ).toJson(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(got.last.length, initialCount + 1);
    expect(
      got.last.where((r) => r.epk == epk).single.status,
      SessionActivity.working,
    );
    await sub.cancel();
  });
}
