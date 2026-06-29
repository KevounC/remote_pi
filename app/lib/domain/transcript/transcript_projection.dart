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

/// Pure projection contract. Step 1 only establishes the side-by-side seam;
/// the full optimistic/authoritative reconcile reducer lands in the next story.
TranscriptProjection deriveTranscriptProjection({
  required String sessionId,
  required Iterable<TranscriptEvent> events,
}) {
  final scoped = events.where((event) => event.sessionId == sessionId);
  final messages = <ChatMessage>[];
  StreamingMessage? streaming;
  var turn = TranscriptTurnView.idle;

  for (final event in scoped) {
    switch (event) {
      case UserMessageSubmitted():
        messages.add(
          UserMsg(
            id: event.clientMessageId,
            text: event.text,
            status: UserMsgStatus.pending,
            image: event.image,
          ),
        );
        turn = TranscriptTurnView(
          status: TranscriptTurnStatus.working,
          replyTo: event.clientMessageId,
        );
      case UserMessageConfirmed():
        messages.add(
          UserMsg(
            id: event.clientMessageId,
            text: event.text,
            image: event.image,
          ),
        );
      case UserMessageFailed():
        messages.add(
          UserMsg(
            id: event.clientMessageId,
            text: event.message,
            status: UserMsgStatus.failed,
          ),
        );
        turn = TranscriptTurnView(
          status: TranscriptTurnStatus.error,
          replyTo: event.clientMessageId,
          error: event.message,
        );
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
        messages.add(AssistantMsg(id: event.messageId, text: event.text));
        streaming = null;
        turn = TranscriptTurnView.idle;
      case AssistantDoneReceived():
        streaming = null;
        turn = TranscriptTurnView.idle;
      case ToolRequested():
        messages.add(
          ToolEvent(
            id: event.toolCallId,
            toolCallId: event.toolCallId,
            tool: event.tool,
            args: event.args,
          ),
        );
      case ToolFinished():
        messages.add(
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
        messages.add(
          CompactionMsg(
            id: event.eventId,
            summary: event.summary,
            tokensBefore: event.tokensBefore,
          ),
        );
    }
  }

  return TranscriptProjection(
    messages: List.unmodifiable(messages),
    streaming: streaming,
    turn: turn,
  );
}
