import 'dart:async';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/transcript_event_record.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/transcript/transcript_event.dart';

final class HiveTranscriptEventStore implements TranscriptEventStore {
  const HiveTranscriptEventStore(this._boxes);

  final LocalBoxes _boxes;

  @override
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  ) async {
    final batch = events.toList(growable: false);
    final box = await _boxes.transcriptEventsBox(key);
    var nextSeq = _maxSeq(box.values) + 1;
    var appended = 0;
    for (final event in batch) {
      if (event.sessionId != key.sessionId) {
        throw StateError(
          'Transcript event ${event.eventId} belongs to session ${event.sessionId}, not ${key.sessionId}',
        );
      }
      if (box.containsKey(event.eventId)) continue;
      final record = TranscriptEventRecord.fromEvent(event, nextSeq++);
      await box.put(event.eventId, record.toJson());
      appended += 1;
    }
    return AppendTranscriptEventsResult(
      received: batch.length,
      appended: appended,
      skipped: batch.length - appended,
    );
  }

  @override
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key) async {
    final box = await _boxes.transcriptEventsBox(key);
    return _readBox(box.values, key.sessionId);
  }

  @override
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key) async* {
    final box = await _boxes.transcriptEventsBox(key);
    yield _readBox(box.values, key.sessionId);
    yield* box.watch().map((_) => _readBox(box.values, key.sessionId));
  }

  int _maxSeq(Iterable<dynamic> values) {
    var max = -1;
    for (final value in values) {
      final record = _recordFromBoxValue(value);
      if (record != null && record.seq > max) max = record.seq;
    }
    return max;
  }

  List<TranscriptEvent> _readBox(Iterable<dynamic> values, String sessionId) {
    final records = <TranscriptEventRecord>[];
    for (final value in values) {
      final record = _recordFromBoxValue(value);
      if (record == null) continue;
      if (record.sessionId != sessionId) {
        throw StateError(
          'Transcript event ${record.eventId} is stored in the wrong session box: ${record.sessionId} != $sessionId',
        );
      }
      records.add(record);
    }
    records.sort((a, b) {
      final seqCompare = a.seq.compareTo(b.seq);
      return seqCompare == 0 ? a.eventId.compareTo(b.eventId) : seqCompare;
    });
    return [for (final record in records) record.toEvent()];
  }

  TranscriptEventRecord? _recordFromBoxValue(dynamic value) {
    if (value == null) return null;
    if (value is TranscriptEventRecord) return value;
    if (value is Map<String, Object?>) return TranscriptEventRecord.fromJson(value);
    if (value is Map) {
      return TranscriptEventRecord.fromJson(
        value.map((key, value) {
          if (key is! String) {
            throw const FormatException('Transcript event record keys must be strings');
          }
          return MapEntry(key, value as Object?);
        }),
      );
    }
    throw FormatException('Unsupported transcript event record value: ${value.runtimeType}');
  }
}
