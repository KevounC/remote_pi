library;

/// Canonical Remote Pi reachability states shared across app, extension, and relay.
///
/// This is a pure domain projection of `protocol/schema/reachability.json`.
/// App transport adapters map their richer runtime objects onto this enum in a
/// later story; this file intentionally has no Flutter, WebSocket, storage, or
/// UI imports.
enum ReachabilityState { connecting, online, degraded, offline, retrying }

extension ReachabilityStateLabel on ReachabilityState {
  String get displayName => switch (this) {
    ReachabilityState.connecting => 'Connecting',
    ReachabilityState.online => 'Online',
    ReachabilityState.degraded => 'Degraded',
    ReachabilityState.offline => 'Offline',
    ReachabilityState.retrying => 'Retrying',
  };
}

const reachabilityBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
];

Duration reachabilityBackoffForAttempt(int attempt) {
  final safeAttempt = attempt < 0 ? 0 : attempt;
  final idx = safeAttempt >= reachabilityBackoff.length
      ? reachabilityBackoff.length - 1
      : safeAttempt;
  return reachabilityBackoff[idx];
}

const reachabilityHeartbeat = ReachabilityHeartbeat(
  appProtocolPing: Duration(seconds: 25),
  relayWsPing: Duration(seconds: 25),
  extensionLivenessCheck: Duration(seconds: 20),
  extensionLivenessTimeout: Duration(seconds: 70),
  degradedAfterMissedAppPongs: 3,
);

final class ReachabilityHeartbeat {
  const ReachabilityHeartbeat({
    required this.appProtocolPing,
    required this.relayWsPing,
    required this.extensionLivenessCheck,
    required this.extensionLivenessTimeout,
    required this.degradedAfterMissedAppPongs,
  });

  final Duration appProtocolPing;
  final Duration relayWsPing;
  final Duration extensionLivenessCheck;
  final Duration extensionLivenessTimeout;
  final int degradedAfterMissedAppPongs;
}

const reachabilityTransitions = <ReachabilityTransition>[
  ReachabilityTransition(
    from: ReachabilityState.offline,
    event: 'connect_requested',
    to: ReachabilityState.connecting,
  ),
  ReachabilityTransition(
    from: ReachabilityState.connecting,
    event: 'connect_succeeded',
    to: ReachabilityState.online,
  ),
  ReachabilityTransition(
    from: ReachabilityState.connecting,
    event: 'connect_failed_retryable',
    to: ReachabilityState.retrying,
  ),
  ReachabilityTransition(
    from: ReachabilityState.connecting,
    event: 'connect_cancelled',
    to: ReachabilityState.offline,
  ),
  ReachabilityTransition(
    from: ReachabilityState.online,
    event: 'app_protocol_silence',
    to: ReachabilityState.degraded,
  ),
  ReachabilityTransition(
    from: ReachabilityState.online,
    event: 'transport_closed',
    to: ReachabilityState.retrying,
  ),
  ReachabilityTransition(
    from: ReachabilityState.online,
    event: 'stop_requested',
    to: ReachabilityState.offline,
  ),
  ReachabilityTransition(
    from: ReachabilityState.degraded,
    event: 'fresh_app_frame_or_room_snapshot',
    to: ReachabilityState.online,
  ),
  ReachabilityTransition(
    from: ReachabilityState.degraded,
    event: 'transport_closed',
    to: ReachabilityState.retrying,
  ),
  ReachabilityTransition(
    from: ReachabilityState.degraded,
    event: 'stop_requested',
    to: ReachabilityState.offline,
  ),
  ReachabilityTransition(
    from: ReachabilityState.retrying,
    event: 'retry_timer_fired',
    to: ReachabilityState.connecting,
  ),
  ReachabilityTransition(
    from: ReachabilityState.retrying,
    event: 'stop_requested',
    to: ReachabilityState.offline,
  ),
  ReachabilityTransition(
    from: ReachabilityState.retrying,
    event: 'retry_disabled',
    to: ReachabilityState.offline,
  ),
];

final class ReachabilityTransition {
  const ReachabilityTransition({
    required this.from,
    required this.event,
    required this.to,
  });

  final ReachabilityState from;
  final String event;
  final ReachabilityState to;
}
