import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceDocument v1 codec', () {
    test('round-trips the current v1 layout keys and semantic values', () {
      final document = WorkspaceDocument(
        projectId: 'project-1',
        focusedPaneId: 'pane-2',
        root: SplitPane(
          id: 'split-1',
          dir: SplitDir.vertical,
          frac: 0.42,
          a: const LeafPane(
            id: 'pane-1',
            tabs: <String>['agent-1', 'term-1'],
            active: 'agent-1',
          ),
          b: const LeafPane(
            id: 'pane-2',
            tabs: <String>['viewer-1', 'empty-1'],
            active: 'viewer-1',
          ),
        ),
        tabs: <String, WorkspaceTab>{
          'agent-1': const WorkspaceTab.agent(
            id: 'agent-1',
            relativeSubpath: 'packages/app',
            title: 'Agent',
            sessionPath: '/tmp/session.jsonl',
            autoStartRelay: true,
            preferredModelId: 'gpt-test',
            preferredThinking: ThinkingLevel.high,
          ),
          'term-1': const WorkspaceTab.terminal(
            id: 'term-1',
            relativeSubpath: 'tools',
            title: 'Shell',
          ),
          'viewer-1': const WorkspaceTab.viewer(
            id: 'viewer-1',
            filePath: '/repo/README.md',
          ),
          'empty-1': const WorkspaceTab.empty(id: 'empty-1', title: 'New'),
        },
      );

      final encoded = document.toPersistedJson();

      expect(
        encoded.keys,
        containsAll(<String>['v', 'focused', 'tree', 'sessions']),
      );
      expect(encoded['v'], 1);
      expect(encoded['focused'], 'pane-2');
      final sessions = (encoded['sessions'] as Map).cast<String, dynamic>();
      expect(sessions['agent-1'], <String, dynamic>{
        'type': 'agent',
        'sub': 'packages/app',
        'title': 'Agent',
        'sessionPath': '/tmp/session.jsonl',
        'auto_start_relay': true,
        'preferred_model': 'gpt-test',
        'preferred_thinking': 'high',
      });
      expect(sessions['term-1'], <String, dynamic>{
        'type': 'terminal',
        'sub': 'tools',
        'title': 'Shell',
      });
      expect(sessions['viewer-1'], <String, dynamic>{
        'type': 'viewer',
        'path': '/repo/README.md',
      });
      expect(sessions['empty-1'], <String, dynamic>{
        'type': 'empty',
        'title': 'New',
      });

      final decoded = WorkspaceDocument.fromPersistedJson(
        projectId: 'project-1',
        json: encoded,
      );
      expect(decoded.projectId, 'project-1');
      expect(decoded.focusedPaneId, 'pane-2');
      expect(decoded.tabs['agent-1']?.preferredThinking, ThinkingLevel.high);
      expect(decoded.toPersistedJson(), encoded);
    });

    test('decodes missing optional fields and invalid thinking as off', () {
      final decoded = WorkspaceDocument.fromPersistedJson(
        projectId: 'project-2',
        json: <String, dynamic>{
          'v': 1,
          'focused': 'pane-1',
          'tree': <String, dynamic>{
            'k': 'leaf',
            'id': 'pane-1',
            'tabs': <String>['agent-1'],
            'active': 'agent-1',
          },
          'sessions': <String, dynamic>{
            'agent-1': <String, dynamic>{
              'type': 'agent',
              'preferred_thinking': 'future-effort',
            },
          },
        },
      );

      final tab = decoded.tabs['agent-1'];
      expect(tab, isNotNull);
      expect(tab!.kind, WorkspaceTabKind.agent);
      expect(tab.relativeSubpath, '');
      expect(tab.autoStartRelay, isFalse);
      expect(tab.preferredThinking, ThinkingLevel.off);
    });

    test('invalid layouts fall back to a single empty pane document', () {
      final decoded = WorkspaceDocument.fromPersistedJson(
        projectId: 'project-3',
        json: <String, dynamic>{'v': 1, 'tree': 'not-a-tree'},
      );

      expect(decoded.projectId, 'project-3');
      expect(decoded.focusedPaneId, 'pane1');
      expect(leaves(decoded.root), hasLength(1));
      expect(decoded.tabs.values.single.kind, WorkspaceTabKind.empty);
    });
  });
}
