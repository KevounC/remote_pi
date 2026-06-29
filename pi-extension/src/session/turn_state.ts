export const TURN_STATE_TAGS = [
  "idle",
  "working",
  "awaiting_tool",
  "streaming",
  "done",
  "error",
] as const;

export type TurnStateTag = (typeof TURN_STATE_TAGS)[number];
export type TurnSource = "app" | "queued" | "local" | "rpc" | "compaction";
export type TurnErrorReason =
  | "provider_error"
  | "delivery_error"
  | "cancelled"
  | "session_shutdown";

export interface QueuedMessage {
  id: string;
  text: string;
}

export type TurnState =
  | { tag: "idle" }
  | { tag: "working"; turnId: string; replyTo: string; source: TurnSource }
  | { tag: "awaiting_tool"; turnId: string; replyTo: string; toolCallId: string }
  | { tag: "streaming"; turnId: string; replyTo: string }
  | { tag: "done"; turnId: string; awaitingSync: true; collectLateAttach: boolean }
  | { tag: "error"; turnId: string | null; reason: TurnErrorReason };

export interface TurnSnapshot {
  state: TurnState;
  queuedMessage: QueuedMessage | null;
  peersAttachedDuringTurn: ReadonlySet<string>;
}

export type TurnEvent =
  | { type: "user_message_accepted"; turnId: string; replyTo?: string; source?: Exclude<TurnSource, "compaction"> }
  | { type: "local_input"; turnId: string; replyTo?: string; source?: "local" | "rpc" }
  | { type: "turn_start"; fallbackTurnId: string }
  | { type: "agent_chunk"; replyTo?: string }
  | { type: "tool_execution_start"; toolCallId: string }
  | { type: "tool_execution_end"; toolCallId?: string }
  | { type: "agent_done"; collectLateAttach?: boolean }
  | { type: "turn_end" }
  | { type: "provider_error"; turnId?: string | null }
  | { type: "delivery_error"; turnId?: string | null }
  | { type: "cancelled"; turnId?: string | null }
  | { type: "session_shutdown" }
  | { type: "compaction_start"; turnId: string; replyTo?: string }
  | { type: "compaction_done" }
  | { type: "peer_attached"; peerId: string }
  | { type: "queued_message_set"; id: string; text: string }
  | { type: "queued_message_clear" };

export interface TurnProjection {
  working: boolean;
  activeTurnId: string | null;
  cancelTargetId: string | null;
  awaitingSyncTurnId: string | null;
  canDrainQueuedMessage: boolean;
  phase: TurnStateTag;
  peersAttachedDuringTurn: readonly string[];
  queuedMessage: QueuedMessage | null;
}

export function initialTurnSnapshot(): TurnSnapshot {
  return {
    state: { tag: "idle" },
    queuedMessage: null,
    peersAttachedDuringTurn: new Set<string>(),
  };
}

