// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
/* eslint-disable */

export type JsonValue = null | boolean | number | string | JsonValue[] | { readonly [key: string]: JsonValue };

export type StreamingBehavior = "steer";

export interface WireImage {
  readonly data: string;
  readonly mime: string;
}

export interface Usage {
  readonly input_tokens: number;
  readonly output_tokens: number;
}

export type PairErrorCode = "token_expired" | "token_consumed" | "token_unknown" | "internal_error";

export type KnownErrorCode = "tool_approval_required" | "invalid_message" | "unsupported_type" | "too_large" | "rate_limited" | "timeout" | "internal_error" | "session_mismatch";

export type ErrorCode = KnownErrorCode | (string & {});

export type ActionName = "session_new" | "session_compact" | "model_set" | "thinking_set";

export type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";

export interface WireModel {
  readonly id: string;
  readonly name: string;
  readonly provider: string;
  readonly reasoning: boolean;
  readonly context_window: number;
  readonly vision?: boolean;
}

export type ByeReason = "peer_stop" | "session_replaced" | "shutdown";

export interface HistoryUserInput {
  readonly ts: number;
  readonly type: "user_input";
  readonly id: string;
  readonly text: string;
  readonly images?: Array<WireImage>;
}

export interface HistoryToolRequest {
  readonly ts: number;
  readonly type: "tool_request";
  readonly tool_call_id: string;
  readonly tool: string;
  readonly args: unknown;
}

export interface HistoryToolResult {
  readonly ts: number;
  readonly type: "tool_result";
  readonly tool_call_id: string;
  readonly result?: unknown;
  readonly error?: string;
}

export interface HistoryAgentMessage {
  readonly ts: number;
  readonly type: "agent_message";
  readonly in_reply_to: string;
  readonly text: string;
  readonly usage?: Usage;
}

export interface HistoryCompaction {
  readonly ts: number;
  readonly type: "compaction";
  readonly summary: string;
  readonly tokens_before: number;
}

export type SessionHistoryEvent =
  | HistoryUserInput
  | HistoryToolRequest
  | HistoryToolResult
  | HistoryAgentMessage
  | HistoryCompaction;

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

export interface PairRequest {
  readonly type: "pair_request";
  readonly id: string;
  readonly token: string;
  readonly device_name: string;
}

export interface UserMessage {
  readonly type: "user_message";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<WireImage>;
  readonly streaming_behavior?: StreamingBehavior;
}

export interface QueuedMessageSet {
  readonly type: "queued_message_set";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
}

export interface QueuedMessageClear {
  readonly type: "queued_message_clear";
  readonly id: string;
  readonly session_id?: string;
}

export interface ApproveTool {
  readonly type: "approve_tool";
  readonly id: string;
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly decision: "allow" | "deny";
}

export interface Cancel {
  readonly type: "cancel";
  readonly id: string;
  readonly session_id?: string;
  readonly target_id: string;
}

export interface Ping {
  readonly type: "ping";
  readonly id: string;
}

export interface SessionSync {
  readonly type: "session_sync";
  readonly id: string;
  readonly session_id?: string;
  readonly limit?: number;
}

export interface SessionNew {
  readonly type: "session_new";
  readonly id: string;
  readonly session_id?: string;
}

export interface SessionCompact {
  readonly type: "session_compact";
  readonly id: string;
  readonly session_id?: string;
}

export interface ModelSet {
  readonly type: "model_set";
  readonly id: string;
  readonly session_id?: string;
  readonly provider: string;
  readonly model_id: string;
}

export interface ThinkingSet {
  readonly type: "thinking_set";
  readonly id: string;
  readonly session_id?: string;
  readonly level: ThinkingLevel;
}

export interface ListModels {
  readonly type: "list_models";
  readonly id: string;
  readonly session_id?: string;
}

export type ClientMessage =
  | PairRequest
  | UserMessage
  | QueuedMessageSet
  | QueuedMessageClear
  | ApproveTool
  | Cancel
  | Ping
  | SessionSync
  | SessionNew
  | SessionCompact
  | ModelSet
  | ThinkingSet
  | ListModels;

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

export interface PairOk {
  readonly type: "pair_ok";
  readonly in_reply_to: string;
  readonly session_name: string;
  readonly session_started_at: number;
  readonly session_id?: string;
  readonly room_id: string;
  readonly harness?: {
  readonly name: string;
  readonly version: string;
};
  readonly hostname?: string;
}

export interface PairError {
  readonly type: "pair_error";
  readonly in_reply_to: string;
  readonly code: PairErrorCode;
  readonly message: string;
}

export interface UserInput {
  readonly type: "user_input";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<WireImage>;
  readonly streaming_behavior?: StreamingBehavior;
}

export interface QueuedMessageState {
  readonly type: "queued_message_state";
  readonly session_id?: string;
  readonly id?: string;
  readonly text?: string;
}

export interface AgentChunk {
  readonly type: "agent_chunk";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly delta: string;
}

export interface AgentDone {
  readonly type: "agent_done";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly usage?: Usage;
}

export interface AgentMessage {
  readonly type: "agent_message";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly text: string;
  readonly usage?: Usage;
}

export interface Compaction {
  readonly type: "compaction";
  readonly session_id?: string;
  readonly summary: string;
  readonly tokens_before: number;
  readonly ts?: number;
}

export interface ToolRequest {
  readonly type: "tool_request";
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly tool: string;
  readonly args: unknown;
}

export interface ToolResult {
  readonly type: "tool_result";
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly result?: unknown;
  readonly error?: string;
}

export interface ErrorMessage {
  readonly type: "error";
  readonly session_id?: string;
  readonly in_reply_to?: string;
  readonly code: ErrorCode;
  readonly message: string;
}

export interface Cancelled {
  readonly type: "cancelled";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly target_id: string;
}

export interface Pong {
  readonly type: "pong";
  readonly in_reply_to: string;
}

export interface Bye {
  readonly type: "bye";
  readonly reason: ByeReason;
}

export interface SessionHistory {
  readonly type: "session_history";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly session_started_at: number;
  readonly events: Array<SessionHistoryEvent>;
  readonly eos: boolean;
  readonly truncated: boolean;
}

export interface ActionOk {
  readonly type: "action_ok";
  readonly in_reply_to: string;
  readonly action: ActionName;
}

export interface ActionError {
  readonly type: "action_error";
  readonly in_reply_to: string;
  readonly action: ActionName;
  readonly error: string;
}

export interface ModelsList {
  readonly type: "models_list";
  readonly in_reply_to: string;
  readonly models: Array<WireModel>;
  readonly current?: WireModel;
}

export type ServerMessage =
  | PairOk
  | PairError
  | UserInput
  | UserMessage
  | QueuedMessageState
  | AgentChunk
  | AgentDone
  | AgentMessage
  | Compaction
  | ToolRequest
  | ToolResult
  | ErrorMessage
  | Cancelled
  | Pong
  | Bye
  | SessionHistory
  | ActionOk
  | ActionError
  | ModelsList;

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
