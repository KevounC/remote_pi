import 'package:app/pairing/storage.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake storage
// ---------------------------------------------------------------------------

class _FakeStorage extends PairingStorage {
  List<PeerRecord> peers;

  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => peers;

  @override
  Future<void> savePeer(PeerRecord r) async {
    peers = [r, ...peers.where((p) => p.remoteEpk != r.remoteEpk)];
  }

  @override
  Future<void> deletePeer(String remoteEpk) async {
    peers = peers.where((p) => p.remoteEpk != remoteEpk).toList();
  }
}

PeerRecord _peer() => const PeerRecord(
  remoteEpk: 'epk_1',
  sessionName: 'test session',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

// ---------------------------------------------------------------------------

void main() {
  group('SettingsViewModel', () {
    test('initial state is SettingsLoading', () {
      final vm = SettingsViewModel(_FakeStorage([_peer()]));
      expect(vm.state, isA<SettingsLoading>());
      vm.dispose();
    });

    test('loads peer → SettingsReady', () async {
      final vm = SettingsViewModel(_FakeStorage([_peer()]));
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, isA<SettingsReady>());
      expect((vm.state as SettingsReady).peer.sessionName, 'test session');
      vm.dispose();
    });

    test('no peer → SettingsNoPeer', () async {
      final vm = SettingsViewModel(_FakeStorage([]));
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, isA<SettingsNoPeer>());
      vm.dispose();
    });

    test('rename updates sessionName', () async {
      final storage = _FakeStorage([_peer()]);
      final vm = SettingsViewModel(storage);
      await Future<void>.delayed(Duration.zero);

      await vm.rename('New Name');
      final s = vm.state as SettingsReady;
      expect(s.peer.sessionName, 'New Name');
      expect(storage.peers.first.sessionName, 'New Name');
      vm.dispose();
    });

    test('revoke deletes peer → SettingsNoPeer', () async {
      final storage = _FakeStorage([_peer()]);
      final vm = SettingsViewModel(storage);
      await Future<void>.delayed(Duration.zero);

      await vm.revoke();
      expect(vm.state, isA<SettingsNoPeer>());
      expect(storage.peers, isEmpty);
      vm.dispose();
    });
  });
}
