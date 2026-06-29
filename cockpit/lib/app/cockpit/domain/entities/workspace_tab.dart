import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';

/// Persistable descriptor for a workspace tab.
///
/// This is intentionally not a live session object. Process handles, file
/// watchers, terminals, and LSP state stay in the projection/ViewModel layer and
/// are keyed by [id].
enum WorkspaceTabKind { empty, agent, terminal, viewer }

final class WorkspaceTab {
  const WorkspaceTab.agent({
    required this.id,
    required this.relativeSubpath,
    required this.title,
    this.sessionPath,
    this.autoStartRelay = false,
    this.preferredModelId,
    this.preferredThinking = ThinkingLevel.off,
  }) : kind = WorkspaceTabKind.agent,
       filePath = null;

  const WorkspaceTab.terminal({
    required this.id,
    required this.relativeSubpath,
    required this.title,
  }) : kind = WorkspaceTabKind.terminal,
       filePath = null,
       sessionPath = null,
       autoStartRelay = false,
       preferredModelId = null,
       preferredThinking = ThinkingLevel.off;

  const WorkspaceTab.viewer({required this.id, required this.filePath})
    : kind = WorkspaceTabKind.viewer,
      relativeSubpath = '',
      title = null,
      sessionPath = null,
      autoStartRelay = false,
      preferredModelId = null,
      preferredThinking = ThinkingLevel.off;

  const WorkspaceTab.empty({required this.id, this.title = 'New'})
    : kind = WorkspaceTabKind.empty,
      relativeSubpath = '',
      filePath = null,
      sessionPath = null,
      autoStartRelay = false,
      preferredModelId = null,
      preferredThinking = ThinkingLevel.off;

  final String id;
  final WorkspaceTabKind kind;
  final String relativeSubpath;
  final String? title;
  final String? filePath;
  final String? sessionPath;
  final bool autoStartRelay;
  final String? preferredModelId;
  final ThinkingLevel preferredThinking;
}
