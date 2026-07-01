// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
/* eslint-disable */

export type JsonValue = null | boolean | number | string | JsonValue[] | { readonly [key: string]: JsonValue };

export const protocolManifest = {
  schemaVersion: 1,
  source: "json-schema-2020-12",
  profile: "compat",
  families: [
    { id: "appPiClient", union: "ClientMessage", transport: "relay-jsonl" },
    { id: "appPiServer", union: "ServerMessage", transport: "relay-jsonl" },
    { id: "relayControl", union: "RelayControlFrame", transport: "relay-jsonl" },
    { id: "crossPc", union: "CrossPcFrame", transport: "relay-jsonl" },
    { id: "cockpitControl", union: "CockpitControlFrame", transport: "pi-custom-event" },
  ],
} as const;

export const appPiClientTypes = [
  "pair_request",
  "user_message",
  "queued_message_set",
  "queued_message_clear",
  "approve_tool",
  "cancel",
  "ping",
  "session_sync",
  "session_new",
  "session_compact",
  "model_set",
  "thinking_set",
  "list_models",
] as const;
export type AppPiClientType = (typeof appPiClientTypes)[number];

export interface ClientMessagePairRequest {
  readonly type: "pair_request";
  readonly id: string;
  readonly token: string;
  readonly device_name: string;
}

export interface ClientMessageUserMessage {
  readonly type: "user_message";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<{
  readonly data: string;
  readonly mime: string;
}>;
  readonly streaming_behavior?: "steer";
}

export interface ClientMessageQueuedMessageSet {
  readonly type: "queued_message_set";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
}

export interface ClientMessageQueuedMessageClear {
  readonly type: "queued_message_clear";
  readonly id: string;
  readonly session_id?: string;
}

export interface ClientMessageApproveTool {
  readonly type: "approve_tool";
  readonly id: string;
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly decision: "allow" | "deny";
}

export interface ClientMessageCancel {
  readonly type: "cancel";
  readonly id: string;
  readonly session_id?: string;
  readonly target_id: string;
}

export interface ClientMessagePing {
  readonly type: "ping";
  readonly id: string;
}

export interface ClientMessageSessionSync {
  readonly type: "session_sync";
  readonly id: string;
  readonly session_id?: string;
  readonly limit?: number;
}

export interface ClientMessageSessionNew {
  readonly type: "session_new";
  readonly id: string;
  readonly session_id?: string;
}

export interface ClientMessageSessionCompact {
  readonly type: "session_compact";
  readonly id: string;
  readonly session_id?: string;
}

export interface ClientMessageModelSet {
  readonly type: "model_set";
  readonly id: string;
  readonly session_id?: string;
  readonly provider: string;
  readonly model_id: string;
}

export interface ClientMessageThinkingSet {
  readonly type: "thinking_set";
  readonly id: string;
  readonly session_id?: string;
  readonly level: "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
}

export interface ClientMessageListModels {
  readonly type: "list_models";
  readonly id: string;
  readonly session_id?: string;
}

export type ClientMessage =
  | ClientMessagePairRequest
  | ClientMessageUserMessage
  | ClientMessageQueuedMessageSet
  | ClientMessageQueuedMessageClear
  | ClientMessageApproveTool
  | ClientMessageCancel
  | ClientMessagePing
  | ClientMessageSessionSync
  | ClientMessageSessionNew
  | ClientMessageSessionCompact
  | ClientMessageModelSet
  | ClientMessageThinkingSet
  | ClientMessageListModels;

export const appPiServerTypes = [
  "pair_ok",
  "pair_error",
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
  "pong",
  "bye",
  "session_history",
  "action_ok",
  "action_error",
  "models_list",
] as const;
export type AppPiServerType = (typeof appPiServerTypes)[number];

export interface ServerMessagePairOk {
  readonly type: "pair_ok";
  readonly in_reply_to: string;
  readonly session_name: string;
  readonly session_started_at: number;
  readonly session_id: string;
  readonly room_id: string;
  readonly harness?: {
  readonly name: string;
  readonly version: string;
};
  readonly hostname?: string;
}

