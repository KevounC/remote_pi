// ignore_for_file: lines_longer_than_80_chars

// --- Supporting types ---

class Usage {
  final int inputTokens;
  final int outputTokens;

  const Usage({required this.inputTokens, required this.outputTokens});

  factory Usage.fromJson(Map<String, dynamic> j) => Usage(
    inputTokens: j['input_tokens'] as int,
    outputTokens: j['output_tokens'] as int,
  );
}

enum ApproveDecision { allow, deny }

class UnsupportedTypeException implements Exception {
  final String type;
  const UnsupportedTypeException(this.type);

  @override
  String toString() => 'UnsupportedTypeException: unknown type "$type"';
}

// --- ClientMessage (app → extension) ---
// MVP: 1 pairing = 1 Pi session — no session management messages.

sealed class ClientMessage {
  Map<String, dynamic> toJson();
}

class UserMessage extends ClientMessage {
  final String id;
  final String text;
  UserMessage({required this.id, required this.text});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user_message',
    'id': id,
    'text': text,
  };
}

class ApproveTool extends ClientMessage {
  final String id;
  final String toolCallId;
  final ApproveDecision decision;
  ApproveTool({
    required this.id,
    required this.toolCallId,
    required this.decision,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'approve_tool',
    'id': id,
    'tool_call_id': toolCallId,
    'decision': decision.name,
  };
}

class Cancel extends ClientMessage {
  final String id;
  final String targetId;
  Cancel({required this.id, required this.targetId});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'cancel',
    'id': id,
    'target_id': targetId,
  };
}

class Ping extends ClientMessage {
  final String id;
  Ping({required this.id});

  @override
  Map<String, dynamic> toJson() => {'type': 'ping', 'id': id};
}

class PairRequest extends ClientMessage {
  final String id;
  final String token;
  final String deviceName;
  PairRequest({
    required this.id,
    required this.token,
    required this.deviceName,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'pair_request',
    'id': id,
    'token': token,
    'device_name': deviceName,
  };
}

// --- ServerMessage (extension → app) ---
// 1 pairing = 1 session: no session_id on any message.
// Sealed: all subtypes in this file — switch exhaustiveness enforced by compiler.

sealed class ServerMessage {
  const ServerMessage();

  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'agent_chunk' => AgentChunk.fromJson(json),
      'agent_done' => AgentDone.fromJson(json),
      'tool_request' => ToolRequest.fromJson(json),
      'tool_result' => ToolResult.fromJson(json),
      'error' => ErrorMessage.fromJson(json),
      'cancelled' => Cancelled.fromJson(json),
      'pong' => Pong.fromJson(json),
      'pair_ok' => PairOk.fromJson(json),
      'pair_error' => PairError.fromJson(json),
      // forward-compat: unknown types are not fatal — callers catch and log
      _ => throw UnsupportedTypeException(type ?? ''),
    };
  }
}

class AgentChunk extends ServerMessage {
  final String inReplyTo;
  final String delta;
  AgentChunk({required this.inReplyTo, required this.delta});

  factory AgentChunk.fromJson(Map<String, dynamic> j) => AgentChunk(
    inReplyTo: j['in_reply_to'] as String,
    delta: j['delta'] as String,
  );
}

class AgentDone extends ServerMessage {
  final String inReplyTo;
  final Usage? usage;
  AgentDone({required this.inReplyTo, this.usage});

  factory AgentDone.fromJson(Map<String, dynamic> j) => AgentDone(
    inReplyTo: j['in_reply_to'] as String,
    usage:
        j['usage'] != null
            ? Usage.fromJson(j['usage'] as Map<String, dynamic>)
            : null,
  );
}

class ToolRequest extends ServerMessage {
  final String toolCallId;
  final String tool;
  final dynamic args;
  ToolRequest({required this.toolCallId, required this.tool, required this.args});

  factory ToolRequest.fromJson(Map<String, dynamic> j) => ToolRequest(
    toolCallId: j['tool_call_id'] as String,
    tool: j['tool'] as String,
    args: j['args'],
  );
}

class ToolResult extends ServerMessage {
  final String toolCallId;
  final dynamic result;
  final String? error;
  ToolResult({required this.toolCallId, this.result, this.error});

  factory ToolResult.fromJson(Map<String, dynamic> j) => ToolResult(
    toolCallId: j['tool_call_id'] as String,
    result: j['result'],
    error: j['error'] as String?,
  );
}

class ErrorMessage extends ServerMessage {
  final String? inReplyTo;
  final String code;
  final String message;
  ErrorMessage({this.inReplyTo, required this.code, required this.message});

  factory ErrorMessage.fromJson(Map<String, dynamic> j) => ErrorMessage(
    inReplyTo: j['in_reply_to'] as String?,
    code: j['code'] as String,
    message: j['message'] as String,
  );
}

class Cancelled extends ServerMessage {
  final String inReplyTo;
  final String targetId;
  Cancelled({required this.inReplyTo, required this.targetId});

  factory Cancelled.fromJson(Map<String, dynamic> j) => Cancelled(
    inReplyTo: j['in_reply_to'] as String,
    targetId: j['target_id'] as String,
  );
}

class Pong extends ServerMessage {
  final String inReplyTo;
  Pong({required this.inReplyTo});

  factory Pong.fromJson(Map<String, dynamic> j) =>
      Pong(inReplyTo: j['in_reply_to'] as String);
}

class PairOk extends ServerMessage {
  final String inReplyTo;
  final String sessionName;
  PairOk({required this.inReplyTo, required this.sessionName});

  factory PairOk.fromJson(Map<String, dynamic> j) => PairOk(
    inReplyTo: j['in_reply_to'] as String,
    sessionName: j['session_name'] as String,
  );
}

class PairError extends ServerMessage {
  final String inReplyTo;
  final String code;
  final String message;
  PairError({
    required this.inReplyTo,
    required this.code,
    required this.message,
  });

  factory PairError.fromJson(Map<String, dynamic> j) => PairError(
    inReplyTo: j['in_reply_to'] as String,
    code: j['code'] as String,
    message: j['message'] as String,
  );
}
