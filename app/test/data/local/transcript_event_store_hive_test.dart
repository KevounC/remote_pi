import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/transcript_event_record.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('HiveTranscriptEventStore', () {
    late Directory dir;
    late LocalBoxes boxes;
    late HiveTranscriptEventStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('transcript_events_');
      await LocalBoxes.initForTest(dir.path);
      boxes = LocalBoxes();
      store = HiveTranscriptEventStore(boxes);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('dedupes by event id and preserves original seq and order', () async {
      const key = TranscriptSessionKey(
        peerId: 'peer/one=',
        roomId: 'room:one',
        sessionId: 'sess-1',
      );
      await store.appendAll(key, <TranscriptEvent>[
        _submitted('event-1', 'sess-1', 'cli-1', 'first'),
        _submitted('event-2', 'sess-1', 'cli-2', 'second'),
      ]);

      final duplicate = await store.appendAll(key, <TranscriptEvent>[
        _submitted('event-1', 'sess-1', 'cli-1', 'changed'),
      ]);
      expect(duplicate.received, 1);
      expect(duplicate.appended, 0);
      expect(duplicate.skipped, 1);

      final events = await store.readSession(key);
      expect(events.map((event) => event.eventId), <String>[
        'event-1',
        'event-2',
      ]);
      expect((events.first as UserMessageSubmitted).text, 'first');

      final box = boxes.openTranscriptEventsBox(key);
      final rawFirst = (box.get('event-1') as Map).cast<String, Object?>();
      final rawSecond = (box.get('event-2') as Map).cast<String, Object?>();
      expect(rawFirst['seq'], 0);
      expect(rawSecond['seq'], 1);
    });

    test(
      'assigns monotonically increasing seq across append batches',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'peer',
          roomId: 'room',
          sessionId: 'sess-1',
        );

        await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-1', 'sess-1', 'cli-1', 'one'),
          _submitted('event-2', 'sess-1', 'cli-2', 'two'),
        ]);
        await store.appendAll(key, <TranscriptEvent>[
          _submitted('event-3', 'sess-1', 'cli-3', 'three'),
        ]);

        final box = boxes.openTranscriptEventsBox(key);
        expect(
          ['event-1', 'event-2', 'event-3'].map((id) {
            final json = (box.get(id) as Map).cast<String, Object?>();
            return json['seq'];
          }),
          <int>[0, 1, 2],
        );
      },
    );

    test('uses per-session box names and isolates reads', () async {
      const first = TranscriptSessionKey(
        peerId: 'peer/id=',
        roomId: 'room:main',
        sessionId: 'sess:one',
      );
      const second = TranscriptSessionKey(
        peerId: 'peer/id=',
        roomId: 'room:main',
        sessionId: 'sess:two',
      );

      expect(
        LocalBoxes.transcriptEventsBoxName(first),
        isNot(LocalBoxes.transcriptEventsBoxName(second)),
      );

      await store.appendAll(first, <TranscriptEvent>[
        _submitted('event-1', 'sess:one', 'cli-1', 'one'),
      ]);
      await store.appendAll(second, <TranscriptEvent>[
        _submitted('event-2', 'sess:two', 'cli-2', 'two'),
      ]);

      expect((await store.readSession(first)).map((e) => e.eventId), <String>[
        'event-1',
      ]);
      expect((await store.readSession(second)).map((e) => e.eventId), <String>[
        'event-2',
      ]);
    });

    test('guards against appending an event for a different session', () async {
      const key = TranscriptSessionKey(
        peerId: 'peer',
        roomId: 'room',
        sessionId: 'sess-1',
      );

      expect(
        () => store.appendAll(key, <TranscriptEvent>[
          _submitted('event-1', 'sess-2', 'cli-1', 'wrong session'),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'shared store/replay fixture is append-only, isolated, and rebuildable',
      () async {
        const key = TranscriptSessionKey(
          peerId: 'peer-fixture',
          roomId: 'main',
          sessionId: 'sess-store-fixture',
        );
        const foreignKey = TranscriptSessionKey(
          peerId: 'peer-fixture',
          roomId: 'main',
          sessionId: 'sess-foreign-fixture',
        );
        final ts = DateTime.fromMillisecondsSinceEpoch(1700000000000);
        final fixture = <TranscriptEvent>[
          UserMessageSubmitted(
            eventId: 'local:cli_1',
            sessionId: key.sessionId,
            ts: ts,
            clientMessageId: 'cli_1',
            text: 'hello',
          ),
          UserMessageFailed(
            eventId: 'local:cli_1:timeout',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 1)),
            clientMessageId: 'cli_1',
            code: 'timeout',
            message: 'Timed out waiting for echo.',
          ),
          UserMessageConfirmed(
            eventId: 'server:cli_1',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 2)),
            clientMessageId: 'cli_1',
            text: 'hello',
          ),
          AssistantMessageCommitted(
            eventId: 'server:chunk_1:committed',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 3)),
            messageId: 'agent_chunk_1',
            replyTo: 'cli_1',
            text: 'done',
          ),
          AssistantDoneReceived(
            eventId: 'server:done_1',
            sessionId: key.sessionId,
            ts: ts.add(const Duration(milliseconds: 4)),
            replyTo: 'cli_1',
          ),
        ];

        final first = await store.appendAll(key, fixture);
        final duplicate = await store.appendAll(key, fixture);
        await store.appendAll(foreignKey, <TranscriptEvent>[
          _submitted('foreign:cli_1', foreignKey.sessionId, 'cli_1', 'foreign'),
        ]);

        expect(first.appended, fixture.length);
        expect(duplicate.appended, 0, reason: 'duplicate append is ignored');
        expect(duplicate.skipped, fixture.length);
        expect(
          (await store.readSession(key)).map((event) => event.eventId),
          fixture.map((event) => event.eventId),
          reason: 'stable append order is the replay order',
        );
        expect(
          (await store.readSession(foreignKey)).map((event) => event.eventId),
          <String>['foreign:cli_1'],
          reason: 'foreign session_id is isolated in its own canonical box',
        );

        final projection = deriveTranscriptProjection(
          sessionId: key.sessionId,
          events: await store.readSession(key),
        );
        expect(projection.turn.working, isFalse);
        expect(projection.messages.map((message) => message.id), <String>[
          'cli_1',
          'agent_chunk_1',
        ]);
        final user = projection.messages.first as UserMsg;
        expect(
          user.status,
          UserMsgStatus.confirmed,
          reason: 'late confirmation suppresses timeout failure',
        );
        expect(user.text, 'hello');
        expect((projection.messages.last as AssistantMsg).text, 'done');
      },
    );

    test('fails fast on unknown record kind', () {
      expect(
        () => TranscriptEventRecord.fromJson(<String, Object?>{
          'event_id': 'event-1',
          'seq': 0,
          'session_id': 'sess-1',
          'kind': 'future_kind',
          'ts': 1700000000000,
          'payload': <String, Object?>{},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

UserMessageSubmitted _submitted(
  String eventId,
  String sessionId,
  String clientMessageId,
  String text,
) => UserMessageSubmitted(
  eventId: eventId,
  sessionId: sessionId,
  ts: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  clientMessageId: clientMessageId,
  text: text,
);