export interface ServerMessagePairError {
  readonly type: "pair_error";
  readonly in_reply_to: string;
  readonly code: "token_expired" | "token_consumed" | "token_unknown" | "internal_error";
  readonly message: string;
}

export interface ServerMessageUserInput {
  readonly type: "user_input";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<{
  readonly data: string;
  readonly mime: string;
}>;
  readonly streaming_behavior?: "steer";
}

export interface ServerMessageUserMessage {
  readonly type: "user_message";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<{
  readonly data: string;
  readonly mime: string;
}>;
  readonly streaming_behavior?: "steer";
}

export interface ServerMessageQueuedMessageState {
  readonly type: "queued_message_state";
  readonly session_id?: string;
  readonly id?: string;
  readonly text?: string;
}

export interface ServerMessageAgentChunk {
  readonly type: "agent_chunk";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly delta: string;
}

export interface ServerMessageAgentDone {
  readonly type: "agent_done";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly usage?: {
  readonly input_tokens: number;
  readonly output_tokens: number;
};
}

export interface ServerMessageAgentMessage {
  readonly type: "agent_message";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly text: string;
  readonly usage?: {
  readonly input_tokens: number;
  readonly output_tokens: number;
};
}

export interface ServerMessageCompaction {
  readonly type: "compaction";
  readonly session_id?: string;
  readonly summary: string;
  readonly tokens_before: number;
  readonly ts?: number;
}

export interface ServerMessageToolRequest {
  readonly type: "tool_request";
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly tool: string;
  readonly args: unknown;
}

export interface ServerMessageToolResult {
  readonly type: "tool_result";
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly result?: unknown;
  readonly error?: string;
}

export interface ServerMessageError {
  readonly type: "error";
  readonly session_id?: string;
  readonly in_reply_to?: string;
  readonly code: string;
  readonly message: string;
}

export interface ServerMessageCancelled {
  readonly type: "cancelled";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly target_id: string;
}

export interface ServerMessagePong {
  readonly type: "pong";
  readonly in_reply_to: string;
}

export interface ServerMessageBye {
  readonly type: "bye";
  readonly reason: "peer_stop" | "session_replaced" | "shutdown";
}

export interface ServerMessageSessionHistory {
  readonly type: "session_history";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly session_started_at: number;
  readonly events: Array<{
  readonly ts: number;
  readonly type: "user_input";
  readonly id: string;
  readonly text: string;
  readonly images?: Array<{
  readonly data: string;
  readonly mime: string;
}>;
} | {
  readonly ts: number;
  readonly type: "tool_request";
  readonly tool_call_id: string;
  readonly tool: string;
  readonly args: unknown;
} | {
  readonly ts: number;
  readonly type: "tool_result";
  readonly tool_call_id: string;
  readonly result?: unknown;
  readonly error?: string;
} | {
  readonly ts: number;
  readonly type: "agent_message";
  readonly in_reply_to: string;
  readonly text: string;
  readonly usage?: {
  readonly input_tokens: number;
  readonly output_tokens: number;
};
} | {
  readonly ts: number;
  readonly type: "compaction";
  readonly summary: string;
  readonly tokens_before: number;
}>;
  readonly eos: boolean;
  readonly truncated: boolean;
}

export interface ServerMessageActionOk {
  readonly type: "action_ok";
  readonly in_reply_to: string;
  readonly action: "session_new" | "session_compact" | "model_set" | "thinking_set";
}

export interface ServerMessageActionError {
  readonly type: "action_error";
  readonly in_reply_to: string;
  readonly action: "session_new" | "session_compact" | "model_set" | "thinking_set";
  readonly error: string;
}

export interface ServerMessageModelsList {
  readonly type: "models_list";
  readonly in_reply_to: string;
  readonly models: Array<{
  readonly id: string;
  readonly name: string;
  readonly provider: string;
  readonly reasoning: boolean;
  readonly context_window: number;
  readonly vision?: boolean;
}>;
  readonly current?: {
  readonly id: string;
  readonly name: string;
  readonly provider: string;
  readonly reasoning: boolean;
  readonly context_window: number;
  readonly vision?: boolean;
};
}

