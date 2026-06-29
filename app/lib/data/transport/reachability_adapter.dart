import 'package:app/domain/value_objects/reachability.dart';

/// Pure app-side reachability runtime used by transport adapters.
///
/// This object owns only contract state and counters. Sockets, timers, storage,
/// and UI remain owned by [ConnectionManager] or higher layers so the canonical
/// reachability policy can move to generated protocol code later without
/// carrying app infrastructure with it.
final class ReachabilityAdapter {
  ReachabilityState _state = ReachabilityState.offline;
  int _retryAttempt = 0;
  int _missedPings = 0;
  bool _connectInFlight = false;

  ReachabilityState get state => _state;
  int get retryAttempt => _retryAttempt;
  int get missedPings => _missedPings;
  bool get connectInFlight => _connectInFlight;
  Duration get nextRetryDelay => reachabilityBackoffForAttempt(_retryAttempt);
  bool get waitingForRetry => _state == ReachabilityState.retrying;

  void onConnectRequested() {
    _state = ReachabilityState.connecting;
    _connectInFlight = true;
  }

  void onConnectSucceeded() {
    _state = ReachabilityState.online;
    _retryAttempt = 0;
    _missedPings = 0;
    _connectInFlight = false;
  }

  void onConnectFailedRetryable() {
    _state = ReachabilityState.retrying;
    _connectInFlight = false;
  }

  void onTransportClosed() {
    _state = ReachabilityState.retrying;
    _missedPings = 0;
    _connectInFlight = false;
  }

  void onAppFrameObserved() {
    _state = ReachabilityState.online;
    _retryAttempt = 0;
    _missedPings = 0;
  }

  void onPingMissed() {
    _missedPings += 1;
    if (_missedPings >= reachabilityHeartbeat.degradedAfterMissedAppPongs) {
      _state = ReachabilityState.degraded;
    }
  }

  void onRetryTimerFired() {
    _retryAttempt += 1;
    _state = ReachabilityState.connecting;
    _connectInFlight = true;
  }

  void onStopRequested() {
    _state = ReachabilityState.offline;
    _connectInFlight = false;
  }

  void reset() {
    _state = ReachabilityState.offline;
    _retryAttempt = 0;
    _missedPings = 0;
    _connectInFlight = false;
  }
}
