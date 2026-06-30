import 'package:app/data/transport/reachability_adapter.dart';
import 'package:app/domain/value_objects/reachability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReachabilityAdapter', () {
    test(
      'relay connection success clears in-flight and ping misses, not retry backoff',
      () {
        final adapter = ReachabilityAdapter();

        adapter.onConnectRequested();
        expect(adapter.state, ReachabilityState.connecting);
        expect(adapter.connectInFlight, isTrue);

        adapter.onConnectFailedRetryable();
        adapter.onRetryTimerFired();
        adapter.onPingMissed();
        expect(adapter.retryAttempt, 1);
        expect(adapter.missedPings, 1);

        adapter.onRelayConnectionEstablished();

        expect(adapter.state, ReachabilityState.online);
        expect(adapter.connectInFlight, isFalse);
        expect(
          adapter.retryAttempt,
          1,
          reason:
              'factory success only proves relay auth; app/Pi traffic resets backoff',
        );
        expect(adapter.missedPings, 0);
      },
    );

    test(
      'retries advance only when timer fires and delay clamps to the contract ladder',
      () {
        final adapter = ReachabilityAdapter();

        adapter.onConnectRequested();
        adapter.onConnectFailedRetryable();
        expect(adapter.state, ReachabilityState.retrying);
        expect(adapter.retryAttempt, 0);
        expect(adapter.nextRetryDelay, reachabilityBackoffForAttempt(0));
        expect(adapter.waitingForRetry, isTrue);

        final expectedDelays = <Duration>[
          const Duration(seconds: 2),
          const Duration(seconds: 5),
          const Duration(seconds: 10),
          const Duration(seconds: 30),
          const Duration(seconds: 30),
          const Duration(seconds: 30),
        ];

        for (var i = 0; i < expectedDelays.length; i++) {
          adapter.onRetryTimerFired();
          expect(adapter.state, ReachabilityState.connecting);
          expect(adapter.connectInFlight, isTrue);
          expect(adapter.retryAttempt, i + 1);

          adapter.onConnectFailedRetryable();
          expect(adapter.state, ReachabilityState.retrying);
          expect(
            adapter.retryAttempt,
            i + 1,
            reason: 'failure emission must not double-increment attempts',
          );
          expect(adapter.nextRetryDelay, expectedDelays[i]);
        }
      },
    );

    test(
      'ping misses degrade after the contract threshold without forcing offline',
      () {
        final adapter = ReachabilityAdapter()..onRelayConnectionEstablished();

        for (
          var i = 1;
          i < reachabilityHeartbeat.degradedAfterMissedAppPongs;
          i++
        ) {
          adapter.onPingMissed();
          expect(adapter.state, ReachabilityState.online);
        }

        adapter.onPingMissed();
        expect(
          adapter.missedPings,
          reachabilityHeartbeat.degradedAfterMissedAppPongs,
        );
        expect(adapter.state, ReachabilityState.degraded);
      },
    );

    test(
      'fresh app traffic restores online and resets retry and missed-ping counters',
      () {
        final adapter = ReachabilityAdapter()
          ..onConnectRequested()
          ..onConnectFailedRetryable()
          ..onRetryTimerFired()
          ..onTransportClosed()
          ..onPingMissed();

        expect(adapter.state, ReachabilityState.retrying);
        expect(adapter.retryAttempt, 1);
        expect(adapter.missedPings, 1);

        adapter.onAppFrameObserved();

        expect(adapter.state, ReachabilityState.online);
        expect(adapter.retryAttempt, 0);
        expect(adapter.missedPings, 0);
      },
    );

    test(
      'stop and reset project offline without transport or timer dependencies',
      () {
        final adapter = ReachabilityAdapter()
          ..onConnectRequested()
          ..onConnectFailedRetryable();

        adapter.onRetryTimerFired();
        expect(adapter.retryAttempt, 1);

        adapter.onStopRequested();
        expect(adapter.state, ReachabilityState.offline);
        expect(adapter.connectInFlight, isFalse);
        expect(adapter.retryAttempt, 0);

        adapter.reset();
        expect(adapter.state, ReachabilityState.offline);
        expect(adapter.retryAttempt, 0);
        expect(adapter.missedPings, 0);
        expect(adapter.connectInFlight, isFalse);
      },
    );
  });
}
