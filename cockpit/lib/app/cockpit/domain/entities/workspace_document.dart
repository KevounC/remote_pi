import 'package:cockpit/app/cockpit/domain/entities/workspace_layout_codec.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';

/// Canonical pure document for a Cockpit project workspace.
///
/// The document owns pane shape, focused pane, tab order, and persistable tab
/// descriptors. Live resources are a projection outside this domain entity.
final class WorkspaceDocument {
  const WorkspaceDocument({
    required this.projectId,
    required this.root,
    required this.focusedPaneId,
    required this.tabs,
    this.version = 1,
  });

  final String projectId;
  final int version;
  final PaneNode root;
  final String focusedPaneId;
  final Map<String, WorkspaceTab> tabs;

  factory WorkspaceDocument.empty({
    required String projectId,
    String paneId = 'pane1',
    String tabId = 'empty1',
  }) {
    return WorkspaceDocument(
      projectId: projectId,
      root: LeafPane(id: paneId, tabs: <String>[tabId], active: tabId),
      focusedPaneId: paneId,
      tabs: <String, WorkspaceTab>{tabId: WorkspaceTab.empty(id: tabId)},
    );
  }

  WorkspaceDocument copyWith({
    int? version,
    PaneNode? root,
    String? focusedPaneId,
    Map<String, WorkspaceTab>? tabs,
  }) {
    return WorkspaceDocument(
      projectId: projectId,
      version: version ?? this.version,
      root: root ?? this.root,
      focusedPaneId: focusedPaneId ?? this.focusedPaneId,
      tabs: tabs ?? this.tabs,
    );
  }

  WorkspaceDocument ensureFocusValid() {
    final currentLeaves = leaves(root);
    if (currentLeaves.any((leaf) => leaf.id == focusedPaneId)) return this;
    if (currentLeaves.isEmpty) return this;
    return copyWith(focusedPaneId: currentLeaves.first.id);
  }

  /// Returns a document that only references tabs in [restorableTabIds].
  ///
  /// Pane geometry is preserved. If filtering would leave a leaf empty, a new
  /// empty tab descriptor from [emptyTabFactory] is inserted in that leaf.
  WorkspaceDocument filterTabs(
    Iterable<String> restorableTabIds, {
    required WorkspaceTab Function() emptyTabFactory,
  }) {
    final allowed = restorableTabIds.toSet();
    final nextTabs = <String, WorkspaceTab>{};

    PaneNode filterNode(PaneNode node) {
      return switch (node) {
        LeafPane() => _filterLeaf(node, allowed, nextTabs, emptyTabFactory),
        SplitPane() => node.copyWith(
          a: filterNode(node.a),
          b: filterNode(node.b),
        ),
      };
    }

    return copyWith(root: filterNode(root), tabs: nextTabs).ensureFocusValid();
  }

  LeafPane _filterLeaf(
    LeafPane leaf,
    Set<String> allowed,
    Map<String, WorkspaceTab> nextTabs,
    WorkspaceTab Function() emptyTabFactory,
  ) {
    final keptIds = <String>[];
    for (final id in leaf.tabs) {
      if (!allowed.contains(id)) continue;
      final tab = tabs[id];
      if (tab == null) continue;
      nextTabs[id] = tab;
      keptIds.add(id);
    }

    if (keptIds.isEmpty) {
      final empty = emptyTabFactory();
      nextTabs[empty.id] = empty;
      return LeafPane(id: leaf.id, tabs: <String>[empty.id], active: empty.id);
    }

    return LeafPane(
      id: leaf.id,
      tabs: keptIds,
      active: keptIds.contains(leaf.active) ? leaf.active : keptIds.first,
    );
  }

  Map<String, dynamic> toPersistedJson() => WorkspaceLayoutCodec.encode(this);

  static WorkspaceDocument fromPersistedJson({
    required String projectId,
    required Map<String, dynamic> json,
  }) => WorkspaceLayoutCodec.decode(projectId: projectId, json: json);
}
