// ConnectionManager — lifecycle of the relay connection.
//
// State machine:
//
//   [noPeer] → connect() → [connecting] → success → [online]
//                              ↓                         ↓
//                           failure               (WS close or 2 ping misses)
//                              ↓                         ↓
//                          [offline] ←── canRetry=false
//                          [retrying] ←── backoff 1→2→5→10→30s
//                              ↓
//                          connect() → [connecting] → …
//
// Ping: every 25 s of idle. After 2 consecutive misses → retrying.
//
// Post-rollback (plan 06): connect() opens transport + adopts channel
// directly — no handshake on reconnect. Pi recognizes the peer via
// peers.json (`remote_epk`).

import 'dart:async';

import 'package:app/data/transport/channel.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';

// ---------------------------------------------------------------------------
// Status model
// ---------------------------------------------------------------------------

sealed class ConnectionStatus {
  const ConnectionStatus();
}

class StatusNoPeer extends ConnectionStatus {
  const StatusNoPeer();
}

class StatusConnecting extends ConnectionStatus {
  const StatusConnecting();
}

class StatusOnline extends ConnectionStatus {
  final IChannel channel;
  const StatusOnline(this.channel);
}

class StatusRetrying extends ConnectionStatus {
  final Duration nextRetry;
  final int attempt; // 0-based
  const StatusRetrying({required this.nextRetry, required this.attempt});
}

class StatusOffline extends ConnectionStatus {
  final String reason;
  final bool canRetry;
  const StatusOffline({required this.reason, this.canRetry = true});
}

// ---------------------------------------------------------------------------
// Backoff sequence (seconds)
// ---------------------------------------------------------------------------

const _kBackoff = [1, 2, 5, 10, 30];

Duration _backoffFor(int attempt) =>
    Duration(seconds: _kBackoff[attempt.clamp(0, _kBackoff.length - 1)]);

// ---------------------------------------------------------------------------
// Factory typedef — injectable for tests
// ---------------------------------------------------------------------------

/// Called to establish a new connection for a given peer.
/// Returns an [IChannel] on success, throws on failure.
typedef ConnectionFactory =
    Future<IChannel> Function(PeerRecord peer, CancelToken cancel);

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

// ---------------------------------------------------------------------------
// ConnectionManager
// ---------------------------------------------------------------------------

class ConnectionManager extends Service {
  final ConnectionFactory _factory;
  final PairingStorage _storage;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = const StatusNoPeer();

  Timer? _retryTimer;
  Timer? _pingTimer;
  CancelToken? _connectCancel;
  int _missedPings = 0;
  int _retryAttempt = 0;

  ConnectionManager({
    required ConnectionFactory factory,
    required PairingStorage storage,
  }) : _factory = factory,
       _storage = storage;

  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  IChannel? get channel =>
      _status is StatusOnline ? (_status as StatusOnline).channel : null;

  // Load the first saved peer and start connecting.
  // No-op when already online (e.g. channel was adopted from pairing flow).
  Future<void> boot() async {
    if (_status is StatusOnline) return;
    final peers = await _storage.listPeers();
    if (peers.isEmpty) {
      _emit(const StatusNoPeer());
      return;
    }
    await _connect(peers.first);
  }

  // Connect to a specific peer (used after fresh pairing).
  Future<void> connectTo(PeerRecord peer) => _connect(peer);

  // Adopt a channel that was established by an external flow (e.g. the
  // pairing handshake). Skips the factory entirely — the channel is already
  // connected and ready for use.
  void adopt(IChannel channel, PeerRecord peer) {
    _cancelRetry();
    _cancelPing();
    _connectCancel?.cancel();
    if (_status is StatusOnline) {
      final old = (_status as StatusOnline).channel;
      // ignore: unawaited_futures
      Future(() async {
        try { await old.close(); } catch (_) {}
      });
    }
    _retryAttempt = 0;
    _missedPings = 0;
    _emit(StatusOnline(channel));
    _startPing(peer, channel);
    _watchChannel(peer, channel);
  }

  // Permanently disconnect and go to NoPeer.
  Future<void> disconnect() async {
    _cancelRetry();
    _cancelPing();
    _connectCancel?.cancel();
    if (_status is StatusOnline) {
      await (_status as StatusOnline).channel.close();
    }
    _emit(const StatusNoPeer());
  }

  @override
  void dispose() {
    _cancelRetry();
    _cancelPing();
    _statusController.close();
  }

  // ---------------------------------------------------------------------------

  Future<void> _connect(PeerRecord peer) async {
    _cancelRetry();
    _cancelPing();
    _connectCancel?.cancel();

    final token = CancelToken();
    _connectCancel = token;
    _emit(const StatusConnecting());

    try {
      final ch = await _factory(peer, token);
      if (token.isCancelled) {
        await ch.close();
        return;
      }
      _retryAttempt = 0;
      _missedPings = 0;
      _emit(StatusOnline(ch));
      _startPing(peer, ch);
      _watchChannel(peer, ch);
    } catch (_) {
      if (!token.isCancelled) _scheduleRetry(peer);
    }
  }

  void _watchChannel(PeerRecord peer, IChannel ch) {
    // Channel closes when WS disconnects — drive retry.
    ch.serverMessages.listen(
      (_) => _missedPings = 0, // any message resets ping miss counter
      onError: (_) => _onChannelLost(peer),
      onDone: () => _onChannelLost(peer),
    );
  }

  void _onChannelLost(PeerRecord peer) {
    if (_status is! StatusOnline) return;
    _cancelPing();
    _scheduleRetry(peer);
  }

  void _scheduleRetry(PeerRecord peer) {
    final delay = _backoffFor(_retryAttempt);
    _emit(StatusRetrying(nextRetry: delay, attempt: _retryAttempt));
    _retryTimer = Timer(delay, () {
      _retryAttempt++;
      _connect(peer);
    });
  }

  void _startPing(PeerRecord peer, IChannel ch) {
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_status is! StatusOnline) return;
      try {
        await ch.send(Ping(id: _newId()));
      } catch (_) {}

      _missedPings++;
      if (_missedPings >= 2) {
        _cancelPing();
        _onChannelLost(peer);
      }
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _cancelPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _missedPings = 0;
  }

  void _emit(ConnectionStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  static int _idCounter = 0;
  static String _newId() => 'ping_${++_idCounter}';
}
