import 'dart:convert';
import 'dart:io';

import 'package:app/domain/value_objects/reachability.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readReachabilityContract() {
  final file = File('../protocol/schema/reachability.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('Reachability Dart projection', () {
    test('states and display names match the interim JSON contract', () {
      final contract = readReachabilityContract();
      final states = contract['states'] as List<dynamic>;
      final displayNames = contract['displayNames'] as Map<String, dynamic>;

      expect(ReachabilityState.values.map((state) => state.name), states);
      expect({
        for (final state in ReachabilityState.values)
          state.name: state.displayName,
      }, displayNames);
    });

    test('backoff policy matches the JSON contract and clamps attempts', () {
      final contract = readReachabilityContract();
      final backoffSeconds = contract['backoffSeconds'] as List<dynamic>;

      expect(
        reachabilityBackoff.map((duration) => duration.inSeconds),
        backoffSeconds,
      );
      expect(
        [-2, -1, 0, 1, 2, 3, 4, 5, 99].map(reachabilityBackoffForAttempt),
        const [
          Duration(seconds: 1),
          Duration(seconds: 1),
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 5),
          Duration(seconds: 10),
          Duration(seconds: 30),
          Duration(seconds: 30),
          Duration(seconds: 30),
        ],
      );
    });

    test('heartbeat policy matches the JSON contract', () {
      final contract = readReachabilityContract();
      final heartbeat = contract['heartbeat'] as Map<String, dynamic>;

      expect(
        reachabilityHeartbeat.appProtocolPing,
        Duration(seconds: heartbeat['appProtocolPingSeconds'] as int),
      );
      expect(
        reachabilityHeartbeat.relayWsPing,
        Duration(seconds: heartbeat['relayWsPingSeconds'] as int),
      );
      expect(
        reachabilityHeartbeat.extensionLivenessCheck,
        Duration(seconds: heartbeat['extensionLivenessCheckSeconds'] as int),
      );
      expect(
        reachabilityHeartbeat.extensionLivenessTimeout,
        Duration(seconds: heartbeat['extensionLivenessTimeoutSeconds'] as int),
      );
      expect(
        reachabilityHeartbeat.degradedAfterMissedAppPongs,
        heartbeat['degradedAfterMissedAppPongs'],
      );
    });

    test('transition table matches the JSON contract', () {
      final contract = readReachabilityContract();
      final transitions = contract['transitions'] as List<dynamic>;
      final projected = reachabilityTransitions
          .map(
            (transition) => <String, String>{
              'from': transition.from.name,
              'event': transition.event,
              'to': transition.to.name,
            },
          )
          .toList();

      expect(projected, transitions);
      expect(
        projected,
        contains({
          'from': 'online',
          'event': 'app_protocol_silence',
          'to': 'degraded',
        }),
      );
      expect(
        projected,
        contains({
          'from': 'degraded',
          'event': 'fresh_app_frame_or_room_snapshot',
          'to': 'online',
        }),
      );
    });
  });
}
