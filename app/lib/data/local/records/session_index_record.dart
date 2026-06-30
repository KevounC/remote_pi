import 'package:app/domain/entities/remote_session_ref.dart';

/// Plan/31 — per-session activity (#5: idle | working).
enum SessionActivity { idle, working }

/// Plan/31 — durable top-level index of sessions, so Home can query
/// cross-session (working/idle + last message) without opening every
/// per-session box. Keyed by `<epk>:<roomId>:<sessionId>` in the
/// `sessions_index` box.
class SessionIndexRecord {
  final String epk;
  final String roomId;
  final String sessionId;
  final String displayName;
  final SessionActivity status;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final DateTime? sessionStartedAt;

  const SessionIndexRecord({
    required this.epk,
    required this.roomId,
    required this.sessionId,
    this.displayName = '',
    this.status = SessionActivity.idle,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.sessionStartedAt,
  });

  RemoteSessionRef get ref =>
      RemoteSessionRef(peerEpk: epk, roomId: roomId, sessionId: sessionId);

  String get key => ref.storageKey;

  SessionIndexRecord copyWith({
    String? displayName,
    SessionActivity? status,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    DateTime? sessionStartedAt,
  }) => SessionIndexRecord(
    epk: epk,
    roomId: roomId,
    sessionId: sessionId,
    displayName: displayName ?? this.displayName,
    status: status ?? this.status,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
  );

  Map<String, dynamic> toJson() => {
    'epk': epk,
    'room_id': roomId,
    'session_id': sessionId,
    'display_name': displayName,
    'status': status.name,
    'last_message_at': lastMessageAt?.millisecondsSinceEpoch,
    'last_message_preview': lastMessagePreview,
    'session_started_at': sessionStartedAt?.millisecondsSinceEpoch,
  };

  static SessionIndexRecord? tryFromJson(Map<String, dynamic> j) {
    final sessionId = j['session_id'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    DateTime? ms(dynamic v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return SessionIndexRecord(
      epk: j['epk'] as String,
      roomId: j['room_id'] as String,
      sessionId: sessionId,
      displayName: (j['display_name'] as String?) ?? '',
      status: SessionActivity.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => SessionActivity.idle,
      ),
      lastMessageAt: ms(j['last_message_at']),
      lastMessagePreview: j['last_message_preview'] as String?,
      sessionStartedAt: ms(j['session_started_at']),
    );
  }

  factory SessionIndexRecord.fromJson(Map<String, dynamic> j) {
    final record = tryFromJson(j);
    if (record == null) {
      throw const FormatException(
        'SessionIndexRecord is missing canonical session_id',
      );
    }
    return record;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionIndexRecord &&
      other.epk == epk &&
      other.roomId == roomId &&
      other.sessionId == sessionId &&
      other.displayName == displayName &&
      other.status == status &&
      other.lastMessageAt == lastMessageAt &&
      other.lastMessagePreview == lastMessagePreview &&
      other.sessionStartedAt == sessionStartedAt;

  @override
  int get hashCode => Object.hash(
    epk,
    roomId,
    sessionId,
    displayName,
    status,
    lastMessageAt,
    lastMessagePreview,
    sessionStartedAt,
  );
}
