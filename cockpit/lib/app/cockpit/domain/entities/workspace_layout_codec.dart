import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';

/// Versioned JSON codec for Cockpit workspace layouts.
///
/// The persisted `v: 1` shape is intentionally compatible with the legacy
/// `CockpitViewModel` serializer. Hive stores an opaque map; this domain codec
/// is the single owner of the map's schema.
final class WorkspaceLayoutCodec {
  const WorkspaceLayoutCodec._();

  static Map<String, dynamic> encode(WorkspaceDocument document) {
    return <String, dynamic>{
      'v': 1,
      'focused': document.focusedPaneId,
      'tree': paneNodeToJson(document.root),
      'sessions': <String, dynamic>{
        for (final tab in document.tabs.values) tab.id: _tabToJson(tab),
      },
    };
  }

  static WorkspaceDocument decode({
    required String projectId,
    required Map<String, dynamic> json,
  }) {
    final treeJson = json['tree'];
    if (treeJson is! Map) {
      return WorkspaceDocument.empty(projectId: projectId);
    }

    try {
      final root = paneNodeFromJson(treeJson.cast<String, dynamic>());
      final rawSessions = json['sessions'];
      final tabs = rawSessions is Map
          ? _tabsFromJson(rawSessions.cast<String, dynamic>())
          : <String, WorkspaceTab>{};
      final focused = json['focused'];
      return WorkspaceDocument(
        projectId: projectId,
        version: json['v'] is int ? json['v'] as int : 1,
        root: root,
        focusedPaneId: focused is String ? focused : leaves(root).first.id,
        tabs: tabs,
      ).ensureFocusValid();
    } catch (_) {
      return WorkspaceDocument.empty(projectId: projectId);
    }
  }

  static Map<String, WorkspaceTab> _tabsFromJson(
    Map<String, dynamic> sessions,
  ) {
    final out = <String, WorkspaceTab>{};
    for (final entry in sessions.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      out[entry.key] = _tabFromJson(entry.key, raw.cast<String, dynamic>());
    }
    return out;
  }

  static WorkspaceTab _tabFromJson(String id, Map<String, dynamic> json) {
    final title = json['title'] as String?;
    final sub = json['sub'] as String? ?? '';
    return switch (json['type']) {
      'terminal' => WorkspaceTab.terminal(
        id: id,
        relativeSubpath: sub,
        title: title,
      ),
      'viewer' => WorkspaceTab.viewer(
        id: id,
        filePath: json['path'] as String?,
      ),
      'empty' => WorkspaceTab.empty(id: id, title: title ?? 'New'),
      _ => WorkspaceTab.agent(
        id: id,
        relativeSubpath: sub,
        title: title,
        sessionPath: json['sessionPath'] as String?,
        autoStartRelay: json['auto_start_relay'] == true,
        preferredModelId: json['preferred_model'] as String?,
        preferredThinking: ThinkingLevel.fromWire(
          json['preferred_thinking'] as String?,
        ),
      ),
    };
  }

  static Map<String, dynamic> _tabToJson(WorkspaceTab tab) {
    return switch (tab.kind) {
      WorkspaceTabKind.terminal => <String, dynamic>{
        'type': 'terminal',
        'sub': tab.relativeSubpath,
        'title': tab.title,
      },
      WorkspaceTabKind.viewer => <String, dynamic>{
        'type': 'viewer',
        'path': tab.filePath,
      },
      WorkspaceTabKind.empty => <String, dynamic>{
        'type': 'empty',
        'title': tab.title,
      },
      WorkspaceTabKind.agent => <String, dynamic>{
        'type': 'agent',
        'sub': tab.relativeSubpath,
        'title': tab.title,
        if (tab.sessionPath != null) 'sessionPath': tab.sessionPath,
        if (tab.autoStartRelay) 'auto_start_relay': true,
        if (tab.preferredModelId != null)
          'preferred_model': tab.preferredModelId,
        if (tab.preferredThinking != ThinkingLevel.off)
          'preferred_thinking': tab.preferredThinking.name,
      },
    };
  }
}
