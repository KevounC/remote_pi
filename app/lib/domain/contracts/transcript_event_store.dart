import 'dart:async';

import 'package:app/domain/transcript/transcript_event.dart';

final class TranscriptSessionKey {
  const TranscriptSessionKey({
    required this.peerId,
    required this.roomId,
    required this.sessionId,
  });

  final String peerId;
  final String roomId;
  final String sessionId;

  String get durableKey => '$peerId:$roomId:$sessionId';
}

final class AppendTranscriptEventsResult {
  const AppendTranscriptEventsResult({
    required this.received,
    required this.appended,
    required this.skipped,
  });

  final int received;
  final int appended;
  final int skipped;
}

abstract interface class TranscriptEventStore {
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  );

  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key);

  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key);
}
