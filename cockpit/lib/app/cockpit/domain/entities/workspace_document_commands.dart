import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';

/// Result of a pure workspace document command.
///
/// The document is the new immutable workspace state. [disposeTabIds] names live
/// projection resources that the caller should tear down after applying the
/// document; domain commands never dispose processes or notify listeners.
final class WorkspaceCommandResult {
  const WorkspaceCommandResult({
    required this.document,
    this.disposeTabIds = const <String>[],
  });

  final WorkspaceDocument document;
  final List<String> disposeTabIds;
}

/// Pure document commands for cockpit pane and tab surgery.
///
/// Commands are deterministic and side-effect free. Callers provide fresh pane,
/// split, and tab ids/descriptors so the domain layer remains portable and easy
/// to replay in tests or future patchbay surfaces.
final class WorkspaceDocumentCommands {
  const WorkspaceDocumentCommands._();

  static WorkspaceCommandResult focusPane(
    WorkspaceDocument document, {
    required String paneId,
  }) {
    if (document.focusedPaneId == paneId ||
        findLeaf(document.root, paneId) == null) {
      return WorkspaceCommandResult(document: document);
    }
    return WorkspaceCommandResult(
      document: document.copyWith(focusedPaneId: paneId),
    );
  }

  static WorkspaceCommandResult selectTab(
    WorkspaceDocument document, {
    required String paneId,
    required String tabId,
  }) {
    final pane = findLeaf(document.root, paneId);
    if (pane == null || !pane.tabs.contains(tabId)) {
      return WorkspaceCommandResult(document: document);
    }
    final root = updateLeaf(
      document.root,
      paneId,
      (leaf) => leaf.copyWith(active: tabId),
    );
    return WorkspaceCommandResult(
      document: document.copyWith(root: root, focusedPaneId: paneId),
    );
  }

  static WorkspaceCommandResult resizeSplit(
    WorkspaceDocument document, {
    required String splitId,
    required double frac,
  }) {
    return WorkspaceCommandResult(
      document: document.copyWith(
        root: setFrac(document.root, splitId, frac.clamp(0.16, 0.84)),
      ),
    );
  }

  static WorkspaceCommandResult appendTab(
    WorkspaceDocument document, {
    required String paneId,
    required WorkspaceTab tab,
  }) {
    final pane = findLeaf(document.root, paneId);
    if (pane == null) return WorkspaceCommandResult(document: document);
    final root = updateLeaf(
      document.root,
      paneId,
      (leaf) =>
          leaf.copyWith(tabs: <String>[...leaf.tabs, tab.id], active: tab.id),
    );
    return WorkspaceCommandResult(
      document: document.copyWith(
        root: root,
        focusedPaneId: paneId,
        tabs: <String, WorkspaceTab>{...document.tabs, tab.id: tab},
      ),
    );
  }

  static WorkspaceCommandResult replaceTab(
    WorkspaceDocument document, {
    required String paneId,
    required String oldTabId,
    required WorkspaceTab newTab,
    bool disposeOldTab = true,
  }) {
    final pane = findLeaf(document.root, paneId);
    if (pane == null || !pane.tabs.contains(oldTabId)) {
      return WorkspaceCommandResult(document: document);
    }
    final root = updateLeaf(document.root, paneId, (leaf) {
      final tabs = leaf.tabs
          .map((id) => id == oldTabId ? newTab.id : id)
          .toList(growable: false);
      return leaf.copyWith(tabs: tabs, active: newTab.id);
    });
    final tabs = <String, WorkspaceTab>{...document.tabs}..remove(oldTabId);
    tabs[newTab.id] = newTab;
    return WorkspaceCommandResult(
      document: document.copyWith(
        root: root,
        focusedPaneId: paneId,
        tabs: tabs,
      ),
      disposeTabIds: disposeOldTab ? <String>[oldTabId] : const <String>[],
    );
  }

  static WorkspaceCommandResult replaceActiveTab(
    WorkspaceDocument document, {
    required String paneId,
    required WorkspaceTab newTab,
  }) {
    final pane = findLeaf(document.root, paneId);
    if (pane == null) return WorkspaceCommandResult(document: document);
    return replaceTab(
      document,
      paneId: paneId,
      oldTabId: pane.active,
      newTab: newTab,
    );
  }

