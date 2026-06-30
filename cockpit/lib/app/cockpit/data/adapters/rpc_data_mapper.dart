import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';

/// Converte os `data` das respostas request/response do RPC em entidades de
/// domínio. Separado do [RpcEventMapper] (que cuida do stream de eventos);
/// aqui é o payload de `get_available_models`/`get_state`/`set_model`/
/// `get_session_stats`. Único lugar que vê esse wire format.
class RpcDataMapper {
  const RpcDataMapper();

  PiModel? model(Object? json) {
    if (json is! Map) return null;
    final id = json['id'] as String?;
    final provider = json['provider'] as String?;
    if (id == null || provider == null) return null;
    final input = json['input'];
    return PiModel(
      provider: provider,
      id: id,
      name: json['name'] as String? ?? id,
      reasoning: json['reasoning'] == true,
      supportsImages: input is List && input.contains('image'),
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      thinkingLevelMap: _thinkingLevelMap(json['thinkingLevelMap']),
    );
  }

  Map<String, String?> _thinkingLevelMap(Object? value) {
    if (value is! Map) return const <String, String?>{};
    return value.map(
      (key, v) => MapEntry(key.toString(), v is String ? v : null),
    );
  }

  List<PiModel> models(Object? data) {
    if (data is! Map || data['models'] is! List) return const <PiModel>[];
    return (data['models'] as List)
        .map(model)
        .whereType<PiModel>()
        .toList(growable: false);
  }

  /// `get_commands` → `{commands:[{name, description, source, ...}]}`.
  List<PiCommand> commands(Object? data) {
    if (data is! Map || data['commands'] is! List) return const <PiCommand>[];
    return (data['commands'] as List)
        .whereType<Map>()
        .map((c) {
          final name = c['name'] as String?;
          if (name == null || name.isEmpty) return null;
          return PiCommand(
            name: name,
            description: c['description'] as String? ?? '',
          );
        })
        .whereType<PiCommand>()
        .toList(growable: false);
  }

  AgentSnapshot state(Object? data) {
    final map = data is Map ? data : const <String, dynamic>{};
    // Short-lived wire compatibility: older `pi --mode rpc get_state` payloads
    // expose `isStreaming` instead of `turn`. Convert it at the adapter boundary
    // so UI/domain consumers only read [AgentTurnProjection].
    return AgentSnapshot(
      model: model(map['model']),
      thinkingLevel: ThinkingLevel.fromWire(map['thinkingLevel'] as String?),
      turn: _turnProjection(
        map['turn'],
        legacyIsStreaming: map['isStreaming'] == true,
      ),
    );
  }

  AgentTurnProjection _turnProjection(
    Object? value, {
    required bool legacyIsStreaming,
  }) {
    if (value is Map) {
      final status = _turnStatus(value['status']);
      if (status != null) {
        return AgentTurnProjection(
          status: status,
          turnId: value['turnId'] as String?,
          replyTo: value['replyTo'] as String?,
          startedAt: _dateTime(value['startedAt']),
          error: value['error'] as String?,
        );
      }
    }
    return legacyIsStreaming
        ? const AgentTurnProjection(status: AgentTurnStatus.streaming)
        : AgentTurnProjection.idle;
  }

  AgentTurnStatus? _turnStatus(Object? value) => switch (value) {
    'idle' => AgentTurnStatus.idle,
    'working' => AgentTurnStatus.working,
    'streaming' => AgentTurnStatus.streaming,
    'error' => AgentTurnStatus.error,
    'stale' => AgentTurnStatus.stale,
    _ => null,
  };

  DateTime? _dateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  ContextUsage? contextUsage(Object? data) {
    if (data is! Map) return null;
    final usage = data['contextUsage'];
    if (usage is! Map) return null;
    final window = (usage['contextWindow'] as num?)?.toInt();
    if (window == null) return null;
    return ContextUsage(
      tokens: (usage['tokens'] as num?)?.toInt(),
      contextWindow: window,
      percent: (usage['percent'] as num?)?.toDouble(),
    );
  }

