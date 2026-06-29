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

  Map<String, dynamic> toPersistedJson() => WorkspaceLayoutCodec.encode(this);

  static WorkspaceDocument fromPersistedJson({
    required String projectId,
    required Map<String, dynamic> json,
  }) => WorkspaceLayoutCodec.decode(projectId: projectId, json: json);
}
