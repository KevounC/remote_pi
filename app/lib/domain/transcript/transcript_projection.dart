import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';

enum TranscriptTurnStatus { idle, working, streaming, error }

final class TranscriptTurnView {
  const TranscriptTurnView({
    required this.status,
    this.replyTo,
    this.error,
  });

  final TranscriptTurnStatus status;
  final String? replyTo;
  final String? error;

  static const idle = TranscriptTurnView(status: TranscriptTurnStatus.idle);
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
          status: TranscriptTurnStatus.working,
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
            status: TranscriptTurnStatus.error,
            replyTo: event.clientMessageId,
            error: event.message,
          );
        }
      case AssistantDeltaReceived():
        streaming = (streaming?.inReplyTo == event.replyTo
                ? streaming
                : StreamingMessage(inReplyTo: event.replyTo))
            ?.appendDelta(event.delta);
        turn = TranscriptTurnView(
          status: TranscriptTurnStatus.streaming,
          replyTo: event.replyTo,
        );
      case AssistantMessageCommitted():
        appendAuthoritative(AssistantMsg(id: event.messageId, text: event.text));
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
      case CompactionRecorded():
        appendAuthoritative(
          CompactionMsg(
            id: event.eventId,
            summary: event.summary,
            tokensBefore: event.tokensBefore,
          ),
        );
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