export type ServerMessage =
  | ServerMessagePairOk
  | ServerMessagePairError
  | ServerMessageUserInput
  | ServerMessageUserMessage
  | ServerMessageQueuedMessageState
  | ServerMessageAgentChunk
  | ServerMessageAgentDone
  | ServerMessageAgentMessage
  | ServerMessageCompaction
  | ServerMessageToolRequest
  | ServerMessageToolResult
  | ServerMessageError
  | ServerMessageCancelled
  | ServerMessagePong
  | ServerMessageBye
  | ServerMessageSessionHistory
  | ServerMessageActionOk
  | ServerMessageActionError
  | ServerMessageModelsList;

export const relayControlTypes = [
  "hello",
  "auth",
  "challenge",
  "subscribe_presence",
  "unsubscribe_presence",
  "presence_check",
  "presence",
  "peer_online",
  "peer_offline",
  "subscribe_rooms",
  "unsubscribe_rooms",
  "rooms_check",
  "rooms",
  "room_announced",
  "room_ended",
  "room_meta_update",
] as const;
export type RelayControlType = (typeof relayControlTypes)[number];

export interface RelayControlFrameHello {
  readonly type: "hello";
  readonly pubkey: string;
  readonly room_id?: string;
  readonly room_meta?: {
  readonly name?: string;
  readonly cwd?: string;
  readonly model?: string;
  readonly thinking?: string;
  readonly session_id?: string;
  readonly working?: boolean;
};
}

export interface RelayControlFrameAuth {
  readonly type: "auth";
  readonly sig: string;
}

export interface RelayControlFrameChallenge {
  readonly type: "challenge";
  readonly nonce: string;
}

