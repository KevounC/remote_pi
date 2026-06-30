import 'dart:typed_data';

import 'transcript_event.dart';

/// Immutable message produced by folding Cockpit transcript events.
///
/// `get_messages` history and the live RPC stream both project through this
/// model so user/text/thinking/tool display rules have one source of truth.
sealed class TranscriptMessage {
  const TranscriptMessage();
}

sealed class ProjectedTranscriptMessage extends TranscriptMessage {
  const ProjectedTranscriptMessage();
}

final class ProjectedUserMessage extends ProjectedTranscriptMessage {
  ProjectedUserMessage(
    this.text, {
    List<Uint8List> images = const <Uint8List>[],
  }) : images = List<Uint8List>.unmodifiable(images);

  final String text;
  final List<Uint8List> images;
}

final class ProjectedAssistantTextMessage extends ProjectedTranscriptMessage {
  const ProjectedAssistantTextMessage(this.text);
  final String text;
}

final class ProjectedThinkingMessage extends ProjectedTranscriptMessage {
  const ProjectedThinkingMessage(this.text);
  final String text;
}

enum ToolProjectionStatus { running, completed, error }

final class ProjectedToolMessage extends ProjectedTranscriptMessage {
  ProjectedToolMessage({
    required this.callId,
    required this.name,
    required Map<String, dynamic> args,
    required this.status,
    this.resultText = '',
  }) : args = Map<String, dynamic>.unmodifiable(args);

  final String callId;
  final String name;
  final Map<String, dynamic> args;
  final ToolProjectionStatus status;
  final String resultText;
}

final class CockpitTranscriptProjection {
  const CockpitTranscriptProjection({
    required this.entries,
    required this.turn,
  });

  final List<ProjectedTranscriptMessage> entries;
  final CockpitTranscriptTurnView turn;
}

/// Folds append-only Cockpit transcript events into immutable display messages.
///
/// The reducer may use mutable draft state internally, but every published entry
/// is a value object. Tool results replace the projected tool entry atomically,
/// so callers never observe a half-mutated domain tool object.
CockpitTranscriptProjection deriveCockpitTranscript(
  Iterable<CockpitTranscriptEvent> events,
) {
  final entries = <ProjectedTranscriptMessage>[];
  final toolsById = <String, int>{};
  _TextDraft? openText;
  _TextDraft? openThinking;
  var turn = const CockpitTranscriptTurnView(
    status: CockpitTranscriptTurnStatus.idle,
  );

  void closeText() {
    openText = null;
  }

  void closeThinking() {
    openThinking = null;
  }

  void closeAssistantBuffers() {
    closeText();
    closeThinking();
  }

  void appendTextDelta(String delta) {
    if (delta.isEmpty) return;
    final draft = openText;
    if (draft == null) {
      entries.add(ProjectedAssistantTextMessage(delta));
      openText = _TextDraft(entries.length - 1, delta);
    } else {
      final text = draft.text + delta;
      entries[draft.index] = ProjectedAssistantTextMessage(text);
      openText = _TextDraft(draft.index, text);
    }
  }

  void commitText(String text) {
    if (text.isEmpty) {
      closeText();
      return;
    }
    final draft = openText;
    if (draft == null) {
      entries.add(ProjectedAssistantTextMessage(text));
    } else {
      entries[draft.index] = ProjectedAssistantTextMessage(text);
    }
    closeText();
  }

  void appendThinkingDelta(String delta) {
    if (delta.isEmpty) return;
    final draft = openThinking;
    if (draft == null) {
      entries.add(ProjectedThinkingMessage(delta));
      openThinking = _TextDraft(entries.length - 1, delta);
    } else {
      final text = draft.text + delta;
      entries[draft.index] = ProjectedThinkingMessage(text);
      openThinking = _TextDraft(draft.index, text);
    }
  }

  for (final event in events) {
    switch (event) {
      case CockpitUserMessageSubmitted(:final text, :final images):
        if (text.isEmpty && images.isEmpty) continue;
        closeAssistantBuffers();
        entries.add(ProjectedUserMessage(text, images: images));
        turn = const CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.working,
        );
      case CockpitUserMessageConfirmed(:final text):
        if (text.isEmpty) continue;
        closeAssistantBuffers();
        entries.add(ProjectedUserMessage(text));
        turn = const CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.working,
        );
      case CockpitUserMessageFailed(:final message):
        turn = CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.error,
          error: message,
        );
      case CockpitAssistantDeltaReceived(:final replyTo, :final delta):
        appendTextDelta(delta);
        turn = CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.streaming,
          replyTo: replyTo,
        );
      case CockpitAssistantMessageCommitted(:final replyTo, :final text):
        commitText(text);
        turn = CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.streaming,
          replyTo: replyTo,
        );
      case CockpitThinkingDeltaReceived(:final replyTo, :final delta):
        appendThinkingDelta(delta);
        turn = CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.streaming,
          replyTo: replyTo,
        );
      case CockpitAssistantDoneReceived():
        closeAssistantBuffers();
        turn = const CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.idle,
        );
      case CockpitToolRequested(:final toolCallId, :final tool, :final args):
        final index = entries.length;
        toolsById[toolCallId] = index;
        entries.add(
          ProjectedToolMessage(
            callId: toolCallId,
            name: tool,
            args: _dynamicMap(args),
            status: ToolProjectionStatus.running,
          ),
        );
        turn = const CockpitTranscriptTurnView(
          status: CockpitTranscriptTurnStatus.working,
        );
      case CockpitToolFinished(:final toolCallId, :final result, :final error):
        final index = toolsById[toolCallId];
        if (index == null) continue;
        final existing = entries[index];
        if (existing is! ProjectedToolMessage) continue;
        entries[index] = ProjectedToolMessage(
          callId: existing.callId,
          name: existing.name,
          args: existing.args,
          status: error == null
              ? ToolProjectionStatus.completed
              : ToolProjectionStatus.error,
          resultText: error ?? _resultText(result),
        );
      case CockpitCompactionRecorded():
        closeAssistantBuffers();
    }
  }

  return CockpitTranscriptProjection(
    entries: List<ProjectedTranscriptMessage>.unmodifiable(entries),
    turn: turn,
  );
}

Map<String, dynamic> _dynamicMap(Map<String, Object?> value) {
  return value.map((key, v) => MapEntry(key, v));
}

String _resultText(Object? result) {
  if (result == null) return '';
  if (result is String) return result;
  if (result is List) {
    return result
        .whereType<Map>()
        .where((block) => block['type'] == 'text')
        .map((block) => block['text'] as String? ?? '')
        .join('\n');
  }
  if (result is Map && result['content'] is List) {
    return _resultText(result['content']);
  }
  return result.toString();
}

final class _TextDraft {
  const _TextDraft(this.index, this.text);

  final int index;
  final String text;
}