  /// Converte `get_messages` (`{messages:[AgentMessage]}`) em eventos do
  /// transcript. Histórico e stream ao vivo passam pelo mesmo reducer em
  /// [deriveCockpitTranscript]; este adapter não publica uma segunda projeção
  /// mutável de mensagens/tools.
  List<CockpitTranscriptEvent> transcriptEvents(
    Object? data, {
    required String sessionId,
  }) {
    if (data is! Map || data['messages'] is! List) {
      return const <CockpitTranscriptEvent>[];
    }
    final effectiveSessionId = sessionId.isNotEmpty
        ? sessionId
        : data['session_id'] as String? ?? 'get_messages';
    final events = <CockpitTranscriptEvent>[];
    var index = 0;
    String nextEventId() => '$effectiveSessionId:history:${index++}';
    final ts = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    for (final raw in data['messages'] as List) {
      if (raw is! Map) continue;
      switch (raw['role']) {
        case 'user':
          final text = _contentText(raw['content']);
          if (text.isNotEmpty) {
            final eventId = nextEventId();
            events.add(
              CockpitUserMessageConfirmed(
                eventId: eventId,
                sessionId: effectiveSessionId,
                ts: ts,
                clientMessageId: raw['id'] as String? ?? eventId,
                text: text,
              ),
            );
          }
        case 'assistant':
          final content = raw['content'];
          if (content is! List) break;
          final messageId = raw['id'] as String? ?? '';
          for (final block in content) {
            if (block is! Map) continue;
            switch (block['type']) {
              case 'thinking':
                final text = block['thinking'] as String? ?? '';
                if (text.isNotEmpty) {
                  events.add(
                    CockpitThinkingDeltaReceived(
                      eventId: nextEventId(),
                      sessionId: effectiveSessionId,
                      ts: ts,
                      replyTo: messageId,
                      delta: text,
                    ),
                  );
                }
              case 'text':
                final text = block['text'] as String? ?? '';
                if (text.isNotEmpty) {
                  final eventId = nextEventId();
                  events.add(
                    CockpitAssistantMessageCommitted(
                      eventId: eventId,
                      sessionId: effectiveSessionId,
                      ts: ts,
                      messageId: messageId.isNotEmpty ? messageId : eventId,
                      replyTo: messageId,
                      text: text,
                    ),
                  );
                }
              case 'toolCall':
                final id = block['id'] as String? ?? '';
                events.add(
                  CockpitToolRequested(
                    eventId: nextEventId(),
                    sessionId: effectiveSessionId,
                    ts: ts,
                    toolCallId: id,
                    tool: block['name'] as String? ?? '?',
                    args: _asObjectMap(block['arguments']),
                  ),
                );
            }
          }
        case 'toolResult':
          final resultText = _contentText(raw['content']);
          events.add(
            CockpitToolFinished(
              eventId: nextEventId(),
              sessionId: effectiveSessionId,
              ts: ts,
              toolCallId: raw['toolCallId'] as String? ?? '',
              result: resultText,
              error: raw['isError'] == true ? resultText : null,
            ),
          );
      }
    }
    return List<CockpitTranscriptEvent>.unmodifiable(events);
  }

  /// Compatibility helper for callers that still ask for projected history.
  /// New session code should request [transcriptEvents] and derive once at the
  /// presentation boundary.
  List<TranscriptMessage> transcriptMessages(Object? data) {
    final sessionId = data is Map
        ? data['session_id'] as String? ?? 'get_messages'
        : 'get_messages';
    return deriveCockpitTranscript(
      transcriptEvents(data, sessionId: sessionId),
    ).entries;
  }

  String _contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String? ?? '')
          .join('\n');
    }
    return '';
  }

  Map<String, Object?> _asObjectMap(Object? value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const <String, Object?>{};
  }
}
