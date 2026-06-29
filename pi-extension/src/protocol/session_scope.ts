export type RemoteSessionId = string;

export const SESSION_SCOPED_SERVER_TYPES = [
  "user_input",
  "user_message",
  "queued_message_state",
  "agent_chunk",
  "agent_done",
  "agent_message",
  "compaction",
  "tool_request",
  "tool_result",
  "error",
  "cancelled",
  "session_history",
] as const;

export const NON_SESSION_SCOPED_SERVER_TYPES = [
  "pair_ok",
  "pair_error",
  "pong",
  "bye",
  "action_ok",
  "action_error",
  "models_list",
] as const;

export const SERVER_MESSAGE_TYPES = [
  ...NON_SESSION_SCOPED_SERVER_TYPES,
  ...SESSION_SCOPED_SERVER_TYPES,
] as const;

export const SESSION_SCOPED_CLIENT_TYPES = [
  "user_message",
  "queued_message_set",
  "queued_message_clear",
  "approve_tool",
  "cancel",
  "session_sync",
  "session_new",
  "session_compact",
  "model_set",
  "thinking_set",
  "list_models",
] as const;

export type SessionScopedServerType = typeof SESSION_SCOPED_SERVER_TYPES[number];
export type NonSessionScopedServerType = typeof NON_SESSION_SCOPED_SERVER_TYPES[number];
export type ServerMessageType = typeof SERVER_MESSAGE_TYPES[number];
export type SessionScopedClientType = typeof SESSION_SCOPED_CLIENT_TYPES[number];

const sessionScopedServerTypes = new Set<string>(SESSION_SCOPED_SERVER_TYPES);
const serverMessageTypes = new Set<string>(SERVER_MESSAGE_TYPES);
const sessionScopedClientTypes = new Set<string>(SESSION_SCOPED_CLIENT_TYPES);

export function isSessionScopedServerType(type: string): type is SessionScopedServerType {
  return sessionScopedServerTypes.has(type);
}

export function isServerMessageType(type: string): type is ServerMessageType {
  return serverMessageTypes.has(type);
}

export function isSessionScopedClientType(type: string): type is SessionScopedClientType {
  return sessionScopedClientTypes.has(type);
}
