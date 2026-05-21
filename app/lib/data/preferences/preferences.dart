import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide UI preferences (persisted across launches).
///
/// Extends [ChangeNotifier] so widgets can `context.watch<Preferences>()`
/// and rebuild on toggle. Backed by [FlutterSecureStorage] (same store
/// already used by pairing). Call [load] once during bootstrap before
/// the first frame to hydrate the in-memory cache.
class Preferences extends ChangeNotifier {
  final FlutterSecureStorage _store;
  bool _hideToolCalls = false;
  String? _selectedPeerEpk;
  String? _relayUrl;
  bool _onboardingCompleted = false;

  Preferences([FlutterSecureStorage? store])
      : _store = store ?? const FlutterSecureStorage();

  static const _kHideToolCallsKey = 'prefs.hide_tool_calls';
  static const _kSelectedPeerEpkKey = 'prefs.selected_peer_epk';
  static const _kRelayUrlKey = 'prefs.relay_url';
  static const _kOnboardingCompletedKey = 'prefs.onboarding_completed';

  /// True → chat hides `ToolEvent` rows (only user/assistant text remain).
  bool get hideToolCalls => _hideToolCalls;

  /// Epoch of the peer the user last picked from Home — the one
  /// `/chat` will connect to when it mounts. Null = no peer selected yet
  /// (user is still browsing or hasn't paired). Persisted so reopening
  /// the app right into `/chat` (e.g. via deep-link) knows which peer.
  String? get selectedPeerEpk => _selectedPeerEpk;

  /// User-configured relay URL override. `null` = use the public default
  /// (`kDefaultRelayUrl` in `relay_config.dart`). Set via Settings or
  /// during onboarding step 2 (custom relay).
  String? get relayUrl => _relayUrl;

  /// `true` after the user completed the 3-step onboarding flow at least
  /// once. Drives `/boot` redirect: false → `/onboarding`, true → `/home`.
  bool get onboardingCompleted => _onboardingCompleted;

  /// Hydrate from secure storage. Safe to call multiple times.
  Future<void> load() async {
    var changed = false;

    final raw = await _store.read(key: _kHideToolCallsKey);
    final next = raw == 'true';
    if (next != _hideToolCalls) {
      _hideToolCalls = next;
      changed = true;
    }

    final selected = await _store.read(key: _kSelectedPeerEpkKey);
    final cleaned = (selected != null && selected.isNotEmpty) ? selected : null;
    if (cleaned != _selectedPeerEpk) {
      _selectedPeerEpk = cleaned;
      changed = true;
    }

    final relay = await _store.read(key: _kRelayUrlKey);
    final relayCleaned = (relay != null && relay.isNotEmpty) ? relay : null;
    if (relayCleaned != _relayUrl) {
      _relayUrl = relayCleaned;
      changed = true;
    }

    final onboarded = await _store.read(key: _kOnboardingCompletedKey);
    final onboardedBool = onboarded == 'true';
    if (onboardedBool != _onboardingCompleted) {
      _onboardingCompleted = onboardedBool;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  Future<void> setHideToolCalls(bool value) async {
    if (_hideToolCalls == value) return;
    _hideToolCalls = value;
    await _store.write(
      key: _kHideToolCallsKey,
      value: value.toString(),
    );
    notifyListeners();
  }

  Future<void> setSelectedPeerEpk(String? value) async {
    final cleaned = (value != null && value.isNotEmpty) ? value : null;
    if (cleaned == _selectedPeerEpk) return;
    _selectedPeerEpk = cleaned;
    if (cleaned == null) {
      await _store.delete(key: _kSelectedPeerEpkKey);
    } else {
      await _store.write(key: _kSelectedPeerEpkKey, value: cleaned);
    }
    notifyListeners();
  }

  /// Set the user-configured relay URL. `null` or empty clears the
  /// override so the app falls back to `kDefaultRelayUrl`. Caller should
  /// validate via `isValidRelayUrl` first when [value] is non-null.
  Future<void> setRelayUrl(String? value) async {
    final cleaned = (value != null && value.isNotEmpty) ? value : null;
    if (cleaned == _relayUrl) return;
    _relayUrl = cleaned;
    if (cleaned == null) {
      await _store.delete(key: _kRelayUrlKey);
    } else {
      await _store.write(key: _kRelayUrlKey, value: cleaned);
    }
    notifyListeners();
  }

  Future<void> setOnboardingCompleted(bool value) async {
    if (_onboardingCompleted == value) return;
    _onboardingCompleted = value;
    await _store.write(
      key: _kOnboardingCompletedKey,
      value: value.toString(),
    );
    notifyListeners();
  }
}
