import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';

/// Non-projected transcript side entry.
///
/// Assistant/user/thinking/tool messages are rendered from immutable
/// [ProjectedTranscriptMessage] values in the session projection. These entries
/// remain for local side-channel rows such as process info, worked duration,
/// extension notices, and interactive UI requests.
sealed class AgentEntry {
  AgentEntry();
}

/// Linha de ciclo de vida (ACK de erro, stderr, saída do processo).
final class InfoEntry extends AgentEntry {
  InfoEntry(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// Marca o fim de um turno com quanto tempo o agente trabalhou.
final class WorkedEntry extends AgentEntry {
  WorkedEntry(this.duration);
  final Duration duration;
}

/// Aviso da extensão (`extension_ui_request` method `notify`) — não é resposta
/// do agente. `level`: 0 info, 1 warning, 2 error.
final class NoticeEntry extends AgentEntry {
  NoticeEntry(this.message, this.level);
  final String message;
  final int level;
}

/// Pedido interativo da extensão (`select`/`confirm`/`input`/`editor`).
/// Renderiza um card no transcript; ao responder, vira [resolved] com
/// [answerLabel] e o `extension_ui_response` é enviado. Mutável de propósito.
final class UiRequestEntry extends AgentEntry {
  UiRequestEntry({
    required this.id,
    required this.method,
    this.title,
    this.message,
    this.placeholder,
    this.defaultValue,
    this.options = const <String>[],
  });

  final String id;
  final String method; // select | confirm | input | editor
  final String? title;
  final String? message;
  final String? placeholder;
  final String? defaultValue;
  final List<String> options;

  bool resolved = false;
  String? answerLabel;
}
