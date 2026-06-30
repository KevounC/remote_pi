import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';

/// Backward-compatible aliases for the transcript seam. The canonical variant
/// set is [AppTurnStatus]; keep this wrapper so older tests/callers do not
/// grow a second enum.
abstract final class TranscriptTurnStatus {
  static const idle = AppTurnStatus.idle;
  static const working = AppTurnStatus.working;
  static const awaitingTool = AppTurnStatus.awaitingTool;
  static const streaming = AppTurnStatus.streaming;
  static const done = AppTurnStatus.done;
  static const error = AppTurnStatus.error;
  static const stale = AppTurnStatus.stale;
}

final class TranscriptTurnView {
  const TranscriptTurnView({
    required this.status,
    this.turnId,
    this.replyTo,
    this.error,
  });

  final AppTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final String? error;

  static const idle = TranscriptTurnView(status: AppTurnStatus.idle);

  bool get working => switch (status) {
    AppTurnStatus.working ||
    AppTurnStatus.awaitingTool ||
    AppTurnStatus.streaming => true,
    AppTurnStatus.idle ||
    AppTurnStatus.done ||
    AppTurnStatus.error ||
    AppTurnStatus.stale => false,
  };

  AppTurnProjection toAppProjection() => AppTurnProjection(
    status: status,
    turnId: turnId,
    replyTo: replyTo,
    error: error,
  );
}

AppTurnProjection deriveChatTurnProjection({
  required RoomTurnProjection room,
  required TranscriptTurnView transcript,
  required StreamingMessage? streaming,
}) {
  if (room.status == AppTurnStatus.stale) {
    return AppTurnProjection.stale;
  }

  if (streaming != null) {
    return AppTurnProjection(
      status: AppTurnStatus.streaming,
      turnId: transcript.turnId ?? streaming.inReplyTo,
      replyTo: streaming.inReplyTo,
      error: transcript.error,
    );
  }

  if (room.status == AppTurnStatus.working) {
    final transcriptProjection = transcript.toAppProjection();
    if (transcriptProjection.working) return transcriptProjection;
    return AppTurnProjection(
      status: AppTurnStatus.working,
      turnId: transcript.turnId ?? transcript.replyTo,
      replyTo: transcript.replyTo,
      error: transcript.error,
    );
  }

  if (transcript.working || transcript.status == AppTurnStatus.error) {
    return transcript.toAppProjection();
  }

  return AppTurnProjection.idle;
}

final class TranscriptProjection {
  const TranscriptProjection({
    required this.messages,
    required this.turn,
    this.streaming,
  });

  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final TranscriptTurnView turn;
}

