import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document_commands.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceDocumentCommands', () {
    test('moves a tab to another pane and removes an emptied source pane', () {
      final result = WorkspaceDocumentCommands.moveTabToPane(
        _document(
          focusedPaneId: 'left',
          root: const SplitPane(
            id: 'root',
            dir: SplitDir.vertical,
            frac: 0.5,
            a: LeafPane(id: 'left', tabs: <String>['a'], active: 'a'),
            b: LeafPane(id: 'right', tabs: <String>['b'], active: 'b'),
          ),
        ),
        srcPaneId: 'left',
        tabId: 'a',
        targetPaneId: 'right',
      );

      expect(leaves(result.document.root), hasLength(1));
      final pane = leaves(result.document.root).single;
      expect(pane.id, 'right');
      expect(pane.tabs, <String>['b', 'a']);
      expect(pane.active, 'a');
      expect(result.document.focusedPaneId, 'right');
      expect(result.disposeTabIds, isEmpty);
    });

    test('move to pane is a no-op for same pane or invalid ids', () {
      final document = _twoPaneDocument();

      expect(
        WorkspaceDocumentCommands.moveTabToPane(
          document,
          srcPaneId: 'left',
          tabId: 'a',
          targetPaneId: 'left',
        ).document,
        same(document),
      );
      expect(
        WorkspaceDocumentCommands.moveTabToPane(
          document,
          srcPaneId: 'left',
          tabId: 'missing',
          targetPaneId: 'right',
        ).document,
        same(document),
      );
    });

    test('moves a tab to a new split before and after the target pane', () {
      final before = WorkspaceDocumentCommands.moveTabToNewSplit(
        _document(
          root: const LeafPane(
            id: 'main',
            tabs: <String>['a', 'b'],
            active: 'a',
          ),
        ),
        srcPaneId: 'main',
        tabId: 'a',
        targetPaneId: 'main',
        dir: SplitDir.vertical,
        before: true,
        newPaneId: 'new-before',
        newSplitId: 'split-before',
      ).document.root;

      expect(before, isA<SplitPane>());
      final beforeSplit = before as SplitPane;
      expect((beforeSplit.a as LeafPane).id, 'new-before');
      expect((beforeSplit.b as LeafPane).tabs, <String>['b']);

      final after = WorkspaceDocumentCommands.moveTabToNewSplit(
        _document(
          root: const LeafPane(
            id: 'main',
            tabs: <String>['a', 'b'],
            active: 'a',
          ),
        ),
        srcPaneId: 'main',
        tabId: 'a',
        targetPaneId: 'main',
        dir: SplitDir.horizontal,
        before: false,
        newPaneId: 'new-after',
        newSplitId: 'split-after',
      ).document.root;

      expect(after, isA<SplitPane>());
      final afterSplit = after as SplitPane;
      expect((afterSplit.a as LeafPane).tabs, <String>['b']);
      expect((afterSplit.b as LeafPane).id, 'new-after');
    });

    test(
      'new split no-ops when splitting a single-tab pane against itself',
      () {
        final document = _document();
        final result = WorkspaceDocumentCommands.moveTabToNewSplit(
          document,
          srcPaneId: 'main',
          tabId: 'a',
          targetPaneId: 'main',
          dir: SplitDir.vertical,
          before: false,
          newPaneId: 'new',
          newSplitId: 'split',
        );

        expect(result.document, same(document));
      },
    );

    test('moves tab to index within pane and clamps cross-pane index', () {
      final samePane = WorkspaceDocumentCommands.moveTabToIndex(
        _document(
          root: const LeafPane(
            id: 'main',
            tabs: <String>['a', 'b', 'c'],
            active: 'a',
          ),
        ),
        srcPaneId: 'main',
        tabId: 'a',
        targetPaneId: 'main',
        index: 3,
      ).document;
      expect(findLeaf(samePane.root, 'main')!.tabs, <String>['b', 'c', 'a']);
      expect(findLeaf(samePane.root, 'main')!.active, 'a');

      final crossPane = WorkspaceDocumentCommands.moveTabToIndex(
        _twoPaneDocument(),
        srcPaneId: 'left',
        tabId: 'a',
        targetPaneId: 'right',
        index: 99,
      ).document;
      expect(findLeaf(crossPane.root, 'right')!.tabs, <String>['c', 'a']);
      expect(crossPane.focusedPaneId, 'right');
    });

    test('selects tab and resizes split without side effects', () {
      final selected = WorkspaceDocumentCommands.selectTab(
        _document(
          root: const LeafPane(
            id: 'main',
            tabs: <String>['a', 'b'],
            active: 'a',
          ),
        ),
        paneId: 'main',
        tabId: 'b',
      ).document;
      expect(findLeaf(selected.root, 'main')!.active, 'b');
      expect(selected.focusedPaneId, 'main');

      final resized =
          WorkspaceDocumentCommands.resizeSplit(
                _twoPaneDocument(),
                splitId: 'root',
                frac: 0.99,
              ).document.root
              as SplitPane;
      expect(resized.frac, 0.84);
    });

    test(
      'appends, replaces, fills empty, and splits with caller-provided tabs',
      () {
        final appended = WorkspaceDocumentCommands.appendTab(
          _document(),
          paneId: 'main',
          tab: const WorkspaceTab.terminal(
            id: 'term',
            relativeSubpath: 'tools',
            title: 'Terminal',
          ),
        ).document;
        expect(findLeaf(appended.root, 'main')!.tabs, <String>['a', 'term']);
        expect(appended.tabs['term']!.kind, WorkspaceTabKind.terminal);

        final filled = WorkspaceDocumentCommands.fillEmpty(
          _document(
            root: const LeafPane(
              id: 'main',
              tabs: <String>['empty'],
              active: 'empty',
            ),
            tabs: const <String, WorkspaceTab>{
              'empty': WorkspaceTab.empty(id: 'empty'),
            },
          ),
          paneId: 'main',
          emptyTabId: 'empty',
          replacement: const WorkspaceTab.agent(
            id: 'agent',
            relativeSubpath: '.',
            title: 'Agent',
          ),
        );
        expect(findLeaf(filled.document.root, 'main')!.tabs, <String>['agent']);
        expect(filled.document.tabs.containsKey('empty'), isFalse);
        expect(filled.disposeTabIds, <String>['empty']);

        final split = WorkspaceDocumentCommands.splitPane(
          _document(),
          targetPaneId: 'main',
          dir: SplitDir.vertical,
          tab: const WorkspaceTab.viewer(id: 'viewer', filePath: '/tmp/a.txt'),
          newPaneId: 'viewer-pane',
          newSplitId: 'split',
        ).document;
        expect(split.root, isA<SplitPane>());
        expect(split.focusedPaneId, 'viewer-pane');
        expect(split.tabs['viewer']!.kind, WorkspaceTabKind.viewer);
      },
    );

    test(
      'close tab returns disposal effect, active fallback, and focus fallback',
      () {
        final result = WorkspaceDocumentCommands.closeTab(
          _twoPaneDocument(focusedPaneId: 'left'),
          paneId: 'left',
          tabId: 'b',
          emptyTab: const WorkspaceTab.empty(id: 'empty'),
        );
        expect(findLeaf(result.document.root, 'left')!.tabs, <String>['a']);
        expect(findLeaf(result.document.root, 'left')!.active, 'a');
        expect(result.disposeTabIds, <String>['b']);
        expect(result.document.tabs.containsKey('b'), isFalse);

        final removedPane = WorkspaceDocumentCommands.closeTab(
          result.document,
          paneId: 'left',
          tabId: 'a',
          emptyTab: const WorkspaceTab.empty(id: 'unused'),
        ).document;
        expect(findLeaf(removedPane.root, 'left'), isNull);
        expect(removedPane.focusedPaneId, 'right');
      },
    );

    test(
      'close last tab or pane replaces with an empty tab and explicit effects',
      () {
        final closeLastTab = WorkspaceDocumentCommands.closeTab(
          _document(),
          paneId: 'main',
          tabId: 'a',
          emptyTab: const WorkspaceTab.empty(id: 'empty'),
        );
        expect(findLeaf(closeLastTab.document.root, 'main')!.tabs, <String>[
          'empty',
        ]);
        expect(closeLastTab.document.tabs.keys, containsAll(<String>['empty']));
        expect(closeLastTab.document.tabs.containsKey('a'), isFalse);
        expect(closeLastTab.disposeTabIds, <String>['a']);

        final closePane = WorkspaceDocumentCommands.closePane(
          _twoPaneDocument(focusedPaneId: 'right'),
          paneId: 'right',
          emptyTab: const WorkspaceTab.empty(id: 'unused'),
        );
        expect(findLeaf(closePane.document.root, 'right'), isNull);
        expect(closePane.disposeTabIds, <String>['c']);
        expect(closePane.document.focusedPaneId, 'left');
      },
    );
  });
}

WorkspaceDocument _document({
  PaneNode root = const LeafPane(id: 'main', tabs: <String>['a'], active: 'a'),
  String focusedPaneId = 'main',
  Map<String, WorkspaceTab>? tabs,
}) => WorkspaceDocument(
  projectId: 'project',
  focusedPaneId: focusedPaneId,
  root: root,
  tabs: tabs ?? _tabsFor(root),
);

WorkspaceDocument _twoPaneDocument({String focusedPaneId = 'left'}) =>
    _document(
      focusedPaneId: focusedPaneId,
      root: const SplitPane(
        id: 'root',
        dir: SplitDir.vertical,
        frac: 0.5,
        a: LeafPane(id: 'left', tabs: <String>['a', 'b'], active: 'b'),
        b: LeafPane(id: 'right', tabs: <String>['c'], active: 'c'),
      ),
    );

Map<String, WorkspaceTab> _tabsFor(PaneNode root) => <String, WorkspaceTab>{
  for (final leaf in leaves(root))
    for (final tabId in leaf.tabs)
      tabId: WorkspaceTab.agent(id: tabId, relativeSubpath: '.', title: tabId),
};
