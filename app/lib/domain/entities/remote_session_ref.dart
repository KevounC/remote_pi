/// Canonical remote Pi session identity used for transcript persistence.
///
/// Room reachability remains keyed separately by `(peerEpk, roomId)` because a
/// relay room can stay live while its Pi SDK session rotates. Durable chat
/// state must always use this full value so two sessions in the same room never
/// share a Hive box or session-index row.
final class RemoteSessionRef {
  const RemoteSessionRef({
    required this.peerEpk,
    required this.roomId,
    required this.sessionId,
  });

  final String peerEpk;
  final String roomId;
  final String sessionId;

  String get storageKey => '$peerEpk:$roomId:$sessionId';

  @override
  bool operator ==(Object other) =>
      other is RemoteSessionRef &&
      other.peerEpk == peerEpk &&
      other.roomId == roomId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(peerEpk, roomId, sessionId);

  @override
  String toString() =>
      'RemoteSessionRef(peerEpk: $peerEpk, roomId: $roomId, sessionId: $sessionId)';
}