/// Pure transcript projection and optimistic/authoritative reconcile reducer.
///
/// The event log is append-only, but this materialized view is rebuildable.
/// Server-authoritative events (`UserMessageConfirmed`, assistant/tool events,
/// compaction) form the stable prefix. Local optimistic submissions that have no
/// authoritative confirmation remain visible after that prefix. A failure marks
/// the local message failed only while no later confirmation exists; late
/// confirmation wins and suppresses the failure projection.
TranscriptProjection deriveTranscriptProjection({
  required String sessionId,
  required Iterable<TranscriptEvent> events,
}) {
  final scoped = events.where((event) => event.sessionId == sessionId);
  final seenEventIds = <String>{};
  final ordered = <TranscriptEvent>[];
  for (final event in scoped) {
    if (seenEventIds.add(event.eventId)) ordered.add(event);
  }

  final confirmedUsers = <String, UserMessageConfirmed>{};
  final submittedUsers = <String, UserMessageSubmitted>{};
  final failedUsers = <String, UserMessageFailed>{};
  final authoritativeMessages = <ChatMessage>[];
  final authoritativeIds = <String>{};
  final toolIndexes = <String, int>{};
  StreamingMessage? streaming;
  var turn = TranscriptTurnView.idle;

  void appendAuthoritative(ChatMessage message) {
    if (authoritativeIds.add(message.id)) authoritativeMessages.add(message);
  }

  void upsertTool(ToolEvent tool) {
    final existingIndex = toolIndexes[tool.toolCallId];
    if (existingIndex == null) {
      toolIndexes[tool.toolCallId] = authoritativeMessages.length;
      authoritativeMessages.add(tool);
      authoritativeIds.add(tool.id);
      return;
    }
    final previous = authoritativeMessages[existingIndex];
    if (previous is ToolEvent) {
      authoritativeMessages[existingIndex] = ToolEvent(
        id: previous.id,
        toolCallId: previous.toolCallId,
        tool: previous.tool.isNotEmpty ? previous.tool : tool.tool,
        args: previous.args,
        status: tool.status,
        result: tool.result,
        error: tool.error,
      );
    }
  }

  for (final event in ordered) {
    switch (event) {
      case UserMessageSubmitted():
        submittedUsers[event.clientMessageId] = event;
        turn = TranscriptTurnView(
          status: AppTurnStatus.working,
          turnId: event.turnId ?? event.clientMessageId,
          replyTo: event.clientMessageId,
        );
      case UserMessageConfirmed():
        confirmedUsers[event.clientMessageId] = event;
        appendAuthoritative(
          UserMsg(
            id: event.clientMessageId,
            text: event.text,
            image: event.image,
          ),
        );
      case UserMessageFailed():
        failedUsers[event.clientMessageId] = event;
        if (!confirmedUsers.containsKey(event.clientMessageId)) {
          turn = TranscriptTurnView(
            status: AppTurnStatus.error,
            turnId: event.turnId ?? event.clientMessageId,
            replyTo: event.clientMessageId,
            error: event.message,
          );
        }
      case AssistantDeltaReceived():
        streaming =
            (streaming?.inReplyTo == event.replyTo
                    ? streaming
                    : StreamingMessage(inReplyTo: event.replyTo))
                ?.appendDelta(event.delta);
        turn = TranscriptTurnView(
          status: AppTurnStatus.streaming,
          turnId: event.turnId ?? event.replyTo,
          replyTo: event.replyTo,
        );
      case AssistantMessageCommitted():
        appendAuthoritative(
          AssistantMsg(id: event.messageId, text: event.text),
        );
        streaming = null;
        turn = TranscriptTurnView.idle;
      case AssistantDoneReceived():
        streaming = null;
        turn = TranscriptTurnView.idle;
      case ToolRequested():
        upsertTool(
          ToolEvent(
            id: event.toolCallId,
            toolCallId: event.toolCallId,
            tool: event.tool,
            args: event.args,
          ),
        );
        if (streaming != null || turn.working) {
          turn = TranscriptTurnView(
            status: AppTurnStatus.awaitingTool,
            turnId: turn.turnId ?? event.turnId ?? streaming?.inReplyTo,
            replyTo: turn.replyTo ?? streaming?.inReplyTo,
          );
        }
      case ToolFinished():
        upsertTool(
          ToolEvent(
            id: event.toolCallId,
            toolCallId: event.toolCallId,
            tool: '',
            args: const <String, Object?>{},
            status: event.error == null
                ? ToolEventStatus.completed
                : ToolEventStatus.failed,
            result: event.result,
            error: event.error,
          ),
        );
        if (turn.status == AppTurnStatus.awaitingTool) {
          turn = TranscriptTurnView(
            status: AppTurnStatus.working,
            turnId: turn.turnId,
            replyTo: turn.replyTo,
          );
        }
      case CompactionRecorded():
        appendAuthoritative(
          CompactionMsg(
            id: event.eventId,
            summary: event.summary,
            tokensBefore: event.tokensBefore,
          ),
        );
        streaming = null;
        turn = TranscriptTurnView.idle;
    }
  }

  final localTail = <ChatMessage>[];
  for (final submitted in submittedUsers.values) {
    if (confirmedUsers.containsKey(submitted.clientMessageId)) continue;
    final failed = failedUsers[submitted.clientMessageId];
    localTail.add(
      UserMsg(
        id: submitted.clientMessageId,
        text: submitted.text,
        status: failed == null ? UserMsgStatus.pending : UserMsgStatus.failed,
        image: submitted.image,
      ),
    );
  }

  return TranscriptProjection(
    messages: List.unmodifiable([...authoritativeMessages, ...localTail]),
    streaming: streaming,
    turn: turn,
  );
}
