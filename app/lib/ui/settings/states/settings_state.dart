import 'package:app/pairing/storage.dart';

sealed class SettingsState {
  const SettingsState();
}

class SettingsLoading extends SettingsState {
  const SettingsLoading();
}

class SettingsReady extends SettingsState {
  final PeerRecord peer;

  const SettingsReady({required this.peer});

  @override
  bool operator ==(Object other) =>
      other is SettingsReady &&
      other.peer.remoteEpk == peer.remoteEpk &&
      other.peer.sessionName == peer.sessionName;

  @override
  int get hashCode => Object.hash(peer.remoteEpk, peer.sessionName);
}

class SettingsNoPeer extends SettingsState {
  const SettingsNoPeer();
}
