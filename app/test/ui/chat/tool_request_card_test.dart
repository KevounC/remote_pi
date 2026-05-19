import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _bashTool = ToolEvent(
  id: 'tc1',
  toolCallId: 'tc1',
  tool: 'Bash',
  args: {'command': 'ls -la'},
);

void main() {
  group('ToolRequestCard', () {
    testWidgets('shows tool name and command', (tester) async {
      await tester.pumpWidget(_wrap(
        ToolRequestCard(tool: _bashTool),
      ));
      expect(find.text('BASH'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
    });

    testWidgets('shows AWAITING and countdown initially', (tester) async {
      await tester.pumpWidget(_wrap(ToolRequestCard(tool: _bashTool)));
      expect(find.textContaining('AWAITING'), findsOneWidget);
      expect(find.textContaining('60s'), findsOneWidget);
    });

    testWidgets('Allow button dispatches ApproveDecision.allow', (tester) async {
      ApproveDecision? decided;
      String? decidedId;

      await tester.pumpWidget(_wrap(
        ToolRequestCard(
          tool: _bashTool,
          onDecide: (id, decision) {
            decidedId = id;
            decided = decision;
          },
        ),
      ));

      await tester.tap(find.text('Allow'));
      expect(decided, ApproveDecision.allow);
      expect(decidedId, 'tc1');
    });

    testWidgets('Deny button dispatches ApproveDecision.deny', (tester) async {
      ApproveDecision? decided;

      await tester.pumpWidget(_wrap(
        ToolRequestCard(
          tool: _bashTool,
          onDecide: (id, decision) => decided = decision,
        ),
      ));

      await tester.tap(find.text('Deny'));
      expect(decided, ApproveDecision.deny);
    });

    testWidgets('approved card shows ALLOWED and dims', (tester) async {
      const allowed = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
        status: ToolEventStatus.allowed,
      );

      await tester.pumpWidget(_wrap(ToolRequestCard(tool: allowed)));
      expect(find.text('ALLOWED'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
      expect(find.text('Deny'), findsNothing);
    });

    testWidgets('denied card shows outcome text', (tester) async {
      const denied = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
        status: ToolEventStatus.denied,
      );

      await tester.pumpWidget(_wrap(ToolRequestCard(tool: denied)));
      expect(find.text('DENIED'), findsOneWidget);
    });

    testWidgets('countdown starts at 60s', (tester) async {
      await tester.pumpWidget(_wrap(ToolRequestCard(tool: _bashTool)));
      expect(find.textContaining('60s'), findsOneWidget);
    });
  });
}