  static WorkspaceCommandResult fillEmpty(
    WorkspaceDocument document, {
    required String paneId,
    required String emptyTabId,
    required WorkspaceTab replacement,
  }) => replaceTab(
    document,
    paneId: paneId,
    oldTabId: emptyTabId,
    newTab: replacement,
  );

  static WorkspaceCommandResult splitPane(
    WorkspaceDocument document, {
    required String targetPaneId,
    required SplitDir dir,
    required WorkspaceTab tab,
    required String newPaneId,
    required String newSplitId,
    bool before = false,
  }) {
    final target = findLeaf(document.root, targetPaneId);
    if (target == null) return WorkspaceCommandResult(document: document);
    final newLeaf = LeafPane(
      id: newPaneId,
      tabs: <String>[tab.id],
      active: tab.id,
    );
    final root = splitLeaf(
      document.root,
      targetPaneId,
      dir,
      newLeaf,
      splitId: newSplitId,
      before: before,
    );
    return WorkspaceCommandResult(
      document: document.copyWith(
        root: root,
        focusedPaneId: newPaneId,
        tabs: <String, WorkspaceTab>{...document.tabs, tab.id: tab},
      ),
    );
  }

  static WorkspaceCommandResult moveTabToPane(
    WorkspaceDocument document, {
    required String srcPaneId,
    required String tabId,
    required String targetPaneId,
  }) {
    if (srcPaneId == targetPaneId) {
      return WorkspaceCommandResult(document: document);
    }
    final src = findLeaf(document.root, srcPaneId);
    final target = findLeaf(document.root, targetPaneId);
    if (src == null || target == null || !src.tabs.contains(tabId)) {
      return WorkspaceCommandResult(document: document);
    }

    final remaining = src.tabs
        .where((id) => id != tabId)
        .toList(growable: false);
    var root = updateLeaf(
      document.root,
      targetPaneId,
      (pane) =>
          pane.copyWith(tabs: <String>[...pane.tabs, tabId], active: tabId),
    );
    if (remaining.isEmpty) {
      root = removeLeaf(root, srcPaneId);
    } else {
      root = updateLeaf(
        root,
        srcPaneId,
        (pane) => pane.copyWith(
          tabs: remaining,
          active: _activeAfter(src, tabId, remaining),
        ),
      );
    }

    return WorkspaceCommandResult(
      document: document
          .copyWith(root: root, focusedPaneId: targetPaneId)
          .ensureFocusValid(),
    );
  }

  static WorkspaceCommandResult moveTabToNewSplit(
    WorkspaceDocument document, {
    required String srcPaneId,
    required String tabId,
    required String targetPaneId,
    required SplitDir dir,
    required bool before,
    required String newPaneId,
    required String newSplitId,
  }) {
    final src = findLeaf(document.root, srcPaneId);
    final target = findLeaf(document.root, targetPaneId);
    if (src == null || target == null || !src.tabs.contains(tabId)) {
      return WorkspaceCommandResult(document: document);
    }
    final remaining = src.tabs
        .where((id) => id != tabId)
        .toList(growable: false);
    if (srcPaneId == targetPaneId && remaining.isEmpty) {
      return WorkspaceCommandResult(document: document);
    }

    final newLeaf = LeafPane(
      id: newPaneId,
      tabs: <String>[tabId],
      active: tabId,
    );
    var root = document.root;
    if (remaining.isNotEmpty) {
      root = updateLeaf(
        root,
        srcPaneId,
        (pane) => pane.copyWith(
          tabs: remaining,
          active: _activeAfter(src, tabId, remaining),
        ),
      );
    }
    root = splitLeaf(
      root,
      targetPaneId,
      dir,
      newLeaf,
      splitId: newSplitId,
      before: before,
    );
    if (remaining.isEmpty) root = removeLeaf(root, srcPaneId);

    return WorkspaceCommandResult(
      document: document
          .copyWith(root: root, focusedPaneId: newPaneId)
          .ensureFocusValid(),
    );
  }