export interface RelayControlFrameSubscribePresence {
  readonly type: "subscribe_presence";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameUnsubscribePresence {
  readonly type: "unsubscribe_presence";
  readonly peers?: Array<string>;
}

export interface RelayControlFramePresenceCheck {
  readonly type: "presence_check";
  readonly peers?: Array<string>;
}

export interface RelayControlFramePresence {
  readonly type: "presence";
  readonly states: Array<{
  readonly peer: string;
  readonly online: boolean;
  readonly since_ts?: number | null;
}>;
}

export interface RelayControlFramePeerOnline {
  readonly type: "peer_online";
  readonly peer: string;
}

export interface RelayControlFramePeerOffline {
  readonly type: "peer_offline";
  readonly peer: string;
  readonly since_ts: number;
}

export interface RelayControlFrameSubscribeRooms {
  readonly type: "subscribe_rooms";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameUnsubscribeRooms {
  readonly type: "unsubscribe_rooms";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameRoomsCheck {
  readonly type: "rooms_check";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameRooms {
  readonly type: "rooms";
  readonly peer: string;
  readonly rooms: Array<{
  readonly room_id: string;
  readonly name?: string;
  readonly cwd?: string;
  readonly session_id?: string;
  readonly model?: string;
  readonly thinking?: string;
  readonly working: boolean;
  readonly started_at: number;
}>;
}

export interface RelayControlFrameRoomAnnounced {
  readonly type: "room_announced";
  readonly peer: string;
  readonly room_id: string;
  readonly name?: string;
  readonly cwd?: string;
  readonly session_id?: string;
  readonly model?: string;
  readonly thinking?: string;
  readonly working: boolean;
  readonly started_at: number;
}

export interface RelayControlFrameRoomEnded {
  readonly type: "room_ended";
  readonly peer: string;
  readonly room_id: string;
  readonly since_ts: number;
}

export interface RelayControlFrameRoomMetaUpdate {
  readonly type: "room_meta_update";
  readonly room_id?: string;
  readonly meta: {
  readonly model?: string | null;
  readonly thinking?: string | null;
  readonly session_id?: string | null;
  readonly working?: boolean;
};
}

export type RelayControlFrame =
  | RelayControlFrameHello
  | RelayControlFrameAuth
  | RelayControlFrameChallenge
  | RelayControlFrameSubscribePresence
  | RelayControlFrameUnsubscribePresence
  | RelayControlFramePresenceCheck
  | RelayControlFramePresence
  | RelayControlFramePeerOnline
  | RelayControlFramePeerOffline
  | RelayControlFrameSubscribeRooms
  | RelayControlFrameUnsubscribeRooms
  | RelayControlFrameRoomsCheck
  | RelayControlFrameRooms
  | RelayControlFrameRoomAnnounced
  | RelayControlFrameRoomEnded
  | RelayControlFrameRoomMetaUpdate;

export const crossPcTypes = [
  "pi_envelope",
  "pi_envelope_in",
] as const;
export type CrossPcType = (typeof crossPcTypes)[number];

export interface CrossPcFramePiEnvelope {
  readonly type: "pi_envelope";
  readonly to_pc: string;
  readonly envelope: {
  readonly from: string;
  readonly to: string | Array<string>;
  readonly id: string;
  readonly re: string | null;
  readonly body: unknown;
};
}

export interface CrossPcFramePiEnvelopeIn {
  readonly type: "pi_envelope_in";
  readonly from_pc: string;
  readonly envelope: {
  readonly from: "_relay";
  readonly to: string;
  readonly id: string;
  readonly re: string | null;
  readonly body: {
  readonly type: "transport_error";
  readonly reason: "offline" | "not_authorized" | "bad_envelope";
};
} | {
  readonly from: string;
  readonly to: string | Array<string>;
  readonly id: string;
  readonly re: string | null;
  readonly body: unknown;
};
}

export type CrossPcFrame =
  | CrossPcFramePiEnvelope
  | CrossPcFramePiEnvelopeIn;

export const cockpitControlTypes = [
  "prompt",
  "remote_pi_control",
  "remote-pi:relay-state",
  "remote-pi:name-assigned",
  "remote-pi:pair-code",
  "remote-pi:paired",
  "remote-pi:mesh-revoked",
] as const;
export type CockpitControlType = (typeof cockpitControlTypes)[number];

export interface CockpitControlFramePrompt {
  readonly type: "prompt";
  readonly message: string;
}

export interface CockpitControlFrameRemotePiControl {
  readonly type: "remote_pi_control";
  readonly command: "relay_on" | "relay_off" | "relay_toggle" | "relay_status" | "rename";
  readonly name?: string;
}

export interface CockpitControlFrameRemotePiRelayState {
  readonly role: "custom";
  readonly customType: "remote-pi:relay-state" | "remote-pi:name-assigned" | "remote-pi:pair-code" | "remote-pi:paired" | "remote-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameRemotePiNameAssigned {
  readonly role: "custom";
  readonly customType: "remote-pi:relay-state" | "remote-pi:name-assigned" | "remote-pi:pair-code" | "remote-pi:paired" | "remote-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameRemotePiPairCode {
  readonly role: "custom";
  readonly customType: "remote-pi:relay-state" | "remote-pi:name-assigned" | "remote-pi:pair-code" | "remote-pi:paired" | "remote-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameRemotePiPaired {
  readonly role: "custom";
  readonly customType: "remote-pi:relay-state" | "remote-pi:name-assigned" | "remote-pi:pair-code" | "remote-pi:paired" | "remote-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameRemotePiMeshRevoked {
  readonly role: "custom";
  readonly customType: "remote-pi:relay-state" | "remote-pi:name-assigned" | "remote-pi:pair-code" | "remote-pi:paired" | "remote-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export type CockpitControlFrame =
  | CockpitControlFramePrompt
  | CockpitControlFrameRemotePiControl
  | CockpitControlFrameRemotePiRelayState
  | CockpitControlFrameRemotePiNameAssigned
  | CockpitControlFrameRemotePiPairCode
  | CockpitControlFrameRemotePiPaired
  | CockpitControlFrameRemotePiMeshRevoked;
