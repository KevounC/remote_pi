import 'package:app/data/transport/channel.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';

/// Abstract session repository — injectable for tests.
abstract class ISessionRepository {
  SessionState get current;
  Stream<SessionState> get sessionStream;
  Future<void> boot();
  Future<void> connectTo(PeerRecord peer);
  Future<void> sendMessage(String text);
  Future<void> cancel(String targetId);
  Future<void> approveTool(String toolCallId, ApproveDecision decision);
  void dispose();

  /// Transfer a live channel established by the pairing flow so the
  /// ConnectionManager can adopt it without going through the factory again.
  void adoptChannel(IChannel channel, PeerRecord peer);

  /// Close the active connection (if any). Used before re-pairing so the
  /// new pairing handshake does not collide in the relay's peer registry.
  Future<void> disconnect();
}
