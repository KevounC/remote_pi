import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('OfflineBanner', () {
    testWidgets('hidden when StatusOnline', (tester) async {
      await tester.pumpWidget(_wrap(
        OfflineBanner(
          status: const StatusOnline(_FakeChannel()),
        ),
      ));
      expect(find.byType(OfflineBanner), findsOneWidget);
      // Should render SizedBox.shrink() — no text visible
      expect(find.text('Reconnecting…'), findsNothing);
    });

    testWidgets('shows retry info when StatusRetrying', (tester) async {
      await tester.pumpWidget(_wrap(
        const OfflineBanner(
          status: StatusRetrying(
            nextRetry: Duration(seconds: 5),
            attempt: 1,
          ),
        ),
      ));
      expect(find.textContaining('retry'), findsOneWidget);
    });

    testWidgets('shows re-pair button when StatusOffline canRetry=false', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(
        OfflineBanner(
          status: const StatusOffline(
            reason: 'fingerprint changed',
            canRetry: false,
          ),
          onRePair: () => tapped = true,
        ),
      ));
      expect(find.text('Re-pair'), findsOneWidget);
      await tester.tap(find.text('Re-pair'));
      expect(tapped, isTrue);
    });

    testWidgets('collapses back when going online', (tester) async {
      // Start retrying
      await tester.pumpWidget(_wrap(
        const OfflineBanner(
          status: StatusRetrying(
            nextRetry: Duration(seconds: 2),
            attempt: 0,
          ),
        ),
      ));
      expect(find.textContaining('retry'), findsOneWidget);

      // Now online
      await tester.pumpWidget(_wrap(
        const OfflineBanner(
          status: StatusOnline(_FakeChannel()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('retry'), findsNothing);
    });
  });
}

class _FakeChannel implements IChannel {
  const _FakeChannel();

  @override Stream<ServerMessage> get serverMessages => const Stream.empty();
  @override Future<void> send(ClientMessage msg) async {}
  @override Future<void> close() async {}
}