  static WorkspaceCommandResult moveTabToIndex(
    WorkspaceDocument document, {
    required String srcPaneId,
    required String tabId,
    required String targetPaneId,
    required int index,
  }) {
    final src = findLeaf(document.root, srcPaneId);
    final target = findLeaf(document.root, targetPaneId);
    if (src == null || target == null || !src.tabs.contains(tabId)) {
      return WorkspaceCommandResult(document: document);
    }

    if (srcPaneId == targetPaneId) {
      final tabs = reorderTabs(src.tabs, tabId, index);
      final root = updateLeaf(
        document.root,
        srcPaneId,
        (pane) => pane.copyWith(tabs: tabs, active: tabId),
      );
      return WorkspaceCommandResult(
        document: document.copyWith(root: root, focusedPaneId: srcPaneId),
      );
    }

    final remaining = src.tabs
        .where((id) => id != tabId)
        .toList(growable: false);
    final targetTabs = <String>[...target.tabs]
      ..insert(index.clamp(0, target.tabs.length), tabId);
    var root = updateLeaf(
      document.root,
      targetPaneId,
      (pane) => pane.copyWith(tabs: targetTabs, active: tabId),
    );
    if (remaining.isEmpty) {
      root = removeLeaf(root, srcPaneId);
    } else {
      root = updateLeaf(
        root,
        srcPaneId,
        (pane) => pane.copyWith(
          tabs: remaining,
          active: _activeAfter(src, tabId, remaining),
        ),
      );
    }
    return WorkspaceCommandResult(
      document: document
          .copyWith(root: root, focusedPaneId: targetPaneId)
          .ensureFocusValid(),
    );
  }

  static WorkspaceCommandResult closeTab(
    WorkspaceDocument document, {
    required String paneId,
    required String tabId,
    required WorkspaceTab emptyTab,
  }) {
    final pane = findLeaf(document.root, paneId);
    if (pane == null || !pane.tabs.contains(tabId)) {
      return WorkspaceCommandResult(document: document);
    }

    final remaining = pane.tabs
        .where((id) => id != tabId)
        .toList(growable: false);
    var tabs = <String, WorkspaceTab>{...document.tabs}..remove(tabId);
    PaneNode root;
    if (remaining.isEmpty) {
      if (leaves(document.root).length == 1) {
        tabs[emptyTab.id] = emptyTab;
        root = updateLeaf(
          document.root,
          paneId,
          (leaf) =>
              leaf.copyWith(tabs: <String>[emptyTab.id], active: emptyTab.id),
        );
      } else {
        root = removeLeaf(document.root, paneId);
      }
    } else {
      root = updateLeaf(
        document.root,
        paneId,
        (leaf) => leaf.copyWith(
          tabs: remaining,
          active: _activeAfter(pane, tabId, remaining),
        ),
      );
    }

    return WorkspaceCommandResult(
      document: document.copyWith(root: root, tabs: tabs).ensureFocusValid(),
      disposeTabIds: <String>[tabId],
    );
  }

  static WorkspaceCommandResult closePane(
    WorkspaceDocument document, {
    required String paneId,
    required WorkspaceTab emptyTab,
  }) {
    final pane = findLeaf(document.root, paneId);
    if (pane == null) return WorkspaceCommandResult(document: document);

    final disposeIds = <String>[...pane.tabs];
    var tabs = <String, WorkspaceTab>{...document.tabs}
      ..removeWhere((id, _) => disposeIds.contains(id));
    PaneNode root;
    if (leaves(document.root).length == 1) {
      tabs[emptyTab.id] = emptyTab;
      root = updateLeaf(
        document.root,
        paneId,
        (leaf) =>
            leaf.copyWith(tabs: <String>[emptyTab.id], active: emptyTab.id),
      );
    } else {
      root = removeLeaf(document.root, paneId);
    }

    return WorkspaceCommandResult(
      document: document.copyWith(root: root, tabs: tabs).ensureFocusValid(),
      disposeTabIds: disposeIds,
    );
  }

  static String _activeAfter(
    LeafPane leaf,
    String removedId,
    List<String> remaining,
  ) {
    if (leaf.active != removedId) return leaf.active;
    final idx = leaf.tabs.indexOf(removedId);
    return remaining[(idx - 1).clamp(0, remaining.length - 1)];
  }
}
