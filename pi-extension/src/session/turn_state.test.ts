import { describe, expect, test } from "vitest";
import {
  initialTurnSnapshot,
  projectTurn,
  reduceTurn,
  TURN_STATE_TAGS,
  type TurnEvent,
} from "./turn_state.js";

function reduce(events: TurnEvent[]) {
  return events.reduce(reduceTurn, initialTurnSnapshot());
}

describe("turn state reducer", () => {
  test("exposes the canonical tag registry", () => {
    expect(TURN_STATE_TAGS).toEqual(["idle", "working", "awaiting_tool", "streaming", "done", "error"]);
  });

  test("projects working only for active phases", () => {
    const idle = initialTurnSnapshot();
    expect(projectTurn(idle)).toMatchObject({ working: false, activeTurnId: null, cancelTargetId: null });

    const working = reduce([{ type: "user_message_accepted", turnId: "u1" }]);
    expect(projectTurn(working)).toMatchObject({ phase: "working", working: true, activeTurnId: "u1", cancelTargetId: "u1" });

    const streaming = reduce([
      { type: "user_message_accepted", turnId: "u1" },
      { type: "agent_chunk" },
    ]);
    expect(projectTurn(streaming)).toMatchObject({ phase: "streaming", working: true });

    const tool = reduce([
      { type: "user_message_accepted", turnId: "u1" },
      { type: "tool_execution_start", toolCallId: "tool-1" },
    ]);
    expect(projectTurn(tool)).toMatchObject({ phase: "awaiting_tool", working: true });

    const done = reduce([
      { type: "user_message_accepted", turnId: "u1" },
      { type: "agent_done" },
    ]);
    expect(projectTurn(done)).toMatchObject({ phase: "done", working: false, awaitingSyncTurnId: "u1", cancelTargetId: null });

    const error = reduce([
      { type: "user_message_accepted", turnId: "u1" },
      { type: "provider_error" },
    ]);
    expect(projectTurn(error)).toMatchObject({ phase: "error", working: false, cancelTargetId: null });
  });

  test("models a normal app turn through streaming, done, and idle", () => {
    const snapshot = reduce([
      { type: "user_message_accepted", turnId: "cli-1" },
      { type: "turn_start", fallbackTurnId: "local-ignored" },
      { type: "agent_chunk" },
      { type: "agent_done" },
    ]);

    expect(projectTurn(snapshot)).toMatchObject({
      phase: "done",
      working: false,
      awaitingSyncTurnId: "cli-1",
    });

    const readyToFlush = reduceTurn(snapshot, { type: "turn_end" });
    expect(projectTurn(readyToFlush)).toMatchObject({
      phase: "done",
      working: false,
      awaitingSyncTurnId: "cli-1",
      canFlushLateAttachSync: true,
    });

    const idle = reduceTurn(readyToFlush, { type: "flush_late_attach_sync" });
    expect(projectTurn(idle)).toMatchObject({ phase: "idle", working: false, awaitingSyncTurnId: null });
  });

  test("seeds a local/RPC turn from turn_start when no app id exists", () => {
    const snapshot = reduce([{ type: "turn_start", fallbackTurnId: "local-1" }]);
    expect(projectTurn(snapshot)).toMatchObject({ phase: "working", activeTurnId: "local-1", working: true });
  });

  test("steering while active preserves the current turn id and reply target", () => {
    const snapshot = reduce([
      { type: "user_message_accepted", turnId: "cli-1" },
      { type: "agent_chunk" },
      { type: "user_message_accepted", turnId: "cli-2", source: "app" },
    ]);

    expect(projectTurn(snapshot)).toMatchObject({ phase: "streaming", activeTurnId: "cli-1" });
  });

  test("tool start and end stay in the same turn", () => {
    const snapshot = reduce([
      { type: "user_message_accepted", turnId: "cli-1" },
      { type: "tool_execution_start", toolCallId: "tool-1" },
      { type: "tool_execution_end", toolCallId: "tool-1" },
    ]);

    expect(projectTurn(snapshot)).toMatchObject({ phase: "working", activeTurnId: "cli-1", working: true });
  });

  test("provider error, delivery error, cancel, and shutdown converge working false", () => {
    const cases: Array<[string, TurnEvent[]]> = [
      ["provider", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "provider_error" }]],
      ["delivery", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "delivery_error" }]],
      ["cancel", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "cancelled" }]],
      ["shutdown", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "session_shutdown" }]],
    ];

    for (const [, events] of cases) {
      expect(projectTurn(reduce(events))).toMatchObject({ working: false, cancelTargetId: null });
    }
  });

  test("compaction is a synthetic working turn that converges false", () => {
    const compacting = reduce([{ type: "compaction_start", turnId: "compact-1" }]);
    expect(projectTurn(compacting)).toMatchObject({ phase: "working", working: true, activeTurnId: "compact-1" });

    const done = reduceTurn(compacting, { type: "compaction_done" });
    expect(projectTurn(done)).toMatchObject({ phase: "done", working: false, awaitingSyncTurnId: "compact-1" });

    const readyToFlush = reduceTurn(done, { type: "turn_end" });
    expect(projectTurn(readyToFlush)).toMatchObject({ phase: "done", working: false, canFlushLateAttachSync: true });

    const idle = reduceTurn(readyToFlush, { type: "flush_late_attach_sync" });
    expect(projectTurn(idle)).toMatchObject({ phase: "idle", working: false });
  });

  test("records late-attach owners only during an active turn and dedupes by kind/id", () => {
    let snapshot = reduceTurn(initialTurnSnapshot(), { type: "peer_attached", target: { kind: "owner", id: "peer-idle" } });
    expect(projectTurn(snapshot).peersAttachedDuringTurn).toEqual([]);

    snapshot = reduceTurn(snapshot, { type: "user_message_accepted", turnId: "cli-1" });
    snapshot = reduceTurn(snapshot, { type: "peer_attached", target: { kind: "owner", id: "peer-b" } });
    snapshot = reduceTurn(snapshot, { type: "peer_attached", target: { kind: "owner", id: "peer-a" } });
    snapshot = reduceTurn(snapshot, { type: "peer_attached", target: { kind: "owner", id: "peer-a" } });
    expect(projectTurn(snapshot).peersAttachedDuringTurn).toEqual(["peer-a", "peer-b"]);

    snapshot = reduceTurn(snapshot, { type: "agent_done" });
    expect(snapshot.state).toMatchObject({ tag: "done", collectLateAttach: true });
    expect(projectTurn(snapshot)).toMatchObject({
      working: false,
      awaitingSyncTurnId: "cli-1",
      lateAttachSyncTargets: [
        { kind: "owner", id: "peer-a" },
        { kind: "owner", id: "peer-b" },
      ],
    });
  });

  test("queued messages drain only when idle and survive normal turns", () => {
    let snapshot = reduceTurn(initialTurnSnapshot(), { type: "queued_message_set", id: "q1", text: "next" });
    expect(projectTurn(snapshot)).toMatchObject({ canDrainQueuedMessage: true, queuedMessage: { id: "q1", text: "next" } });

    snapshot = reduceTurn(snapshot, { type: "user_message_accepted", turnId: "cli-1" });
    expect(projectTurn(snapshot)).toMatchObject({ canDrainQueuedMessage: false, queuedMessage: { id: "q1", text: "next" } });

    snapshot = reduceTurn(snapshot, { type: "agent_done" });
    snapshot = reduceTurn(snapshot, { type: "turn_end" });
    expect(projectTurn(snapshot)).toMatchObject({ canDrainQueuedMessage: false, canFlushLateAttachSync: true, queuedMessage: { id: "q1", text: "next" } });

    snapshot = reduceTurn(snapshot, { type: "flush_late_attach_sync" });
    expect(projectTurn(snapshot)).toMatchObject({ canDrainQueuedMessage: true, queuedMessage: { id: "q1", text: "next" } });

    snapshot = reduceTurn(snapshot, { type: "queued_message_clear" });
    expect(projectTurn(snapshot)).toMatchObject({ canDrainQueuedMessage: false, queuedMessage: null });
  });

  test("late-attach targets are collected from working, streaming, and awaiting-tool phases", () => {
    const cases: TurnEvent[][] = [
      [{ type: "user_message_accepted", turnId: "cli-1" }],
      [{ type: "user_message_accepted", turnId: "cli-1" }, { type: "agent_chunk" }],
      [{ type: "user_message_accepted", turnId: "cli-1" }, { type: "tool_execution_start", toolCallId: "tool-1" }],
    ];

    for (const events of cases) {
      const snapshot = reduce([
        ...events,
        { type: "peer_attached", target: { kind: "owner", id: "owner-1" } },
        { type: "peer_attached", target: { kind: "mesh_bridge", id: "bridge-1" } },
        { type: "agent_done" },
      ]);

      expect(projectTurn(snapshot)).toMatchObject({
        working: false,
        awaitingSyncTurnId: "cli-1",
        lateAttachSyncTargets: [
          { kind: "mesh_bridge", id: "bridge-1" },
          { kind: "owner", id: "owner-1" },
        ],
      });
    }
  });

  test("turn_end plus flush_late_attach_sync clears targets before queued drain", () => {
    let snapshot = reduce([
      { type: "queued_message_set", id: "q1", text: "next" },
      { type: "user_message_accepted", turnId: "cli-1" },
      { type: "peer_attached", target: { kind: "owner", id: "owner-1" } },
      { type: "agent_done" },
      { type: "turn_end" },
    ]);

    expect(projectTurn(snapshot)).toMatchObject({
      phase: "done",
      working: false,
      canFlushLateAttachSync: true,
      canDrainQueuedMessage: false,
      lateAttachSyncTargets: [{ kind: "owner", id: "owner-1" }],
    });

    snapshot = reduceTurn(snapshot, { type: "flush_late_attach_sync" });
    expect(projectTurn(snapshot)).toMatchObject({
      phase: "idle",
      canFlushLateAttachSync: false,
      canDrainQueuedMessage: true,
      lateAttachSyncTargets: [],
    });
  });

  test("session shutdown clears queued ownership and stale late-attach state", () => {
    const snapshot = reduce([
      { type: "queued_message_set", id: "q1", text: "next" },
      { type: "user_message_accepted", turnId: "cli-1" },
      { type: "peer_attached", peerId: "peer-a" },
      { type: "session_shutdown" },
    ]);

    expect(projectTurn(snapshot)).toMatchObject({
      phase: "error",
      working: false,
      queuedMessage: null,
      peersAttachedDuringTurn: [],
      lateAttachSyncTargets: [],
    });
  });

  test("all terminal causes converge to idle projection with no cancel target", () => {
    const terminalCases: Array<[string, TurnEvent[]]> = [
      ["success", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "agent_done" }]],
      ["provider error", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "provider_error" }, { type: "turn_end" }]],
      ["cancel/abort", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "cancelled" }, { type: "turn_end" }]],
      ["compaction", [{ type: "compaction_start", turnId: "c1" }, { type: "compaction_done" }]],
      ["session replacement/shutdown", [{ type: "turn_start", fallbackTurnId: "u1" }, { type: "session_shutdown" }]],
      ["reconnect late-attach recovery", [
        { type: "turn_start", fallbackTurnId: "u1" },
        { type: "peer_attached", target: { kind: "owner", id: "late-owner" } },
        { type: "agent_done" },
        { type: "turn_end" },
        { type: "flush_late_attach_sync" },
      ]],
    ];

    for (const [name, events] of terminalCases) {
      const projection = projectTurn(reduce(events));
      expect(projection.working, name).toBe(false);
      expect(projection.activeTurnId, name).toBeNull();
      expect(projection.cancelTargetId, name).toBeNull();
    }
  });

  test("Done(awaitingSync) is explicit in the projection before late-attach flush", () => {
    const projection = projectTurn(reduce([
      { type: "turn_start", fallbackTurnId: "u1" },
      { type: "peer_attached", target: { kind: "owner", id: "late-owner" } },
      { type: "agent_done" },
      { type: "turn_end" },
    ]));

    expect(projection).toMatchObject({
      phase: "done",
      working: false,
      activeTurnId: null,
      cancelTargetId: null,
      awaitingSyncTurnId: "u1",
      canFlushLateAttachSync: true,
      lateAttachSyncTargets: [{ kind: "owner", id: "late-owner" }],
    });
  });

  test("queued message drain becomes legal after every drain-preserving terminal state reaches idle", () => {
    const terminalCases: Array<[string, TurnEvent[]]> = [
      ["success", [{ type: "agent_done" }, { type: "turn_end" }, { type: "flush_late_attach_sync" }]],
      ["provider error", [{ type: "provider_error" }, { type: "turn_end" }]],
      ["cancel/abort", [{ type: "cancelled" }, { type: "turn_end" }]],
      ["compaction", [{ type: "compaction_done" }, { type: "turn_end" }, { type: "flush_late_attach_sync" }]],
    ];

    for (const [name, terminalEvents] of terminalCases) {
      const projection = projectTurn(reduce([
        { type: "queued_message_set", id: "q1", text: "next" },
        { type: "turn_start", fallbackTurnId: name === "compaction" ? "ignored" : "u1" },
        ...(name === "compaction" ? [{ type: "compaction_start", turnId: "c1" } as const] : []),
        ...terminalEvents,
      ]));
      expect(projection.phase, name).toBe("idle");
      expect(projection.canDrainQueuedMessage, name).toBe(true);
      expect(projection.queuedMessage, name).toEqual({ id: "q1", text: "next" });
    }
  });
});
