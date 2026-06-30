// Plan/32 follow-up — the Quick Actions sheet must close when the tablet's
// selected session changes out from under it.

import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/quick_actions/widgets/dismiss_on_session_change.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteSessionRef _ref(String epk, String roomId, String sessionId) =>
    RemoteSessionRef(peerEpk: epk, roomId: roomId, sessionId: sessionId);

void main() {
  testWidgets('open modal sheet is dismissed when the session changes', (
    tester,
  ) async {
    final selection = SessionSelection()
      ..select(_ref('e1', 'r1', 'session-1'), 'Chat 1');
    addTearDown(selection.dispose);

    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Center(child: Text('page')));
          },
        ),
      ),
    );

    // Open a modal sheet wrapped like the Quick Actions sheet.
    showModalBottomSheet<void>(
      context: pageContext,
      builder: (_) => DismissOnSessionChange(
        selection: selection,
        child: const Text('quick-actions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('quick-actions'), findsOneWidget);

    // Switch to a different session (tablet master tap) → sheet closes.
    selection.select(_ref('e2', 'r2', 'session-2'), 'Chat 2');
    await tester.pumpAndSettle();
    expect(find.text('quick-actions'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('a no-op re-select keeps the sheet open', (tester) async {
    final selection = SessionSelection()
      ..select(_ref('e1', 'r1', 'session-1'), 'Chat 1');
    addTearDown(selection.dispose);

    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    showModalBottomSheet<void>(
      context: pageContext,
      builder: (_) => DismissOnSessionChange(
        selection: selection,
        child: const Text('quick-actions'),
      ),
    );
    await tester.pumpAndSettle();

    // Same session (no-op select notifies nothing) → stays open.
    selection.select(_ref('e1', 'r1', 'session-1'), 'Chat 1');
    await tester.pumpAndSettle();
    expect(find.text('quick-actions'), findsOneWidget);
  });
}
