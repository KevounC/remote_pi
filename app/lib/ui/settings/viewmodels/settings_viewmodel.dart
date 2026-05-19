import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/settings/states/settings_state.dart';

class SettingsViewModel extends ViewModel<SettingsState> {
  final PairingStorage _storage;
  bool _disposed = false;

  SettingsViewModel(this._storage) : super(const SettingsLoading()) {
    _load();
  }

  Future<void> _load() async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (peers.isEmpty) {
      emit(const SettingsNoPeer());
    } else {
      emit(SettingsReady(peer: peers.first));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Rename the paired device inline.
  Future<void> rename(String newName) async {
    final s = state;
    if (s is! SettingsReady) return;
    final updated = s.peer.copyWith(sessionName: newName);
    await _storage.savePeer(updated);
    emit(SettingsReady(peer: updated));
  }

  // Revoke local pairing — removes all peer records from Keychain.
  Future<void> revoke() async {
    if (state is! SettingsReady) return;
    final peers = await _storage.listPeers();
    for (final p in peers) {
      await _storage.deletePeer(p.remoteEpk);
    }
    emit(const SettingsNoPeer());
  }
}