export function reduceTurn(snapshot: TurnSnapshot, event: TurnEvent): TurnSnapshot {
  switch (event.type) {
    case "queued_message_set":
      return withQueued(snapshot, { id: event.id, text: event.text });
    case "queued_message_clear":
      return withQueued(snapshot, null);
    case "peer_attached":
      if (!isActive(snapshot.state)) return snapshot;
      return {
        ...snapshot,
        peersAttachedDuringTurn: new Set([...snapshot.peersAttachedDuringTurn, event.peerId]),
      };
    case "user_message_accepted":
      return seedTurn(snapshot, event.turnId, event.replyTo ?? event.turnId, event.source ?? "app");
    case "local_input":
      return seedTurn(snapshot, event.turnId, event.replyTo ?? event.turnId, event.source ?? "local");
    case "turn_start":
      if (isActive(snapshot.state)) return snapshot;
      return {
        ...snapshot,
        state: { tag: "working", turnId: event.fallbackTurnId, replyTo: event.fallbackTurnId, source: "local" },
        peersAttachedDuringTurn: new Set<string>(),
      };
    case "agent_chunk":
      return transitionActive(snapshot, (state) => ({
        tag: "streaming",
        turnId: state.turnId,
        replyTo: event.replyTo ?? state.replyTo,
      }));
    case "tool_execution_start":
      return transitionActive(snapshot, (state) => ({
        tag: "awaiting_tool",
        turnId: state.turnId,
        replyTo: state.replyTo,
        toolCallId: event.toolCallId,
      }));
    case "tool_execution_end":
      if (snapshot.state.tag !== "awaiting_tool") return snapshot;
      if (event.toolCallId !== undefined && event.toolCallId !== snapshot.state.toolCallId) return snapshot;
      return {
        ...snapshot,
        state: {
          tag: "working",
          turnId: snapshot.state.turnId,
          replyTo: snapshot.state.replyTo,
          source: "local",
        },
      };
    case "agent_done":
      if (!isActive(snapshot.state)) return snapshot;
      return {
        ...snapshot,
        state: {
          tag: "done",
          turnId: snapshot.state.turnId,
          awaitingSync: true,
          collectLateAttach: event.collectLateAttach ?? snapshot.peersAttachedDuringTurn.size > 0,
        },
      };
    case "turn_end":
      if (snapshot.state.tag === "idle") return snapshot;
      return { ...snapshot, state: { tag: "idle" }, peersAttachedDuringTurn: new Set<string>() };
    case "provider_error":
      return terminalError(snapshot, "provider_error", event.turnId);
    case "delivery_error":
      return terminalError(snapshot, "delivery_error", event.turnId);
    case "cancelled":
      return terminalError(snapshot, "cancelled", event.turnId);
    case "session_shutdown":
      return {
        state: { tag: "error", turnId: activeTurnId(snapshot.state), reason: "session_shutdown" },
        queuedMessage: null,
        peersAttachedDuringTurn: new Set<string>(),
      };
    case "compaction_start":
      return {
        ...snapshot,
        state: { tag: "working", turnId: event.turnId, replyTo: event.replyTo ?? event.turnId, source: "compaction" },
        peersAttachedDuringTurn: new Set<string>(),
      };
    case "compaction_done":
      if (!isActive(snapshot.state)) return snapshot;
      return {
        ...snapshot,
        state: { tag: "done", turnId: snapshot.state.turnId, awaitingSync: true, collectLateAttach: false },
      };
  }
}

export function projectTurn(snapshot: TurnSnapshot): TurnProjection {
  const state = snapshot.state;
  const working = state.tag === "working" || state.tag === "awaiting_tool" || state.tag === "streaming";
  return {
    working,
    activeTurnId: working ? state.turnId : null,
    cancelTargetId: working ? state.turnId : null,
    awaitingSyncTurnId: state.tag === "done" && state.awaitingSync ? state.turnId : null,
    canDrainQueuedMessage: snapshot.queuedMessage !== null && state.tag === "idle",
    phase: state.tag,
    peersAttachedDuringTurn: [...snapshot.peersAttachedDuringTurn].sort(),
    queuedMessage: snapshot.queuedMessage,
  };
}

function withQueued(snapshot: TurnSnapshot, queuedMessage: QueuedMessage | null): TurnSnapshot {
  return { ...snapshot, queuedMessage };
}

function seedTurn(snapshot: TurnSnapshot, turnId: string, replyTo: string, source: Exclude<TurnSource, "compaction">): TurnSnapshot {
  if (isActive(snapshot.state)) return snapshot;
  return {
    ...snapshot,
    state: { tag: "working", turnId, replyTo, source },
    peersAttachedDuringTurn: new Set<string>(),
  };
}

function transitionActive(snapshot: TurnSnapshot, next: (state: ActiveTurnState) => TurnState): TurnSnapshot {
  if (!isActive(snapshot.state)) return snapshot;
  return { ...snapshot, state: next(snapshot.state) };
}

type ActiveTurnState = Extract<TurnState, { tag: "working" | "awaiting_tool" | "streaming" }>;

function isActive(state: TurnState): state is ActiveTurnState {
  return state.tag === "working" || state.tag === "awaiting_tool" || state.tag === "streaming";
}

function activeTurnId(state: TurnState): string | null {
  if (isActive(state)) return state.turnId;
  if (state.tag === "done") return state.turnId;
  if (state.tag === "error") return state.turnId;
  return null;
}

function terminalError(snapshot: TurnSnapshot, reason: TurnErrorReason, turnId?: string | null): TurnSnapshot {
  return {
    ...snapshot,
    state: { tag: "error", turnId: turnId ?? activeTurnId(snapshot.state), reason },
    peersAttachedDuringTurn: new Set<string>(),
  };
}
