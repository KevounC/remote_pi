import 'dart:async';
import 'dart:convert';

import 'package:app/config/utils/injector.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_history_store.dart';
import 'package:app/data/repositories/session_repository.dart';
import 'package:app/data/transport/channel.dart'; // IChannel
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:provider/provider.dart';

final _injector = CustomInjector();

/// Direct injector access — only for bootstrap, tests, and deep-link handlers.
CustomInjector get injector => _injector;

Future<void> setupDependencies() async {
  // Infrastructure singletons
  _injector.addInstance<PairingStorage>(const PairingStorage());

  final prefs = Preferences();
  await prefs.load();
  _injector.addInstance<Preferences>(prefs);

  _injector.addInstance<SessionHistoryStore>(SessionHistoryStore());

  // ConnectionManager — production factory wired here.
  _injector.addService<ConnectionManager>(
    () => ConnectionManager(
      factory: _productionConnectionFactory,
      storage: _injector.get<PairingStorage>(),
    ),
  );

  // Repositories
  _injector.addRepository<SessionRepository>(
    () => SessionRepository(
      _injector.get<ConnectionManager>(),
      _injector.get<SessionHistoryStore>(),
    ),
  );

  // ViewModels
  _injector.addViewModel<ChatViewModel>(
    () => ChatViewModel(
      _injector.get<SessionRepository>(),
      _injector.get<Preferences>(),
      _injector.get<PairingStorage>(),
    ),
  );
  _injector.addViewModel<HomeViewModel>(
    () => HomeViewModel(
      _injector.get<PairingStorage>(),
      _injector.get<Preferences>(),
      _injector.get<ConnectionManager>(),
    ),
  );
  _injector.addViewModel<SettingsViewModel>(
    () => SettingsViewModel(
      _injector.get<PairingStorage>(),
      _injector.get<Preferences>(),
      _injector.get<ConnectionManager>(),
    ),
  );
  _injector.addViewModel<PairingViewModel>(
    () => PairingViewModel(
      _injector.get<PairingStorage>(),
      _productionPairingTransportFactory,
      _injector.get<SessionRepository>(),
      _injector.get<Preferences>(),
    ),
  );
  _injector.addViewModel<OnboardingViewModel>(
    () => OnboardingViewModel(_injector.get<Preferences>()),
  );

  _injector.commit();
}

// ---------------------------------------------------------------------------
// Production ConnectionFactory — used by ConnectionManager for reconnection.
// Post-rollback: just open transport + wrap in PlainPeerChannel; Pi recognizes
// the peer via peers.json (no per-reconnect handshake).
// ---------------------------------------------------------------------------

Future<IChannel> _productionConnectionFactory(
  PeerRecord peer,
  CancelToken cancel,
) async {
  final storage = injector.get<PairingStorage>();

  // Load (or generate) device-level Ed25519 identity.
  final deviceId = await storage.loadOrCreateDeviceEd25519Key();
  if (cancel.isCancelled) throw _CancelledError();

  final seed = base64Url.decode(_pad(deviceId.sk));
  final deviceKey = await Ed25519().newKeyPairFromSeed(seed);
  if (cancel.isCancelled) throw _CancelledError();

  // Defensive timeout (plano app-state-normalization): without this the
  // WebSocket connect + Ed25519 challenge round-trip can hang
  // indefinitely if the relay is unreachable — ChatViewModel would sit
  // in `ChatConnecting` forever. Throwing here pushes the manager into
  // its retry/backoff path, which is observable as `StatusRetrying` and
  // renders a "reconnecting" banner rather than an empty spinner.
  const wsConnectTimeout = Duration(seconds: 10);
  // Resolve the GLOBAL relay URL (plan 14): user override > default.
  // `peer.relayUrl` is kept on PeerRecord for legacy QR payloads but is
  // no longer consulted when opening a connection.
  final relayUrl = resolveRelayUrl(_injector.get<Preferences>());
  final transport = await WsTransport.connect(
    relayUrl: relayUrl,
    peerPubkey: peer.remoteEpk,
    ed25519Key: deviceKey,
  ).timeout(
    wsConnectTimeout,
    onTimeout: () => throw TimeoutException(
      'WS connect to $relayUrl timed out after '
      '${wsConnectTimeout.inSeconds}s',
    ),
  );

  if (cancel.isCancelled) {
    await transport.close();
    throw _CancelledError();
  }

  return PlainPeerChannel(transport: transport);
}

// ---------------------------------------------------------------------------
// Production PairingTransportFactory — used by PairingViewModel for first pair.
// ---------------------------------------------------------------------------

Future<PeerTransport> _productionPairingTransportFactory(
  QrPairPayload qr,
  SimpleKeyPair deviceEd25519,
) async {
  // Plan 14: pairing connects via the GLOBAL relay URL (Preferences),
  // not whatever was embedded in the QR. Mismatch between qr.relayUrl
  // and the user's configured relay is handled upstream by
  // `pair_request_flow.dart` (raises a `relay_mismatch` error that
  // PairingViewModel surfaces as a "trocar relay?" modal).
  final relayUrl = resolveRelayUrl(_injector.get<Preferences>());
  return WsTransport.connect(
    relayUrl: relayUrl,
    peerPubkey: qr.epk,
    ed25519Key: deviceEd25519,
  );
}

// ---------------------------------------------------------------------------

class _CancelledError implements Exception {
  const _CancelledError();
}

String _pad(String s) {
  final p = (4 - s.length % 4) % 4;
  return s + '=' * p;
}

void disposeDependencies() => _injector.dispose();

/// Bridges auto_injector and provider: creates a `ChangeNotifierProvider` that
/// asks the injector for a fresh `ViewModel<T>` instance on each route mount.
class ViewmodelProvider<T extends ViewModel> extends ChangeNotifierProvider<T> {
  ViewmodelProvider({super.key, super.child})
    : super(create: (_) => _injector.get<T>());

  ViewmodelProvider.value({super.key, required super.value, super.child})
    : super.value();
}
