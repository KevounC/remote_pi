import 'package:app/protocol/protocol.dart';

/// Abstract channel — testable interface over [PeerChannel].
abstract class IChannel {
  Stream<ServerMessage> get serverMessages;
  Future<void> send(ClientMessage msg);
  Future<void> close();
}
