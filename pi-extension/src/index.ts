#!/usr/bin/env node
/**
 * pi-extension — remote-pi slash commands + AgentBridge wiring
 *
 * Exported as ExtensionFactory (default export) to be loaded by Pi SDK:
 *   pi -e $(pwd)/dist/index.js
 *
 * State machine:  idle → started → paired
 *   /remote-pi start   connects to relay (idle → started)
 *   /remote-pi pair    shows QR for new peers (started, async → paired via auto-listener)
 *   /remote-pi stop    closes everything (any → idle)
 *
 * Pairing (post plano 06 — sem Noise XX):
 *   App envia inner `pair_request` (id, token, device_name) sobre canal opaco.
 *   Pi valida o token via qrSession.consumeToken, salva peer em peers.json
 *   {name, remote_epk, paired_at} e responde com `pair_ok` (ou `pair_error`).
 *   `ct` é base64(JSON.stringify(inner)) — sem cifra, sem MAC.
 *
 * Reconexão de peer conhecido:
 *   Se uma mensagem chega em estado `started` vinda de um epk presente em
 *   peers.json, o auto-listener promove direto pra `paired` sem novo
 *   pair_request, criando o PlainPeerChannel e roteando a mensagem.
 *
 * Architecture note — why we don't use AgentBridge directly here:
 *   AgentBridge.beforeToolCallHook is designed to be passed to createAgentSession().
 *   Inside an extension Pi already owns the AgentSession, so we can't re-bind
 *   beforeToolCall after the fact. The equivalent is pi.on("tool_call", …) which
 *   fires BEFORE execution and supports { block: true }.
 *   AgentBridge (src/session/agent_bridge.ts) remains the tested, mockable unit
 *   for integration tests.
 */

import { randomUUID } from "node:crypto";
import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  ExtensionFactory,
} from "@earendil-works/pi-coding-agent";
import { qrSession } from "./pairing/qr.js";
import { addPeer, listPeers } from "./pairing/storage.js";
import type {
  ClientMessage,
  ServerMessage,
  SessionHistoryEvent,
  ThinkingLevel,
} from "./protocol/types.js";
import type { TranscriptEvent } from "./session/transcript_event.js";
import {
  appendTranscriptEvent,
  deterministicTranscriptEventId,
  imagesFromContent,
  mapLegacyAgentMessagesToTranscriptEvents,
  projectSessionHistory,
  stringifyContent,
  stringifyToolResult,
  type LegacyAgentMessage,
} from "./session/transcript_projection.js";
import { RelayClient } from "./transport/relay_client.js";
import { PlainPeerChannel } from "./transport/peer_channel.js";
import { OwnerMultiplexer } from "./extension/owner_multiplexer.js";
import type { OwnerMultiplexerTestHarness } from "./extension/testing.js";
import { createCommandSurface } from "./extension/command_surface.js";
import { registerRemotePiCommands, type RemotePiCommandSpec } from "./extension/command_surface/commands.js";
import { LocalMeshCommands } from "./extension/command_surface/local_mesh_commands.js";
import { DaemonCommands } from "./extension/command_surface/daemon_commands.js";
import { CronCommands } from "./extension/command_surface/cron_commands.js";
import { PairingCommands } from "./extension/command_surface/pairing_commands.js";
import { PairingCoordinator } from "./extension/command_surface/pairing_coordinator.js";
import { RelayCommands } from "./extension/command_surface/relay_commands.js";
import { ServiceCommands } from "./extension/command_surface/service_commands.js";
import { restartSupervisor } from "./extension/command_surface/supervisor_restart.js";
import { probeListPeers } from "./extension/probe_list_peers.js";
export { probeListPeers } from "./extension/probe_list_peers.js";
export { restartSupervisorCommand as _restartSupervisorCommand } from "./extension/command_surface/supervisor_restart.js";
export type { RestartStep } from "./extension/command_surface/supervisor_restart.js";
import { createRemotePiExtensionRuntime } from "./extension/composition_root.js";
import { createLegacyIndexPorts, type LegacyIndexDeps } from "./extension/legacy_ports.js";
import type { CommandSurfacePort } from "./extension/ports.js";
import { SdkSessionProjection } from "./session/sdk_session_projection.js";
import { roomIdFor } from "./rooms.js";
import { registerAgentTools } from "./session/tools.js";
import { formatPeerInventory } from "./session/peer_inventory.js";
import { MeshNode } from "./session/mesh_node.js";
import { reachabilityBackoffMs } from "./reachability/reachability_contract.js";
import { RemoteSessionIssuer } from "./session/remote_session.js";
import { validateClientSession } from "./session/session_gate.js";
import {
  initialTurnSnapshot,
  projectTurn,
  reduceTurn,
  type TurnEvent,
  type TurnProjection,
  type TurnSnapshot,
} from "./session/turn_state.js";
import {
  handleSessionCompact,
  handleSessionNew,
  handleModelSet,
  handleThinkingSet,
  handleListModels,
  type ActionCtx,
} from "./actions/handlers.js";
import { ensureModelRegistry } from "./actions/registry.js";
import {
  ensureGlobalDirs,
  LOCAL_SESSION_NAME,
  sessionAuditPath,
  sessionSockPath,
  skillsDir,
} from "./session/global_config.js";
import { EXIT_DAEMON_FRESH_SESSION } from "./daemon/rpc_child.js";
import {
  defaultAgentName,
  effectiveAutoStartRelay,
  loadLocalConfig,
  localConfigExists,
  saveLocalConfig,
} from "./session/local_config.js";
import { updateFooter, type FooterState } from "./ui/footer.js";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, copyFileSync, existsSync, unlinkSync, readFileSync, writeFileSync, realpathSync } from "node:fs";
import { createInterface } from "node:readline";
import { spawnSync } from "node:child_process";
import { hostname, tmpdir } from "node:os";
import {
  kDefaultRelayUrl,
  resolveRelayUrl,
  saveConfig,
  isValidRelayUrl,
  isWebSocketScheme,
  toWebSocketUrl,
} from "./config.js";

// ── State machine ─────────────────────────────────────────────────────────────
//
// Pre-2026-05-23: `idle` → `started` → `paired` (one owner at a time, gate-kept
// by `_appPeerId`/`_peerChannel` singletons). The transition to `paired` was
// what unblocked the app from sending application messages.
//
// Now: `idle` → `started`. The `paired` state is a derived metric
// (`OwnerMultiplexer.activeCount() > 0`) — N owners can be connected at once,
// each with its own `PlainPeerChannel` owned by the multiplexer. Plan/24 W2D
// ("multi-channel broadcast"): pairing a second device no longer disconnects
// the first, and every connected owner receives the same agent stream in parallel.

export type RemoteState = "idle" | "started";

let _state: RemoteState = "idle";
let _relay: RelayClient | null = null;

/** Relay connectivity as seen by an RPC client (Cockpit). Derived from
 *  `_state` + `_relay`: "disconnected" = relay off (idle); "connected" = live
 *  WS; "reconnecting" = was on, WS dropped, retrying. Surfaced via the
 *  `remote-pi:relay-state` custom message (see `_emitRelayState`). */
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";

/** Last `RelayConnectivity` emitted, for change-dedup. Starts "disconnected"
 *  (the process boots with the relay down). */
let _lastRelayStatus: RelayConnectivity | null = null;

/** Sentinel prefix for a transparent control message an RPC client sends on the
 *  `prompt` channel (stdin). The `input` hook intercepts it, runs the action,
 *  and swallows it (`action:"handled"`) so it never becomes an LLM turn or a
 *  transcript entry. Starts with NUL so it can't collide with real user input
 *  and doesn't begin with "/" (which would route to the command parser). */
export const CTRL_PREFIX = "\x00remote-pi-ctrl:";
let _relayUrl: string | null = null;  // URL used by current _relay connection
let _myRoomId: string | null = null;   // this Pi's room id (derived from cwd)

const _owners = new OwnerMultiplexer({
  createChannel: (input) => new PlainPeerChannel(
    input.relay,
    input.peerId,
    input.roomId ?? _myRoomId ?? undefined,
    input.onMessage,
    () => input.onDisconnect(input.peerId),
  ),
  refreshFooter: () => _refreshFooter(),
  listPeers: () => listPeers(),
  findKnownPeer: async (peerId) => {
    const peers = await listPeers();
    return peers.find((p) => p.remote_epk === peerId) ?? null;
  },
  consumePairToken: (token) => qrSession.consumeToken(token),
  addPeer: (record) => addPeer(record),
  onPeerPersisted: () => { void _owners.refreshPairingsCache(); },
  currentPairingSession: () => {
    const cwd = _currentCwd();
    const sessionName = _displayName(cwd);
    return {
      sessionName,
      sessionStartedAt: _sessionStartedAt ?? Date.now(),
      sessionId: _currentRemoteSessionId(_lastEventCtx ?? _lastCtx),
      roomId: _myRoomId ?? roomIdFor(cwd, sessionName),
      harness: _HARNESS,
      hostname: _HOSTNAME,
    };
  },
  makeUnknownPeerError: () => _withCurrentSession({
    type: "error",
    code: "unknown_peer",
    message: "Peer not paired — re-scan QR",
  }),
  onOwnerAttached: ({ peerId, peerName, activeCount }) => {
    _applyTurnAndPublish({ type: "peer_attached", target: { kind: "owner", id: peerId } });
    _notify(
      `[remote-pi] Owner attached: peer=${peerId.slice(0, 8)}, name=${peerName} ` +
      `(${activeCount} active)`,
      "info",
    );
  },
  onOwnerPaired: ({ peerId, peerName, pairedAt }) => {
    _sendPiMessage({
      customType: "remote-pi:paired",
      content: `Paired with ${peerName}`,
      details: { name: peerName, peerId, pairedAt },
      display: false,
    }, undefined, "paired");
  },
});

const ownerHarness: OwnerMultiplexerTestHarness = {
  activeOwnerCount: () => _owners.activeCount(),
  hasOwner: (peerId) => _owners.has(peerId),
  disconnectOwner: (peerId) => _disconnectOwnerForRuntime(peerId),
  fallbackRoute: (message, ctx) => {
    const fallback = _owners.entries().at(-1)?.channel;
    if (!fallback) return;
    _routeClientMessageFrom(fallback as PlainPeerChannel, message, ctx);
  },
};

const _pairingCoordinator = new PairingCoordinator({
  getState: () => _state,
  setState: (state) => { _state = state; },
  relay: () => _relay,
  setRelay: (relay) => { _relay = relay; },
  relayUrl: () => _relayUrl,
  setRelayUrl: (url) => { _relayUrl = url; },
  roomId: () => _myRoomId,
  setRoomId: (roomId) => { _myRoomId = roomId; },
  roomMeta: () => _myRoomMeta,
  setRoomMeta: (meta) => { _myRoomMeta = meta as typeof _myRoomMeta; },
  sessionStartedAt: () => _sessionStartedAt,
  setSessionStartedAt: (ts) => { _sessionStartedAt = ts; },
  currentModel: () => _currentModel,
  setCurrentModel: (model) => { _currentModel = model; },
  currentThinking: () => _currentThinking,
  setCurrentThinking: (thinking) => { _currentThinking = thinking; },
  currentThinkingLevel: () => _pi?.getThinkingLevel() as ThinkingLevel | undefined,
  displayName: (cwd) => _displayName(cwd),
  currentRemoteSessionId: (ctx) => _currentRemoteSessionId(ctx),
  withCurrentSession: (msg) => _withCurrentSession(msg),
  currentPairingSession: () => _currentPairingSessionSnapshot(),
  isDisposed: () => _disposed,
  turnWorking: () => _turnProjection().working,
  owners: _owners,
  ownerHas: (peerId) => _owners.has(peerId),
  ownerActiveCount: () => _owners.activeCount(),
  refreshPairingsCache: () => { void _owners.refreshPairingsCache(); },
  onOwnerAttached: ({ peerId, peerName, activeCount }) => {
    _applyTurnAndPublish({ type: "peer_attached", target: { kind: "owner", id: peerId } });
    _notify(
      `[remote-pi] Owner attached: peer=${peerId.slice(0, 8)}, name=${peerName} ` +
      `(${activeCount} active)`,
      "info",
    );
  },
  onOwnerPaired: ({ peerId, peerName, pairedAt }) => {
    _sendPiMessage({
      customType: "remote-pi:paired",
      content: `Paired with ${peerName}`,
      details: { name: peerName, peerId, pairedAt },
      display: false,
    }, undefined, "paired");
  },
  onPeerDisconnect: (peerId) => _onPeerDisconnect(peerId),
  handleClientMessage: (sender, message) => _routeClientMessageFrom(sender as PlainPeerChannel, message, _lastEventCtx ?? _lastCtx ?? _noopCtx),
  joinLocalMesh: async (ctx) => { if (!_meshNode) await _cmdJoin(ctx); },
  refreshFooter: (ctx) => _refreshFooter(ctx),
  notify: (message, type, ctx) => _notify(message, type, ctx),
  sendPiMessage: (message, options, label) => _sendPiMessage(message, options, label),
  onRelayClose: () => _onRelayClose(),
  attachBridgeIfReady: () => _attachBridgeIfReady(),
  emitRelayState: (force) => _emitRelayState(force),
  setSiblings: (siblings) => { _meshNode?.setSiblings(siblings); },
});
const _pairingCommands = new PairingCommands(_pairingCoordinator);
const _relayCommands = new RelayCommands(_pairingCoordinator);
const _daemonCommands = new DaemonCommands();
const _cronCommands = new CronCommands();
const _serviceCommands = new ServiceCommands();
// Plan/28 Wave D.1: `thinking` published alongside `model` so the app's
// Quick Actions sheet hydrates the thinking segmented control on first
// open instead of starting null. The SDK fires `thinking_level_select`
// on every change (initial load + user toggle), mirrored to room_meta
// the same way model is — apps subscribe to one channel for both.
let _myRoomMeta: { name: string; cwd: string; session_id?: string; model?: string; thinking?: ThinkingLevel; working?: boolean } | null = null;
let _currentModel: string | undefined = undefined;  // last-known model name
let _currentThinking: ThinkingLevel | undefined = undefined;  // last-known thinking level

// ── Agent-network session (plano 19) ──────────────────────────────────────────
// MeshNode owns both the local UDS mesh (SessionPeer) and the optional
// cross-PC relay bridge (BrokerRemote + PiForwardClient). The bridge is
// attached via `_meshNode.attachBridge()` once the relay WS is up and this
// Pi is the leader; MeshNode re-attaches it across UDS failovers.
let _meshNode: MeshNode | null = null;
// Set true by the `session_shutdown` handler. The daemon auto-init defers the
// connect (`setTimeout(_cmdRoot, 0)`) and connecting is async, so a shutdown can
// land WHILE this instance's `_cmdRoot` is still mid-connect (`_meshNode` not
// assigned yet) — the handler would then find nothing to close, and the connect
// would finish afterwards as an unreachable ghost. `_cmdRoot`/`_cmdJoin` check
// this flag after each await and abort (closing any peer that already connected)
// so a torn-down instance never lingers on the broker. Per-module (jiti
// re-evaluates the module on every session replacement), so the replacement
// instance starts fresh with `_disposed = false`.
let _disposed = false;

/** Re-queries the broker for the authoritative peer list. The broker's map is
 *  the source of truth — incremental +1/-1 counters drift after failover, lost
 *  `peer_left` broadcasts (e.g., leader leaves), or any dropped event. Called
 *  on every `peer_joined`/`peer_left` and once on join. Fire-and-forget. */
function _refreshSessionPeerCount(
  peer: MeshNode,
  ctx?: Pick<ExtensionContext, "ui"> | null,
): void {
  void peer.request("broker", { type: "list_peers" }, 2000)
    .then((reply) => {
      const peers = (reply.body as { peers?: string[] } | null)?.peers;
      if (Array.isArray(peers)) {
        _owners.setSessionPeerCount(peers.length);
        _refreshFooter(ctx);
      }
    })
    .catch(() => { /* older broker without list_peers — keep prior count */ });
}

/** Friendly model name for room_meta (plano 18). undefined when SDK has none yet. */
function _currentModelName(): string | undefined {
  return _currentModel;
}

/**
 * Cache the active model name and fan it out to subscribed apps via a
 * `room_meta_update`. The relay push is a no-op when the room isn't up yet —
 * the next `room_meta` hello carries the cached value instead. Shared by the
 * `model_select` event and the connect/turn-start seeding, so a daemon that
 * just runs its DEFAULT model still reports it: `model_select` only fires on an
 * explicit set/cycle (never on settings load), so default-model daemons would
 * otherwise never surface their model.
 */
function _setCurrentModel(name: string): void {
  _currentModel = name;
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, model: name };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { model: name } });
  }
}

/**
 * Plan/32: publish the `working` flag as room_meta (raw, no debounce — the
 * app debounces). Same shape as model/thinking updates. Used by turn_start/end
 * AND by the compaction handlers: `compact()` doesn't run a turn (it
 * disconnects the agent + aborts, emitting compaction_start, NOT turn_start),
 * so room_meta.working must be bracketed manually around compaction.
 */
function _publishWorking(working: boolean): void {
  _publishRoomMetaPatch({ working });
}

function _publishRoomMetaPatch(
  patch: { session_id?: string; model?: string; thinking?: ThinkingLevel; working?: boolean },
): void {
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, ...patch };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: patch });
  }
}

// ── Cross-PC mesh wiring (plan/25 Wave B/C) ───────────────────────────────────

/**
 * Hand the live relay to MeshNode so it can bring up the cross-PC bridge
 * (BrokerRemote + sibling discovery) — but only when this Pi is the leader
 * (broker host). MeshNode is idempotent + re-attaches across UDS failovers,
 * so this is safe to call from `_cmdStart`, relay reconnect, or SelfRevoke.
 * No-op until the relay WS + cached identity are both present.
 */
function _attachBridgeIfReady(): void {
  const keypair = _pairingCoordinator.currentKeypair();
  if (!_meshNode || !_relay || !_relayUrl || !keypair) return;
  void _meshNode
    .attachBridge({ relay: _relay, relayUrl: _relayUrl, keypair })
    .catch(() => { /* best-effort — UDS mesh works regardless */ });
}

type RemotePiUi = {
  setStatus?: (k: string, v: string | undefined) => void;
  setTitle?: (t: string) => void;
  notify?: (msg: string, type?: "info" | "warning" | "error") => void;
};

type RemotePiUiContext = { ui?: RemotePiUi } | null | undefined;

/**
 * Safely resolve a ctx.ui reference. Pi intentionally throws when an extension
 * touches a context captured before session replacement/reload; relay callbacks
 * can outlive that context (idle app resumes, known-peer reconnect, late
 * notifications). Treat stale ctxs as absent and clear our captured slots so
 * later callbacks fall through to the freshest session_start ctx or no-op.
 */
function _isStaleContextError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return message.includes("stale after session replacement or reload");
}

function _safeUi(ctx?: RemotePiUiContext): RemotePiUi | undefined {
  if (!ctx) return undefined;
  try {
    return ctx.ui;
  } catch (err) {
    if (_isStaleContextError(err)) {
      if (ctx === _lastCtx) _lastCtx = null;
      if (ctx === _lastEventCtx) _lastEventCtx = null;
    }
    return undefined;
  }
}

function _currentUi(preferred?: RemotePiUiContext): RemotePiUi | undefined {
  return _safeUi(preferred) ?? _safeUi(_lastEventCtx) ?? _safeUi(_lastCtx);
}

function _currentCwd(): string {
  if (!_lastCtx) return process.cwd();
  try {
    return "cwd" in _lastCtx ? _lastCtx.cwd : process.cwd();
  } catch {
    _lastCtx = null;
    return process.cwd();
  }
}

function _notify(msg: string, type: "info" | "warning" | "error" = "info", ctx?: RemotePiUiContext): void {
  const ui = _currentUi(ctx);
  if (typeof ui?.notify !== "function") return;
  try {
    ui.notify(msg, type);
  } catch {
    // Best-effort notification path: stale UI must never crash relay callbacks.
  }
}

function _forgetStaleMessageApi(api: AgentMessageApi): void {
  if (api === _messageApi) _messageApi = null;
  if (api === _pi) _pi = null;
}

function _sessionUnavailable(sender: PlainPeerChannel, inReplyTo: string, detail = "Pi session is replacing or not bound yet"): void {
  sender.send(_withCurrentSession({
    type: "error",
    code: "internal_error",
    in_reply_to: inReplyTo,
    message: detail,
  }));
}

function _sendPiMessage(
  message: Parameters<ExtensionAPI["sendMessage"]>[0],
  options?: Parameters<ExtensionAPI["sendMessage"]>[1],
  label = "sendMessage",
): boolean {
  const candidates = Array.from(new Set<AgentMessageApi | null>([_messageApi, _pi]));
  let lastDetail = "agent session not bound yet";
  for (const api of candidates) {
    if (!api || typeof api.sendMessage !== "function") continue;
    try {
      const delivered = api.sendMessage(message, options);
      if (_isPromiseLike(delivered)) {
        delivered.catch((err: unknown) => {
          const detail = err instanceof Error ? err.message : String(err);
          if (_isStaleContextError(err)) _forgetStaleMessageApi(api);
          console.error(`[remote-pi] ${label}: Pi rejected message: ${detail}`);
        });
      }
      return true;
    } catch (err) {
      const detail = err instanceof Error ? err.message : String(err);
      lastDetail = detail;
      if (_isStaleContextError(err)) {
        _forgetStaleMessageApi(api);
        continue;
      }
      console.error(`[remote-pi] ${label}: Pi rejected message: ${detail}`);
      return false;
    }
  }
  console.error(`[remote-pi] ${label}: Pi rejected message: ${lastDetail}`);
  return false;
}

/** Refreshes the Pi TUI footer slots from current module state. Safe no-op when ctx lacks ui or is stale. */
function _refreshFooter(ctx?: RemotePiUiContext): void {
  const ui = _currentUi(ctx);
  if (!ui || typeof ui.setStatus !== "function" || typeof ui.setTitle !== "function") return;
  const ownerSnapshot = _owners.snapshot();
  const state: FooterState = {
    session: ownerSnapshot.sessionName ?? undefined,
    peerCount: ownerSnapshot.sessionPeerCount,
    relayOn: _state !== "idle",
    // `devicePaired` now reflects "any owner currently attached" — picks one
    // shortid representatively (multi-owner UX detail surfaces in the
    // `/remote-pi status` line, not the footer slot).
    devicePaired: ownerSnapshot.activeOwnerCount > 0 ? ownerSnapshot.lastOwnerShortId : undefined,
    hasPairings: ownerSnapshot.hasGlobalPairings,
    agentName: _meshNode?.name(),
  };
  updateFooter(
    { ui: { setStatus: ui.setStatus.bind(ui), setTitle: ui.setTitle.bind(ui) } },
    state,
  );
}

// Epoch ms when the state machine entered 'started' (last /remote-pi start).
// Used by session_sync to let the app detect Pi restarts (and force a full
// replay). Cleared on _goIdle.
let _sessionStartedAt: number | null = null;
const _remoteSessionIssuer = new RemoteSessionIssuer();

// Append-only transcript event log for session_sync history projection.
// Preserved across relay stop/reconnect because the Pi agent session outlives
// the relay connection. Cleared only when a new Pi session is created.
let _transcriptEvents: TranscriptEvent[] = [];

// App-origin user messages are echoed immediately after SDK acceptance, before
// the SDK's later message_end persistence callback. Keep a small deterministic
// signature map so that callback appends the same event id and the event log
// deduper treats it as replay rather than a duplicate user bubble.
const _deliveredUserEventIds = new Map<string, { clientMessageId: string; eventId: string }[]>();

/**
 * Test-only: emulate what `/remote-pi` does on the returning-user path
 * (join the local mesh, then start the relay) without touching the FS for
 * a `localConfigExists()` lookup. Lets tests bring the relay up without
 * mocking the wizard or the local config storage.
 *
 * Typed loosely to accept any ctx shape with `ui.notify` + `cwd` — the
 * unit tests use minimal mocks that don't satisfy the full
 * `ExtensionContext` interface.
 */
export async function _connectForTest(ctx: unknown): Promise<void> {
  const real = ctx as Parameters<typeof _cmdJoin>[0];
  await _cmdJoin(real);
  await _cmdStart(real);
}

/** Test-only: tear everything down (mirrors `/remote-pi stop`). */
export async function _stopForTest(ctx: unknown): Promise<void> {
  await _cmdStop(ctx as Parameters<typeof _cmdStop>[0]);
}

/** Test-only: read/reset the `_disposed` flag. In production it's per-module
 *  and never reset (a disposed instance is discarded), but tests share one
 *  module across cases, so they reset it to avoid cross-test pollution. */
export function _getDisposedForTest(): boolean { return _disposed; }
export function _setDisposedForTest(v: boolean): void { _disposed = v; }

/** Test-only: true when this instance holds a live local-mesh node. */
export function _hasMeshNodeForTest(): boolean { return _meshNode !== null; }

/** Test-only: the effective (possibly `#N`-suffixed) name the cwd-lock reserved. */
export function _getLockedNameForTest(): string | null { return _localMeshCommands.getLockedNameForTest(); }

/** Test-only: release + clear the cwd lock (the lock normally survives stop). */
export function _resetCwdLockForTest(): void {
  _localMeshCommands.resetCwdLockForTest();
}

/**
 * Test-only: relay-only startup, no UDS mesh join. Replaces the old
 * `remote-pi relay start` handler that some tests captured to bring up
 * the relay in isolation (e.g. ping/pong tests that don't care about the
 * agent-network broker).
 */
export async function _startRelayForTest(ctx: unknown): Promise<void> {
  await _cmdStart(ctx as Parameters<typeof _cmdStart>[0]);
}

// Legacy test adapter: accepts old SDK-message fixtures but stores transcript events.
export function _setMessageBufferForTest(msgs: unknown[]): void {
  _deliveredUserEventIds.clear();
  _lastTranscriptUserId = null;
  _transcriptEvents = mapLegacyAgentMessagesToTranscriptEvents({
    sessionId: _currentRemoteSessionId(),
    messages: msgs as LegacyAgentMessage[],
  });
  const lastUser = [..._transcriptEvents].reverse().find((event) =>
    event.kind === "user_confirmed" || event.kind === "user_submitted"
  );
  _lastTranscriptUserId = lastUser?.clientMessageId ?? null;
}

export function _setTranscriptEventsForTest(events: TranscriptEvent[]): void {
  _deliveredUserEventIds.clear();
  _transcriptEvents = [...events];
  const lastUser = [..._transcriptEvents].reverse().find((event) =>
    event.kind === "user_confirmed" || event.kind === "user_submitted"
  );
  _lastTranscriptUserId = lastUser?.clientMessageId ?? null;
}

/** Test-only accessor: returns a defensive copy of the transcript event log. */
export function _getTranscriptEventsForTest(): TranscriptEvent[] {
  return [..._transcriptEvents];
}

/** Test-only override of session started timestamp. */
export function _setSessionStartedAtForTest(ts: number | null): void {
  _sessionStartedAt = ts;
}

export function _getRemoteSessionIdForTest(): string | null {
  return _remoteSessionIssuer.current();
}

export function _setRemoteSessionIdForTest(id: string | null): void {
  if (id === null) _remoteSessionIssuer.clear();
  else _remoteSessionIssuer.capture({ sessionManager: { getSessionId: () => id } });
}

function _currentRemoteSessionId(ctx?: unknown): string {
  return _remoteSessionIssuer.currentOrCapture(ctx ?? _lastEventCtx ?? _lastCtx ?? undefined);
}

function _withCurrentSession<T extends object>(msg: T): T & { session_id: string } {
  return { ...msg, session_id: _currentRemoteSessionId() };
}

let _lastTranscriptUserId: string | null = null;

function _appendTranscriptEvent(event: TranscriptEvent): void {
  _transcriptEvents = appendTranscriptEvent(_transcriptEvents, event);
}

function _rememberDeliveredUserEvent(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
  clientMessageId: string,
  eventId: string,
): void {
  const key = _userContentSignature(text, images);
  const existing = _deliveredUserEventIds.get(key) ?? [];
  existing.push({ clientMessageId, eventId });
  _deliveredUserEventIds.set(key, existing);
}

function _consumeDeliveredUserEvent(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
): { clientMessageId: string; eventId: string } | undefined {
  const key = _userContentSignature(text, images);
  const existing = _deliveredUserEventIds.get(key);
  if (!existing || existing.length === 0) return undefined;
  const match = existing.shift();
  if (existing.length === 0) _deliveredUserEventIds.delete(key);
  return match;
}

function _userContentSignature(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
): string {
  return JSON.stringify({ text, images: images ?? [] });
}

function _appendUserConfirmedTranscriptEvent(input: {
  sessionId: string;
  ts: number;
  clientMessageId: string;
  text: string;
  images?: Extract<TranscriptEvent, { kind: "user_confirmed" }>["images"];
  streamingBehavior?: Extract<TranscriptEvent, { kind: "user_confirmed" }>["streamingBehavior"];
  eventId?: string;
}): void {
  const eventId = input.eventId
    ?? deterministicTranscriptEventId(input.sessionId, "user_confirmed", input.clientMessageId);
  _appendTranscriptEvent({
    kind: "user_confirmed",
    eventId,
    sessionId: input.sessionId,
    ts: input.ts,
    clientMessageId: input.clientMessageId,
    text: input.text,
    ...(input.images && input.images.length > 0 ? { images: [...input.images] } : {}),
    ...(input.streamingBehavior ? { streamingBehavior: input.streamingBehavior } : {}),
  });
  _lastTranscriptUserId = input.clientMessageId;
}

function _appendLegacySdkMessageToTranscript(message: LegacyAgentMessage): void {
  const sessionId = _currentRemoteSessionId();
  const ts = typeof message.timestamp === "number" ? message.timestamp : Date.now();
  if (message.role === "user") {
    const text = stringifyContent(message.content);
    const images = imagesFromContent(message.content);
    const matched = _consumeDeliveredUserEvent(text, images);
    const clientMessageId = matched?.clientMessageId ?? `sync_${ts}`;
    _appendUserConfirmedTranscriptEvent({
      sessionId,
      ts,
      clientMessageId,
      text,
      ...(images.length > 0 ? { images } : {}),
      ...(matched ? { eventId: matched.eventId } : {}),
    });
    return;
  }

  if (message.role === "assistant") {
    const content = Array.isArray(message.content) ? message.content : [];
    const usage = message.usage
      ? { input_tokens: message.usage.input ?? 0, output_tokens: message.usage.output ?? 0 }
      : undefined;
    for (const [blockIndex, raw] of content.entries()) {
      if (!raw || typeof raw !== "object") continue;
      const block = raw as { type?: string; text?: unknown; id?: unknown; name?: unknown; arguments?: unknown };
      if (block.type === "text") {
        const text = String(block.text ?? "");
        if (!text) continue;
        const messageId = `sync_${ts}:assistant:${blockIndex}`;
        _appendTranscriptEvent({
          kind: "assistant_committed",
          eventId: deterministicTranscriptEventId(sessionId, "assistant_committed", messageId),
          sessionId,
          ts,
          messageId,
          replyTo: _lastTranscriptUserId ?? `sync_${ts}`,
          text,
          ...(usage ? { usage } : {}),
        });
      } else if (block.type === "toolCall") {
        const toolCallId = String(block.id ?? `sync_${ts}:tool:${blockIndex}`);
        _appendTranscriptEvent({
          kind: "tool_requested",
          eventId: deterministicTranscriptEventId(sessionId, "tool_requested", toolCallId),
          sessionId,
          ts,
          toolCallId,
          tool: String(block.name ?? ""),
          args: _recordArgs(block.arguments),
        });
      }
    }
    return;
  }

  if (message.role === "toolResult") {
    const toolCallId = String(message.toolCallId ?? `sync_${ts}:tool-result`);
    const text = stringifyToolResult(message.content);
    _appendTranscriptEvent(message.isError
      ? {
          kind: "tool_finished",
          eventId: deterministicTranscriptEventId(sessionId, "tool_finished", toolCallId),
          sessionId,
          ts,
          toolCallId,
          error: text,
        }
      : {
          kind: "tool_finished",
          eventId: deterministicTranscriptEventId(sessionId, "tool_finished", toolCallId),
          sessionId,
          ts,
          toolCallId,
          result: text,
        });
  }
}

function _recordArgs(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function _captureRemoteSession(ctx: unknown): string {
  const sessionId = _remoteSessionIssuer.capture(ctx);
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, session_id: sessionId };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { session_id: sessionId } });
  }
  return sessionId;
}

/** Test-only: reset the cached model name (between tests). */
export function _setCurrentModelForTest(name: string | undefined): void {
  _currentModel = name;
}

/** Test-only: read the active turn id used for plain `cancel` routing. */
export function _getCurrentTurnIdForTest(): string | null {
  return _turnProjection().activeTurnId;
}

/** Test-only: inspect the reducer-owned turn projection without exposing internals. */
export function _getTurnProjectionForTest(): TurnProjection {
  return _turnProjection();
}

/** Test-only: override the bound AgentSession so a spy can capture the
 *  content handed to `sendUserMessage` (plan/30 multimodal ingest). */
export function _setPiForTest(pi: unknown): void {
  _pi = pi as typeof _pi;
  _messageApi = _isAgentMessageApi(pi) ? pi : null;
  if (_pi) _sdkSessionProjection.bindApi(_pi);
}

/**
 * Persist a model change to the PROJECT settings (`<cwd>/.pi/settings.json`) so
 * a model picked from the app survives a Pi/daemon restart. `pi.setModel` only
 * sets the LIVE model — on the next restart a fresh session reads the saved
 * default and reverts (the reported bug). We write the PROJECT scope, NOT
 * global, deliberately: the SDK merges global←project with PROJECT winning
 * (`SettingsManager`), so a folder that already has a project default (every
 * created daemon does) would shadow a global write like the TUI's. Project
 * scope is also correct for a fleet — each daemon keeps its own model rather
 * than leaking one default globally.
 *
 * Read-merge-write + best-effort: preserves other keys and never throws (a
 * settings write must not fail the live model change, which already applied).
 */
function _persistModelDefault(provider: string, modelId: string): void {
  try {
    const path = join(process.cwd(), ".pi", "settings.json");
    let obj: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
      if (parsed && typeof parsed === "object") obj = parsed as Record<string, unknown>;
    } catch { /* no existing/parseable file → start fresh */ }
    obj["defaultProvider"] = provider;
    obj["defaultModel"] = modelId;
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(obj, null, 2));
  } catch { /* best-effort — model change already applied live */ }
}

// Per-turn messaging state
let _turn: TurnSnapshot = initialTurnSnapshot();

function _turnProjection(): TurnProjection {
  return projectTurn(_turn);
}

function _publishTurnProjection(before: TurnProjection, after: TurnProjection): void {
  if (before.working === after.working) return;
  _publishWorking(after.working);
}

function _applyTurnAndPublish(event: TurnEvent): TurnProjection {
  const before = _turnProjection();
  _turn = reduceTurn(_turn, event);
  const after = _turnProjection();
  _publishTurnProjection(before, after);
  return after;
}

function _resetTurnSnapshot(): void {
  _turn = initialTurnSnapshot();
}

function _activeReplyTarget(): string | null {
  const projection = _turnProjection();
  return projection.replyTo ?? projection.activeTurnId;
}

// Module-level pi reference
let _pi: ExtensionAPI | null = null;

// ── Session sync limit (mirror cache cap) ─────────────────────────────────────
//
// Configurable via REMOTE_PI_SYNC_LIMIT env var (positive int, default 30).
// Read on every session_sync so QA can `export REMOTE_PI_SYNC_LIMIT=N` between
// runs without restarting the extension. The value is also clamped against
// the client-provided `limit` (server is authoritative).
const SYNC_LIMIT_DEFAULT = 30;
function _getSyncLimit(): number {
  const raw = process.env["REMOTE_PI_SYNC_LIMIT"];
  const parsed = raw ? parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : SYNC_LIMIT_DEFAULT;
}

// ── Relay reconnect state ─────────────────────────────────────────────────────
// Backoffs in ms: 1s, 2s, 5s, 10s, 30s, then stays at 30s.
let _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let _reconnectAttempt = 0;

/** Test-only: exposes pending reconnect timer state. */
export function _hasPendingReconnect(): boolean {
  return _reconnectTimer !== null;
}

/**
 * Public state-snapshot helper. Returns the derived UX state, not the raw
 * `_state` enum: the W2D refactor collapsed the internal machine to
 * `idle | started` and made `paired` a derived metric
 * (`ownerMultiplexer.activeCount() > 0`). Tests and the footer keep the
 * three-state mental model via this getter.
 */
export function _getState(): "idle" | "started" | "paired" {
  if (_state === "idle") return "idle";
  return _owners.activeCount() > 0 ? "paired" : "started";
}

/** Test-only: number of owners currently attached via PlainPeerChannel. */
export const _getActivePeerCountForTest = (): number => ownerHarness.activeOwnerCount();

/** Test-only: true if a specific peer (base64 std) has an attached channel. */
export const _hasActivePeerForTest = (appPeerIdStd: string): boolean => ownerHarness.hasOwner(appPeerIdStd);


// ── Multi-channel helpers ─────────────────────────────────────────────────────

function _queuedMessageState(): Extract<ServerMessage, { type: "queued_message_state" }> {
  const queued = _turnProjection().queuedMessage;
  return queued
    ? _withCurrentSession({ type: "queued_message_state", id: queued.id, text: queued.text })
    : _withCurrentSession({ type: "queued_message_state" });
}

function _broadcastQueuedMessageState(): void {
  _owners.broadcast(_queuedMessageState());
}

// ── Display-name helpers ──────────────────────────────────────────────────────

/**
 * Resolves the name this Pi shows to the mobile app and the relay's
 * `room_meta.name`. Single source of truth for "what does this Pi call
 * itself when talking to others".
 *
 * Resolution order:
 *   1. Broker-assigned name (when this Pi is on the local UDS mesh) — may
 *      carry a `#N` suffix from a name collision. Matches what other
 *      agents see, so the mobile UI shows the exact same string.
 *   2. `agent_name` from `<cwd>/.pi/remote-pi/config.json` — set by the
 *      wizard on first run; this is "the name the user configured".
 *   3. `defaultAgentName(cwd)` (parent/folder) — fallback when no config
 *      exists yet and the mesh hasn't been joined.
 *
 * Pre-2026-05-23 callers computed `cwd.split('/').slice(-2).join('/')`
 * inline at three different sites (pair_ok, room_meta, QR URI); this
 * helper consolidates them and lifts the user's configured name above
 * the raw cwd path.
 */
function _displayName(cwd: string): string {
  if (_meshNode) return _meshNode.name();
  const local = loadLocalConfig(cwd);
  return local.agent_name || defaultAgentName(cwd);
}

// ── Transition helpers ────────────────────────────────────────────────────────

/**
 * Full teardown: stop listener, detach channel, close relay → idle.
 *
 * `byeReason` (optional): when present and the channel is up, sends a
 * `{type:"bye", reason}` to the app before detaching so it sees offline
 * immediately instead of waiting ~50s for a ping miss. Fire-and-forget —
 * if the WS already failed (e.g., `relay.on("close")` callback) skip it
 * by omitting the reason; app falls back to ping miss naturally.
 */
function _goIdle(byeReason?: import("./protocol/types.js").ByeReason): void {
  // Broadcast bye to every still-attached owner so each app surfaces
  // "offline" immediately instead of waiting ~50s for a ping miss.
  if (byeReason && _state !== "idle" && _owners.activeCount() > 0) {
    _owners.broadcast({ type: "bye", reason: byeReason });
  }

  // Cancel any pending reconnect attempt. Critical: /remote-pi stop must
  // win the race against a scheduled reconnect.
  if (_reconnectTimer !== null) {
    clearTimeout(_reconnectTimer);
    _reconnectTimer = null;
  }
  _reconnectAttempt = 0;

  _pairingCoordinator.stopListener();

  // Tear down every per-owner channel and clear the multiplexer registry.
  _owners.detachAll();
  _applyTurnAndPublish({ type: "session_shutdown" });
  _resetTurnSnapshot();
  _publishWorking(false);

  _relay?.close();
  _relay = null;
  _relayUrl = null;

  // Stop the mesh poller — it's bound to the relay-up lifecycle so a new
  // relay start will spin up a fresh instance (with potentially a new relay
  // URL if the user changed it via /remote-pi relay url).
  _pairingCoordinator.stopSelfRevoke();

  // Cross-PC routing relies on _relay being up; tear it down here too.
  _meshNode?.detachBridge();

  // Preserve _sessionStartedAt + _transcriptEvents across stop/start cycles.
  // The Pi agent session outlives the relay connection — `message_end` keeps
  // firing for terminal turns even while idle, and the transcript event log
  // must survive so those turns appear in the next session_sync. Only a Pi
  // process restart resets these (init-time values).

  _state = "idle";
  _refreshFooter();
  _emitRelayState();  // → disconnected
}

/**
 * Called when the relay WS closes unexpectedly (network drop, relay restart,
 * etc.). Does a **partial** teardown — keeps `_sessionStartedAt`, `_transcriptEvents`,
 * `_relayUrl`, and the coordinator-owned identity so the session can resume on reconnect —
 * and schedules an `_attemptReconnect`.
 *
 * Peer (app) reconnect after a successful relay reconnect is handled by the
 * existing auto-listener via `peers.json` lookup, so we don't need to track
 * the prior peer here; we just go back to `started` and wait.
 */
function _onRelayClose(): void {
  if (_state === "idle") return;  // already torn down (e.g. /remote-pi stop)

  _pairingCoordinator.stopListener();

  // Detach every per-owner channel — relay is gone, none can route. The
  // auto-listener re-attaches owners after `_attemptReconnect` succeeds
  // (via the same known-peer + pair_request paths used on first connect).
  // Relay drop is not an explicit stop: do not send bye and do not clear
  // session history or reconnect-owned state.
  _owners.detachAllForRelayDrop();
  if (!_turnProjection().working) _resetTurnSnapshot();

  _relay = null;  // _relayUrl preserved for retry

  // Cross-PC routing relies on _relay; bring it down. Will be re-instated
  // by _attemptReconnect on success.
  _meshNode?.detachBridge();

  _state = "started";
  _refreshFooter();
  _emitRelayState();  // → reconnecting

  _scheduleReconnect();
}

function _scheduleReconnect(): void {
  if (_reconnectTimer !== null) return;  // already scheduled
  if (!_pairingCoordinator.currentKeypair() || !_relayUrl) return;  // can't reconnect without these
  if (_getState() === "idle") return;  // stopped while we were here

  const delay = reachabilityBackoffMs(_reconnectAttempt);
  _reconnectAttempt += 1;

  _reconnectTimer = setTimeout(() => {
    _reconnectTimer = null;
    void _attemptReconnect();
  }, delay);
}

async function _attemptReconnect(): Promise<void> {
  // `_state` may transition to "idle" between awaits via _goIdle; read via
  // _getState() to defeat TS narrowing on the module-level let.
  if (_getState() === "idle") return;
  if (!_pairingCoordinator.currentKeypair() || !_relayUrl) return;

  const edKp = _pairingCoordinator.currentKeypair()!;
  const url = _relayUrl;
  // _relayUrl is stored in canonical http(s):// form — convert at the
  // WS boundary, same as _cmdStart.
  const relay = new RelayClient(toWebSocketUrl(url), edKp);

  try {
    // Replay the same room identity from _cmdStart. Without this the relay
    // would log this WS as a default-room peer and the app would see a
    // phantom "legacy session" appear (regression of plano 17 + 18).
    await relay.connect({
      ...(_myRoomId ? { roomId: _myRoomId } : {}),
      ...(_myRoomMeta ? { roomMeta: _myRoomMeta } : {}),
    });
  } catch {
    if (_getState() === "idle") return;
    _scheduleReconnect();
    return;
  }

  if (_getState() === "idle") {
    // Stop fired while connect was succeeding — drop the new relay.
    relay.close();
    return;
  }

  _relay = relay;
  _reconnectAttempt = 0;

  relay.on("close", _onRelayClose);
  _pairingCoordinator.listenOn(relay);

  // Plan/25 Wave B/C: relay is back; bring cross-PC routing back online.
  _attachBridgeIfReady();

  // _state stays "started"; peer reconnect (if previously paired) flows
  // through PairingCoordinator.installAutoListener
  // automatically when the app sends any inner.
  _emitRelayState();
}

// ── Relay state event + transparent control channel (Cockpit toggle) ─────────

/** Current relay connectivity, derived from `_state` + `_relay`. */
function _relayStatus(): RelayConnectivity {
  if (_getState() === "idle") return "disconnected";
  return _relay ? "connected" : "reconnecting";
}

/**
 * Emit the `remote-pi:relay-state` custom message so an RPC client (Cockpit)
 * can render a relay on/off indicator. Pure data (`display:false`) — never
 * shown in the transcript. De-duped on the connectivity value; pass
 * `force=true` to answer an explicit `relay:status` query regardless.
 */
function _emitRelayState(force = false): void {
  const status = _relayStatus();
  if (!force && status === _lastRelayStatus) return;
  _lastRelayStatus = status;
  // During session_shutdown we intentionally clear the message API before
  // tearing down relay state. There is no live Pi session to notify, and the
  // replacement instance / withSession rearm will publish its own fresh state.
  if (!_messageApi && !_pi) return;
  _sendPiMessage({
    customType: "remote-pi:relay-state",
    content: `Relay ${status}`,
    details: {
      status,
      connected: status === "connected",
      ...(_relayUrl ? { relayUrl: _relayUrl } : {}),
      ...(_myRoomId ? { room: _myRoomId } : {}),
    },
    display: false,
  }, undefined, "relay-state");
}

/** Minimal ctx for relay start/stop driven by a control message (no command
 *  ctx is available in the `input` hook). cwd matches the daemon's launch dir,
 *  so the derived relay room is identical to the one `_cmdStart` first used. */
function _controlCtx(): Pick<ExtensionContext, "ui" | "cwd"> {
  return {
    ui: _headlessUi(),
    cwd: process.cwd(),
  } as unknown as Pick<ExtensionContext, "ui" | "cwd">;
}

/**
 * `ui.notify` for headless contexts (daemon auto-init + control channel). There
 * is no TUI, and the RPC client (Cockpit) already gets everything it needs via
 * structured events (`remote-pi:relay-state`, `remote-pi:name-assigned`,
 * room_meta) — so routine INFO chatter would just pollute the client's captured
 * stderr. We drop info and forward only warnings/errors (kept for the
 * supervisor's journal / genuine failures). The interactive Pi keeps its normal
 * footer/notify path — this only affects headless ctxs.
 */
function _headlessUi(): { notify: (msg: string, type?: "info" | "warning" | "error") => void } {
  return {
    notify: (msg: string, type?: "info" | "warning" | "error") => {
      if (type === "warning" || type === "error") process.stderr.write(`${msg}\n`);
    },
  };
}

/**
 * Handle a transparent control command from an RPC client (Cockpit), received
 * as a `CTRL_PREFIX`-tagged input the `input` hook swallowed. Toggles the relay
 * WITHOUT leaving the local mesh (relay-only: `_cmdStart` up / `_goIdle` down),
 * then emits the fresh state. `relay:status` just re-emits (no change) so the
 * client can sync its button after (re)attaching to the RPC stream.
 */
export async function _handleControl(cmd: string): Promise<void> {
  await _localMeshCommands.handleControl(cmd);
}

/**
 * Per-owner disconnect callback. Fires when one specific owner's channel
 * detaches (e.g. relay told us the peer is gone). Other owners' channels
 * keep running — relay stays "started".
 *
 * Exported so tests can trigger the disconnect path for a specific peer.
 *
 * Backward-compat: a no-arg call (legacy tests / pre-W2D callers) falls
 * back to detaching the most recently attached peer, mirroring the old
 * singleton semantics.
 */
function _disconnectOwnerForRuntime(appPeerId?: string): void {
  if (_state === "idle") return;
  const result = _owners.disconnectOwner(appPeerId);
  if (!result.disconnected) return;

  if (result.activeOwnerCount > 0) {
    // Other owners still attached — keep the turn projection so they continue
    // seeing the in-flight agent stream.
    _refreshFooter();
    return;
  }

  // No owner left. Keep the turn projection active so a later attach during the
  // same turn can still receive chunks/done; the reducer clears only on terminal events.
  if (!_turnProjection().working) _resetTurnSnapshot();
  _refreshFooter();
  _notify("[remote-pi] All app peers disconnected, listening for reconnect", "info");
  // Auto-listener stays up — same listener catches the reconnect on any peer.
}

export const _onPeerDisconnect = (appPeerId?: string): void => ownerHarness.disconnectOwner(appPeerId);

/**
 * Plan/27 Wave A: lazily resolve the pi-extension package version from
 * disk so the `pair_ok.harness.version` field reflects what's actually
 * shipped. The lookup is best-effort — a parse failure (or running this
 * file out-of-tree) falls back to "0.0.0" which is still semver-valid
 * and the app tolerates it. Cached at module load.
 */
function _readExtensionVersion(): string {
  try {
    const here = fileURLToPath(import.meta.url);
    // dist/index.js → ../package.json. src/index.ts under tsx → also one level up.
    const pkgPath = join(here, "..", "..", "package.json");
    const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as { version?: string };
    return typeof pkg.version === "string" ? pkg.version : "0.0.0";
  } catch {
    return "0.0.0";
  }
}
const _HARNESS = {
  name: "Pi coding agent",
  version: _readExtensionVersion(),
} as const;
const _HOSTNAME = hostname();

function _currentPairingSessionSnapshot() {
  const cwd = _currentCwd();
  const sessionName = _displayName(cwd);
  return {
    sessionName,
    sessionStartedAt: _sessionStartedAt ?? Date.now(),
    sessionId: _currentRemoteSessionId(_lastEventCtx ?? _lastCtx),
    roomId: _myRoomId ?? roomIdFor(cwd, sessionName),
    harness: _HARNESS,
    hostname: _HOSTNAME,
  };
}

// ── Extension factory (default export) ───────────────────────────────────────

// Stores most recent command context so the auto-listener can use ui.notify.
// NOTE: this is a CAPTURED command ctx — the SDK marks it stale after a
// session replacement (newSession/fork/switch/reload). We re-capture it via
// `withSession` when WE drive a newSession (see the session_new dispatch).
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
// Freshest base ExtensionContext, re-captured on EVERY `session_start`
// (startup/new/fork/reload/resume). The session_start ctx is always bound to
// the CURRENT session, so compact + cancel (base-ctx methods) routed through
// here never hit a stale ctx — regardless of who triggered the replacement
// (an app Quick Action OR a `/new` typed in the Pi TUI). It carries only
// base-ctx methods (no newSession — that's command-ctx only), so command ops
// keep using `_lastCtx`.
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort" | "ui"> | null = null;
const _noopCtx = { ui: { notify: () => undefined }, abort: () => undefined };

type AgentMessageApi = {
  sendMessage: (...args: Parameters<ExtensionAPI["sendMessage"]>) => void | Promise<void>;
  sendUserMessage: (...args: Parameters<ExtensionAPI["sendUserMessage"]>) => void | Promise<void>;
};
let _messageApi: AgentMessageApi | null = null;

function _isPromiseLike(value: unknown): value is PromiseLike<void> {
  return !!value && (typeof value === "object" || typeof value === "function") && typeof (value as { then?: unknown }).then === "function";
}

function _isAgentMessageApi(value: unknown): value is AgentMessageApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<AgentMessageApi>;
  return typeof candidate.sendMessage === "function" && typeof candidate.sendUserMessage === "function";
}

const _sdkSessionProjection = new SdkSessionProjection({
  outputs: {
    broadcast: (message) => _owners.broadcast(message),
    sendTo: (sender, message) => sender.send(message),
    publishRoomMeta: (patch) => _publishRoomMetaPatch(patch),
    activeOwnerIds: () => _owners.peerIds(),
    lateAttachTargets: () => _owners.entries(),
    handleClientMessage: (sender, message) => _routeClientMessageFrom(sender as PlainPeerChannel, message, _lastEventCtx ?? _lastCtx ?? _noopCtx),
    onStaleMessageApi: (api) => _forgetStaleMessageApi(api),
  },
});

const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  const legacyPorts = createLegacyIndexPorts(createIndexDeps());
  const legacyRuntime = createRemotePiExtensionRuntime(pi, legacyPorts);
  legacyRuntime.ports.session.bindApi(pi);

  // Plano 19: ensure ~/.pi/remote/{sessions,skills}/ exist. The command
  // surface deploys the agent-network skill when it registers.
  try {
    ensureGlobalDirs();
  } catch { /* best-effort init */ }

  pi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }));

  // Tool calls execute without prompting the remote user. The Pi SDK has no
  // native `requiresApproval` per tool, and a hardcoded gate (Bash/Edit/Write)
  // misfired on every custom tool from third-party packages. Approval will
  // come back when the Pi ecosystem ships a permissions convention. tool_result
  // is still forwarded so the app shows tool activity transparently.

  // Mirror input typed in the Pi terminal (or sent via RPC) to every
  // connected owner. 'extension' source is our own sendUserMessage call
  // from routeClientMessage, which already seeded the turn projection — skip to
  // avoid a double turnId.
  pi.on("input", (event) => {
    // Transparent control channel: a `CTRL_PREFIX`-tagged input from an RPC
    // client (Cockpit button) toggles the relay. Run it and SWALLOW the input
    // (`action:"handled"`) so it never reaches the LLM or the transcript.
    // Checked first, before the peer-broadcast path, and regardless of source.
    if (event.text.startsWith(CTRL_PREFIX)) {
      void _handleControl(event.text.slice(CTRL_PREFIX.length).trim());
      return { action: "handled" } as const;
    }
    if (event.source === "extension") return;
    const before = _turnProjection();
    const turnId = before.replyTo ?? before.activeTurnId ?? `local_${randomUUID()}`;
    _applyTurnAndPublish({ type: "local_input", turnId, replyTo: turnId, source: "local" });
    if (_owners.activeCount() === 0) return;
    _owners.broadcast(_withCurrentSession({ type: "user_input", id: turnId, text: event.text }));
    return undefined;
  });

  // Track active model so the app can show it in the SessionTile (plano 18).
  // SDK fires model_select on settings load + every user switch. We cache the
  // friendly name and broadcast a room_meta_update so the relay can fan it
  // out to subscribed apps without needing a new pair.
  pi.on("model_select", (event) => {
    const m = event?.model as { name?: string; id?: string } | undefined;
    const modelName = m?.name ?? m?.id;
    if (!modelName) return;
    // Cache + fan out. Keeps the cached room_meta fresh so a future reconnect
    // carries the current model in its hello, and pushes a room_meta_update to
    // apps already subscribed.
    _setCurrentModel(modelName);
  });

  // Plan/28 Wave D.1: mirror model's room_meta_update path for thinking
  // level so the app hydrates the segmented control on first open instead
  // of starting null. SDK fires `thinking_level_select` on settings load
  // AND on every user toggle (matching `model_select`'s behavior), so
  // late-pairing apps see the current level via `room_meta_updated`.
  pi.on("thinking_level_select", (event) => {
    const level = event?.level as ThinkingLevel | undefined;
    if (!level) return;
    _currentThinking = level;
    if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, thinking: level };
    if (!_relay || !_myRoomId) return;
    _relay.sendControl({
      type: "room_meta_update",
      room_id: _myRoomId,
      meta: { thinking: level },
    });
  });

  pi.on("message_update", (event) => {
    const ae = event.assistantMessageEvent;
    if (ae.type !== "text_delta") return;
    const projection = _applyTurnAndPublish({ type: "agent_chunk" });
    const replyTo = projection.replyTo ?? projection.activeTurnId;
    if (_owners.activeCount() === 0 || replyTo === null) return;
    _owners.broadcast(_withCurrentSession({ type: "agent_chunk", in_reply_to: replyTo, delta: ae.delta }));
  });

  // Notify every connected owner that a tool is about to run (visibility
  // only, NOT approval). tool_execution_start fires before the tool
  // executes; tool_execution_end closes the loop with the result. Together
  // they render a "Tool running… done" timeline in each paired app.
  pi.on("tool_execution_start", (event) => {
    const sessionId = _currentRemoteSessionId();
    const args = _enrichToolArgs(event.toolName, event.args);
    _appendTranscriptEvent({
      kind: "tool_requested",
      eventId: deterministicTranscriptEventId(sessionId, "tool_requested", event.toolCallId),
      sessionId,
      ts: Date.now(),
      toolCallId: event.toolCallId,
      tool: event.toolName,
      args,
    });
    if (_owners.activeCount() === 0) return;
    _owners.broadcast(_withCurrentSession({
      type: "tool_request",
      tool_call_id: event.toolCallId,
      tool: event.toolName,
      args,
    }));
  });

  pi.on("tool_execution_end", (event) => {
    // Stringify through the transcript projection helper so live == re-sync.
    const text = stringifyToolResult(event.result);
    const sessionId = _currentRemoteSessionId();
    _appendTranscriptEvent(event.isError
      ? {
          kind: "tool_finished",
          eventId: deterministicTranscriptEventId(sessionId, "tool_finished", event.toolCallId),
          sessionId,
          ts: Date.now(),
          toolCallId: event.toolCallId,
          error: text,
        }
      : {
          kind: "tool_finished",
          eventId: deterministicTranscriptEventId(sessionId, "tool_finished", event.toolCallId),
          sessionId,
          ts: Date.now(),
          toolCallId: event.toolCallId,
          result: text,
        });
    if (_owners.activeCount() === 0) return;
    const msg: ServerMessage = event.isError
      ? _withCurrentSession({ type: "tool_result", tool_call_id: event.toolCallId, error: text })
      : _withCurrentSession({ type: "tool_result", tool_call_id: event.toolCallId, result: text });
    _owners.broadcast(msg);
  });

  // Cumulative session buffer fed via `message_end`, which fires once per
  // persisted message (user, assistant, toolResult) — same hook the SDK uses
  // to persist to sessionManager (see agent-session.js:298-309). Pushing here
  // accumulates the whole session over time, so session_sync can replay every
  // turn — including turns initiated from the Pi terminal (source:"interactive")
  // or RPC. Previous impl overwrote on `agent_end` and lost everything but the
  // last turn (see diagnostics 14, 15).
  pi.on("message_end", (event) => {
    const m = event?.message as { role?: string; stopReason?: string; errorMessage?: string } | undefined;
    if (!m) return;
    if (m.role === "user" || m.role === "assistant" || m.role === "toolResult") {
      _appendLegacySdkMessageToTranscript(m as unknown as LegacyAgentMessage);
    }
    // Forward a failed turn to connected owners. Without this the app just
    // hangs with no response when the provider errors (e.g. the TUI's
    // "Provider finish_reason: error"): the SDK surfaces the failure as an
    // assistant message with stopReason "error" + an `errorMessage` (pi-ai).
    // `error` is an existing ServerMessage the app already renders — no
    // protocol/app change. `in_reply_to` ties it to the turn the app awaits.
    if (m.role === "assistant" && m.stopReason === "error" && _owners.activeCount() > 0) {
      const message = typeof m.errorMessage === "string" && m.errorMessage
        ? m.errorMessage
        : "Provider error";
      const replyTo = _activeReplyTarget();
      _applyTurnAndPublish({ type: "provider_error", turnId: replyTo });
      const errMsg: ServerMessage = _withCurrentSession(replyTo
        ? { type: "error", in_reply_to: replyTo, code: "provider_error", message }
        : { type: "error", code: "provider_error", message });
      _owners.broadcast(errMsg);
    }
  });

  pi.on("agent_end", () => {
    // Buffer is fed by `message_end`; here we only finalize the outbound
    // turn signal to every connected owner. No buffer mutation.
    const before = _turnProjection();
    const finishedTurnId = before.replyTo ?? before.activeTurnId;
    if (finishedTurnId === null) return;
    _applyTurnAndPublish({ type: "agent_done" });
    if (_owners.activeCount() > 0) {
      _owners.broadcast(_withCurrentSession({ type: "agent_done", in_reply_to: finishedTurnId }));
    }
    _maybeSendLateAttachSessionSync();
    _maybeDrainQueuedMessage();
  });

  // plan/34: the broker no longer gates delivery on busy state, so we no
  // longer notify it of turn lifecycle. Working state is still published as
  // room_meta over the relay (plan/32) below — that's independent of the
  // broker and drives the app's working indicator.
  pi.on("turn_start", (_event, ctx) => {
    const fallbackTurnId = _turnProjection().replyTo ?? _turnProjection().activeTurnId ?? `local_${randomUUID()}`;
    _applyTurnAndPublish({ type: "turn_start", fallbackTurnId });
    // Late model hydration: if the model was still unknown at connect (resolved
    // lazily by the SDK), grab it on the first turn and fan it out — so a daemon
    // whose model only materialises at turn 1 still reports it to the app.
    if (!_currentModel) {
      try {
        const m = (ctx as Partial<ExtensionContext> & { getModel?: () => { name?: string; id?: string } | undefined }).getModel?.();
        const name = m?.name ?? m?.id;
        if (name) _setCurrentModel(name);
      } catch { /* defensive — never block a turn on a model lookup */ }
    }
    // Plan/32 Part B: room_meta.working is published by the turn projection diff.
  });
  pi.on("turn_end", () => {
    const before = _turnProjection();
    const after = _applyTurnAndPublish({ type: "turn_end" });
    if (!before.working && !after.working) _publishWorking(false);
    _maybeSendLateAttachSessionSync();
    _maybeDrainQueuedMessage();
  });

  // Plan/32: compaction feedback. compact() doesn't run a turn, so bracket it
  // with working=true/false here. Returning void = no veto → default
  // compaction proceeds.
  pi.on("session_before_compact", () => {
    _applyTurnAndPublish({ type: "compaction_start", turnId: `compact_${randomUUID()}` });
  });
  pi.on("session_compact", (event) => {
    const entry = event?.compactionEntry as { summary?: unknown; tokensBefore?: unknown } | undefined;
    const summary = typeof entry?.summary === "string" ? entry.summary : "";
    const tokensBefore = typeof entry?.tokensBefore === "number" ? entry.tokensBefore : 0;
    const ts = Date.now();
    // (2) Persist in history: the CompactionEntry never reaches message_end
    // (only user/assistant/toolResult), so append a transcript event that the
    // session_history projection turns into a `compaction` event.
    const sessionId = _currentRemoteSessionId();
    _appendTranscriptEvent({
      kind: "compaction_recorded",
      eventId: deterministicTranscriptEventId(sessionId, "compaction_recorded", String(ts)),
      sessionId,
      ts,
      summary,
      tokensBefore,
    });
    // (1) Live result to every connected owner.
    _owners.broadcast(_withCurrentSession({ type: "compaction", summary, tokens_before: tokensBefore, ts }));
    // (3) Working ends.
    _applyTurnAndPublish({ type: "compaction_done" });
    _applyTurnAndPublish({ type: "turn_end" });
    _publishWorking(false);
    _maybeSendLateAttachSessionSync();
  });

  // Re-capture the freshest base ctx on every session replacement so compact
  // never operates on a stale captured ctx — this is the fix for the
  // "stale after session replacement" crash when the app taps Compact after a
  // New session. Fires on startup/new/fork/reload/resume; the ctx is always
  // bound to the current session.
  //
  // Important: the documented session_start ctx is a base ExtensionContext; it
  // does NOT provide sendMessage/sendUserMessage. Message delivery after a
  // replacement is only safe through a fresh extension instance (new factory
  // call with fresh `pi`) or through a ReplacedSessionContext passed to a
  // withSession callback when Remote Pi itself initiated the replacement.
  pi.on("session_start", (_event, ctx) => {
    _lastEventCtx = ctx;
    _sdkSessionProjection.bindSessionContext(ctx);
    _captureRemoteSession(ctx);
    // Rearm a reused-but-disposed instance. The session_shutdown teardown (below)
    // sets _disposed=true assuming the host re-evaluates THIS module fresh for the
    // replacement session, yielding a new instance with _disposed=false. Some hosts
    // instead REUSE the same module instance across ctx.newSession() — then the
    // _disposed latch is never cleared (nothing else resets it), so the relay never
    // reconnects and /remote-pi (via _cmdRoot) silently early-returns until a full
    // Pi restart. Clearing the latch + re-running the idempotent connect path
    // restores the relay automatically. No-op when a fresh instance IS created
    // (_disposed=false there → never fires) and at first boot.
    if (_disposed) {
      _disposed = false;
      void _cmdRoot(ctx);
    }
  });

  // Tear down THIS instance's live handles when the SDK replaces the session
  // (switch_session / new / fork / reload / quit). This is the fix for the
  // "double mesh connection" the Cockpit hits when it restores a saved
  // conversation via switch_session on boot.
  //
  // Why it happens: the Pi SDK loads extensions through jiti with
  // `moduleCache: false`, so every session replacement re-evaluates THIS module
  // FRESH — a brand-new instance whose `_meshNode`, `_relay`, and command-surface
  // cwd lock start back at null. The OUTGOING instance's broker socket, relay WS,
  // and cwd-lock UDS keep running regardless (module state is gone, but the OS
  // handles aren't). In daemon mode (REMOTE_PI_DAEMON=1, set by the Cockpit) the
  // fresh instance re-runs `_cmdRoot` on load, so without releasing the old
  // handles first we end up with TWO mesh peers under the same name on the
  // broker + two rooms on the relay. The per-cwd lock is meant to stop the
  // second connect, but its 500 ms connect-probe can miss the still-bound old
  // socket while the event loop is saturated at boot, fall through to the
  // stale-socket unlink path, and let the fresh instance bind a second lock.
  //
  // `session_shutdown` fires on the OUTGOING extension runner and is AWAITED by
  // the SDK (`teardownCurrent`) BEFORE the replacement runtime — and thus the
  // fresh extension instance — is created. Closing the mesh node, relay, and
  // lock here guarantees the next instance starts from a clean slate and stands
  // up exactly ONE connection bound to the restored session. Idempotent +
  // best-effort: every step is guarded so a partially-initialised instance
  // (e.g. shutdown lands mid-`_cmdRoot`) tears down without throwing.
  pi.on("session_shutdown", async () => {
    // Mark disposed FIRST so an in-flight `_cmdRoot`/`_cmdJoin` (the deferred
    // daemon connect) aborts instead of finishing as a ghost after we've torn
    // down — the race that left a mute `Backoffice` behind when the Cockpit
    // fired switch_session right after boot.
    _disposed = true;
    // Captured contexts from the outgoing runtime are invalid after this point.
    // Relay timers / reconnect callbacks can still fire briefly, so make them
    // fall through to no-op helpers instead of touching stale ctx.ui/abort.
    _lastCtx = null;
    _lastEventCtx = null;
    _messageApi = null;
    _pi = null;
    _sdkSessionProjection.clearStaleContexts();
    if (_meshNode) {
      try { await _meshNode.close(); } catch { /* best-effort */ }
      _meshNode = null;
      _owners.setMeshSession(null);
      _owners.setSessionPeerCount(0);
    }
    // No bye reason: the process keeps running and the fresh instance re-joins
    // the SAME relay room, so an explicit offline→online flap would be wrong.
    if (_state !== "idle") _goIdle();
    _localMeshCommands.releaseCwdLock();
  });

  // ── Commands ──────────────────────────────────────────────────────────────
  legacyRuntime.ports.commands.register(pi, legacyRuntime);

};

export default extension;

function createIndexDeps(): LegacyIndexDeps {
  return {
    relay: {
      status: _relayStatus,
      start: async (input) => {
        const keypair = _pairingCoordinator.currentKeypair();
        if (!keypair) throw new Error("remote-pi identity not loaded");
        const relay = new RelayClient(toWebSocketUrl(input.relayUrl), keypair);
        await relay.connect({ roomId: input.roomId, roomMeta: input.roomMeta });
        _relay = relay;
        _relayUrl = input.relayUrl;
        if (input.roomId) _myRoomId = input.roomId;
        return { relay, roomId: input.roomId };
      },
      stop: (reason) => { _goIdle(reason); },
      sendRoomMeta: (patch) => {
        _publishRoomMetaPatch({
          session_id: patch.session_id,
          model: patch.model,
          thinking: patch.thinking as ThinkingLevel | undefined,
          working: patch.working,
        });
      },
      onOuterMessage: (handler) => {
        const relay = _relay;
        if (!relay) return () => undefined;
        relay.on("message", handler);
        return () => { relay.off("message", handler); };
      },
      attachCrossPcBridge: async () => { _attachBridgeIfReady(); },
      detachCrossPcBridge: () => { _meshNode?.detachBridge(); },
      relay: () => _relay,
      setRelay: (relay) => { _relay = relay; },
    },
    owners: {
      activeCount: () => _owners.activeCount(),
      attach: (input) => {
        const channel = _owners.attach({
          ...input,
          roomId: input.roomId ?? _myRoomId ?? undefined,
          turnActive: _turnProjection().working,
        });
        _applyTurnAndPublish({ type: "peer_attached", target: { kind: "owner", id: input.peerId } });
        return channel;
      },
      detach: (peerId, reason) => { _owners.detach(peerId, reason); },
      broadcast: (message) => _owners.broadcast(message),
      routeFrom: (sender, message) => _owners.routeFrom(sender, message),
      lateAttachTargets: () => _owners.lateAttachTargets(),
    },
    session: {
      bindApi: (boundPi) => {
        _pi = boundPi;
        _messageApi = boundPi;
        _sdkSessionProjection.bindApi(boundPi);
      },
      bindCommandContext: _rememberCommandCtx,
      bindSessionContext: (ctx) => {
        _lastEventCtx = ctx;
        _sdkSessionProjection.bindSessionContext(ctx);
        _captureRemoteSession(ctx);
      },
      clearStaleContexts: () => {
        _lastCtx = null;
        _lastEventCtx = null;
        _messageApi = null;
        _pi = null;
        _sdkSessionProjection.clearStaleContexts();
      },
      sendPiMessage: (...args) => _sendPiMessage(...args),
      wakeAgent: (...args) => _sdkSessionProjection.wakeAgent(...args),
      publishWorking: _publishWorking,
      handleClientMessage: (sender, message) => _routeClientMessageFrom(sender as PlainPeerChannel, message, _lastEventCtx ?? _lastCtx ?? _noopCtx),
    },
    commands: {
      register: (boundPi, runtime) => { createLegacyCommandSurface().register(boundPi, runtime); },
    },
  };
}

function createLegacyCommandSurface(): CommandSurfacePort {
  return createCommandSurface({
    deployAgentNetworkSkill: _deployAgentNetworkSkill,
    refreshPairingsCache: () => { void _owners.refreshPairingsCache(); },
    registerAgentTools: (pi) => registerAgentTools(pi, () => _meshNode?.peer() ?? null),
    registerCommands: _registerRemotePiCommands,
    startDaemonMode: _startDaemonMode,
  });
}

function _rememberCommandCtx(ctx: ExtensionCommandContext): void {
  _lastCtx = ctx;
  _sdkSessionProjection.bindCommandContext(ctx);
}

function _registerRemotePiCommands(pi: ExtensionAPI): void {
  const runWithCtx = (
    run: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>,
  ) => async (args: string, ctx: ExtensionCommandContext) => {
    _rememberCommandCtx(ctx);
    return run(args, ctx);
  };

  const specs: RemotePiCommandSpec[] = [
    { suffix: "setup", description: "Run the setup wizard and update local config", run: runWithCtx(async (_args, ctx) => { await _cmdSetup(ctx); }) },
    { suffix: "status", description: "Show local mesh + relay status", run: runWithCtx((_args, ctx) => { _cmdStatus(ctx); }) },
    { suffix: "stop", description: "Stop everything (leave local mesh + disconnect relay)", run: runWithCtx(async (_args, ctx) => { await _cmdStop(ctx); }) },
    { suffix: "pair", description: "Show a QR code to pair a new mobile device (optional: --ttl <seconds>)", run: runWithCtx(async (args, ctx) => { await _cmdPair(ctx, args); }) },
    { suffix: "devices", description: "List paired mobile devices", run: runWithCtx(async (_args, ctx) => { await _cmdList(ctx); }) },
    { suffix: "revoke", description: "Revoke a paired device by its shortid", complete: async (prefix) => _shortidCompletions(prefix), run: runWithCtx(async (args, ctx) => { await _cmdRevoke(args, ctx); }) },
    { suffix: "set-relay", description: "Persist a new relay URL to user config", run: runWithCtx((args, ctx) => { _cmdSetRelay(args, ctx); }) },
    { suffix: "peers", description: "List local + cross-PC mesh peers, grouped by PC label", run: runWithCtx(async (_args, ctx) => { await _cmdPeers(ctx); }) },
    { suffix: "create", description: "Register a folder as a daemon and start it (when the supervisor is running)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.create(args, ctx); }) },
    { suffix: "remove", description: "Stop + unregister a daemon by id (local config is preserved)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.remove(args, ctx); }) },
    { suffix: "daemons", description: "List registered daemons + state", run: runWithCtx(async (_args, ctx) => { await _daemonCommands.list(ctx); }) },
    { suffix: "daemon start", description: "Start daemons: all, or one by id (`daemon start <id>`)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.start(ctx, args || undefined); }) },
    { suffix: "daemon stop", description: "Stop daemons: all, or one by id (`daemon stop <id>`)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.stop(ctx, args || undefined); }) },
    { suffix: "daemon restart", description: "Restart daemons: all, or one by id (`daemon restart <id>`)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.restart(ctx, args || undefined); }) },
    { suffix: "daemon status", description: "Show fleet runtime status (pid, uptime, restarts)", run: runWithCtx(async (_args, ctx) => { await _daemonCommands.status(ctx); }) },
    { suffix: "daemon send", description: "Send a prompt to a daemon: `daemon send <id> \"<text>\"`", run: runWithCtx(async (args, ctx) => { await _daemonCommands.send(args, ctx); }) },
    { suffix: "cron", completionValues: ["cron", "cron add", "cron list", "cron remove", "cron enable", "cron disable", "cron run", "cron log"], description: "Schedule recurring prompts to daemons: `cron <add|list|remove|enable|disable|run|log>`", run: runWithCtx(async (args, ctx) => { await _cronCommands.run(args, ctx); }) },
    { suffix: "install", description: "Install pi-supervisord as a system service + link the remote-pi CLI (systemd/launchd/Task Scheduler; Windows prompts for admin)", run: runWithCtx((_args, ctx) => { _serviceCommands.install(ctx, { linkCli: true }); }) },
    { suffix: "uninstall", description: "Remove the pi-supervisord system service + the CLI shims (daemons registry preserved; Windows prompts for admin)", run: runWithCtx((_args, ctx) => { _serviceCommands.uninstall(ctx, { linkCli: true }); }) },
  ];

  registerRemotePiCommands(
    pi,
    specs,
    async (sub, ctx) => {
      _rememberCommandCtx(ctx);
      const spec = specs
        .slice()
        .sort((a, b) => b.suffix.length - a.suffix.length)
        .find((candidate) => sub === candidate.suffix || sub.startsWith(`${candidate.suffix} `));
      if (!spec) {
        await _cmdRoot(ctx);
        return;
      }
      const args = sub === spec.suffix ? "" : sub.slice(spec.suffix.length).trim();
      await spec.run(args, ctx);
    },
  );
}

function _startDaemonMode(): void {
  const daemonCtx = {
    ui: _headlessUi(),
    cwd: process.cwd(),
  } as unknown as Pick<ExtensionContext, "ui" | "cwd">;
  setTimeout(() => { void _cmdRoot(daemonCtx); }, 0);
}

const _localMeshCommands = new LocalMeshCommands({
  isDisposed: () => _disposed,
  getState: _getState,
  meshNode: () => _meshNode,
  setMeshNode: (node) => { _meshNode = node; },
  setSessionState: (sessionName, peerCount) => {
    _owners.setMeshSession(sessionName);
    _owners.setSessionPeerCount(peerCount);
  },
  startRelay: _cmdStart,
  stopRelay: _goIdle,
  status: _cmdStatus,
  controlCtx: _controlCtx,
  emitRelayState: _emitRelayState,
  refreshFooter: _refreshFooter,
  refreshSessionPeerCount: _refreshSessionPeerCount,
  deliverMeshMessage: _deliverMeshMessageToAgent,
  attachBridgeIfReady: _attachBridgeIfReady,
  notify: _notify,
  sendPiMessage: _sendPiMessage,
});

// ── Command implementations ───────────────────────────────────────────────────

/**
 * `/remote-pi status` — full state snapshot. Two lines: local mesh + relay.
 *
 * Always callable; safe when nothing is up (renders the off variants).
 * Reuses the same icons as the footer so terminal + status output stay
 * visually consistent.
 */
function _cmdStatus(ctx: Pick<ExtensionContext, "ui">): void {
  const relayUrl = _relayUrl ?? resolveRelayUrl().url;
  const ownerSnapshot = _owners.snapshot();

  // Mesh line
  let meshLine: string;
  if (_meshNode) {
    const name = _meshNode.name();
    const count = ownerSnapshot.sessionPeerCount;
    meshLine = `🟢 Local mesh: connected as "${name}" (${count} peer${count === 1 ? "" : "s"})`;
  } else {
    meshLine = "⚪ Local mesh: not connected";
  }

  // Relay line — paired state is derived from OwnerMultiplexer snapshot.
  let relayLine: string;
  if (_state === "idle") {
    relayLine = `⚪ Relay: off (${relayUrl}) — run /remote-pi to start`;
  } else if (ownerSnapshot.activeOwnerCount > 0) {
    const count = ownerSnapshot.activeOwnerCount;
    const shortids = ownerSnapshot.ownerShortIds.join(", ");
    relayLine = `🟢 Relay: ${count} owner${count === 1 ? "" : "s"} online (${shortids}) (${relayUrl})`;
  } else {
    relayLine = ownerSnapshot.hasGlobalPairings
      ? `🟢 Relay: on, waiting for an app to connect (${relayUrl})`
      : `🟡 Relay: on, waiting for first pairing (${relayUrl})`;
  }

  ctx.ui.notify(`[remote-pi]\n  ${meshLine}\n  ${relayLine}`, "info");
}

async function _cmdPeers(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  await _localMeshCommands.peers(ctx);
}

async function _cmdRoot(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _localMeshCommands.root(ctx);
}

async function _cmdSetup(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _localMeshCommands.setup(ctx);
}

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _relayCommands.start(ctx);
}

/**
 * `/remote-pi pair` — always generates a fresh QR when the relay is up.
 *
 * The coordinator owns QR token issuance, relay auto-listening, known-peer
 * reconnect, and pair_request handling so owner/session attachment flows
 * through the owner/session ports instead of mutating index state directly.
 */
async function _cmdPair(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> {
  await _pairingCommands.pair(ctx, args);
}

async function _cmdStop(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  await _localMeshCommands.stop(ctx);
}

async function _cmdList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  await _pairingCommands.devices(ctx);
}

async function _cmdRevoke(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _pairingCommands.revoke(arg, ctx);
}

async function _shortidCompletions(
  prefix: string,
  valuePrefix = "",
): Promise<Array<{ value: string; label: string }>> {
  return _pairingCommands.completeShortid(prefix, valuePrefix);
}

function _cmdSetRelay(arg: string, ctx: Pick<ExtensionContext, "ui">): void {
  _relayCommands.setRelay(arg, ctx);
}

// Daemon, cron, and service command handlers live in extension/command_surface/*.
// The daemon/ modules remain the single source of runtime behavior.

// ── Agent-network commands (plano 19) ─────────────────────────────────────────

function _resolveExtensionDir(): string {
  // dist/index.js → dist; skills sit at <extensionRoot>/skills/. When we run
  // from src/ via tsx (dev), index.ts is in src/ and skills/ is sibling. We
  // detect by checking both locations.
  const here = fileURLToPath(import.meta.url);
  // dist/index.js or src/index.ts → parent = <dist or src>; sibling = ../skills
  const parent = here.replace(/\/[^/]+$/, "");
  const candidateA = join(parent, "..", "skills"); // dist → ../skills
  const candidateB = join(parent, "skills");        // src → skills
  if (existsSync(candidateA)) return parent.replace(/\/dist$/, "");
  if (existsSync(candidateB)) return parent;
  return parent;
}

function _deployAgentNetworkSkill(): void {
  // Pi SDK spec (core/skills.js): every skill must live at
  //   <skillsRoot>/<skill-name>/SKILL.md
  // The skill `name:` frontmatter must equal the parent directory name. We
  // ship the source pre-arranged that way so deploy is a straight copy into
  // ~/.pi/remote/skills/agent-network/SKILL.md.
  const root = _resolveExtensionDir();
  const src1 = join(root, "skills", "agent-network", "SKILL.md");
  const src2 = join(root, "..", "skills", "agent-network", "SKILL.md");
  const src = existsSync(src1) ? src1 : (existsSync(src2) ? src2 : null);
  if (!src) return;
  const dstDir = join(skillsDir(), "agent-network");
  const dst = join(dstDir, "SKILL.md");
  try {
    mkdirSync(dstDir, { recursive: true });
    copyFileSync(src, dst);
    // Cleanup legacy deploy at ~/.pi/remote/skills/agent-network.md (flat
    // layout, fails the Pi SDK's name-vs-parent-dir validation).
    const legacy = join(skillsDir(), "agent-network.md");
    if (existsSync(legacy)) {
      try { unlinkSync(legacy); } catch { /* ignored */ }
    }
  } catch { /* best-effort */ }
}

/**
 * Inject text into the agent as a user message, waking a turn. The base
 * `ExtensionAPI.sendUserMessage` is synchronous, while replacement-session
 * contexts can return a Promise; this helper handles both and treats a rejected
 * handoff as a failed delivery. The SDK runtime still owns any later turn
 * failure (no model/API key, expired auth, provider error), which surfaces in
 * the agent's own output, not back to us. Two gaps this helper closes, both of
 * which previously failed silently:
 *
 *   1. `_pi` not bound yet (activation race / mesh joined before the session
 *      attached): the old code did `if (!_pi) return`, dropping the message
 *      with no trace. We log it (the daemon forwards child stderr to its log
 *      with a cwd prefix, so it's visible in `journalctl`).
 *   2. A synchronous throw or Promise rejection from `sendUserMessage` (e.g.
 *      malformed content or a stale replacement context): the old fire-and-
 *      forget call could either propagate out of the `onMessage` callback or
 *      create a false success echo. We catch + surface it instead.
 *
 * NOTE: this does NOT make a wake that fails *inside* the SDK observable —
 * that requires a fix in the Pi runtime (no extension-level error event
 * exists for it). See `.orchestration/results/mesh-liveness-stale-peer.md`.
 */
type SendUserMessageOptions =
  NonNullable<Parameters<ExtensionAPI["sendUserMessage"]>[1]>;

type WakeAgentResult =
  | { ok: true }
  | { ok: false; detail: string };

async function _wakeAgent(
  content: Parameters<ExtensionAPI["sendUserMessage"]>[0],
  label: string,
  steeringBehavior?: SendUserMessageOptions["deliverAs"],
): Promise<WakeAgentResult> {
  const candidates = Array.from(new Set<AgentMessageApi | null>([_messageApi, _pi]));
  let lastDetail = "agent session not bound yet";
  for (const api of candidates) {
    if (!api || typeof api.sendUserMessage !== "function") continue;
    try {
      if (steeringBehavior) {
        await api.sendUserMessage(content, { deliverAs: steeringBehavior });
      } else {
        await api.sendUserMessage(content);
      }
      return { ok: true };
    } catch (err) {
      const detail = err instanceof Error ? err.message : String(err);
      lastDetail = detail;
      if (_isStaleContextError(err)) {
        _forgetStaleMessageApi(api);
        continue;
      }
      console.error(`[remote-pi] ${label}: agent rejected incoming message: ${detail}`);
      _notify(`[remote-pi] failed to process incoming message: ${detail}`, "error");
      return { ok: false, detail };
    }
  }
  console.error(`[remote-pi] ${label}: agent rejected incoming message: ${lastDetail}`);
  _notify(`[remote-pi] failed to process incoming message: ${lastDetail}`, "error");
  return { ok: false, detail: lastDetail };
}

/**
 * Deliver an inbound agent-network (mesh) message to the agent + the app.
 *
 * Display: the app renders it in the TOOL timeline (a matched
 * tool_request/tool_result "agent-network" pair) — NOT as the user's own
 * message, which is what `sendUserMessage` used to produce (the reported bug).
 *
 * Wake: we inject a CUSTOM message (role:"custom"), not a user message. The
 * SDK's `convertToLlm` maps custom → a user-role LLM message, so the agent
 * still sees + replies to it, but `message_end` does NOT buffer role:"custom",
 * so it never replays as `user_input` on session_sync. `triggerTurn` runs the
 * turn; `id` lets the LLM echo it via `agent_send(..., re=<id>)`.
 */
function _deliverMeshMessageToAgent(
  env: { id: string; from: string; re: string | null; body: unknown },
): void {
  const bodyText = typeof env.body === "string" ? env.body : JSON.stringify(env.body);
  const toolCallId = `mesh_${env.id}`;
  _owners.broadcast(_withCurrentSession({
    type: "tool_request",
    tool_call_id: toolCallId,
    tool: "agent-network",
    args: env.re
      ? { from: env.from, re: env.re, message: bodyText }
      : { from: env.from, message: bodyText },
  }));
  _owners.broadcast(_withCurrentSession({ type: "tool_result", tool_call_id: toolCallId, result: { from: env.from, message: bodyText } }));

  const label = `agent-network message from "${env.from}"`;
  if (!_pi) {
    console.error(`[remote-pi] ${label}: agent session not bound yet — message dropped`);
    return;
  }
  const header = `[agent-network] message from "${env.from}" (id=${env.id}${env.re ? `, re=${env.re}` : ""}):`;
  const footer = env.re
    ? "(This is a reply to a previous message of yours.)"
    : `(If a reply is expected, call agent_send with to="${env.from}" and re="${env.id}".)`;
  const ok = _sendPiMessage(
    { customType: "remote-pi:mesh-message", content: `${header}\n${bodyText}\n\n${footer}`, display: true },
    { triggerTurn: true },
    label,
  );
  if (!ok) _notify("[remote-pi] failed to process incoming mesh message", "error");
}

async function _cmdJoin(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _localMeshCommands.join(ctx);
}

// ── routeClientMessage ────────────────────────────────────────────────────────

/**
 * Per-channel router. Replaces the W2D-pre `routeClientMessage` which
 * implicitly used the `_peerChannel` singleton for replies. Each
 * PlainPeerChannel now carries its own `sender` and passes it here so
 * sender-specific responses (cancelled, pong, session_history) flow back
 * through the right wire instead of being broadcast.
 *
 * Broadcast messages (user_input mirror, agent_chunk, tool_*) still fan out
 * through OwnerMultiplexer from the SDK event handlers; this router only
 * handles incoming app→pi requests.
 */
function _abortCurrentTurn(
  fallbackCtx?: Pick<ExtensionContext, "abort">,
): boolean {
  const candidates: Array<Pick<ExtensionContext, "abort"> | null | undefined> = [
    _lastEventCtx,
    _lastCtx,
    fallbackCtx,
  ];

  for (const candidate of candidates) {
    if (!candidate || candidate === _noopCtx) continue;
    if (typeof candidate.abort !== "function") continue;
    try {
      candidate.abort();
      return true;
    } catch (err) {
      if (!_isStaleContextError(err)) throw err;
      if (candidate === _lastCtx) _lastCtx = null;
      if (candidate === _lastEventCtx) _lastEventCtx = null;
    }
  }

  return false;
}

type UserClientMessage = Extract<ClientMessage, { type: "user_message" }>;

function _sendDeliveryError(sender: PlainPeerChannel | null, inReplyTo: string, detail: string): void {
  const error: ServerMessage = _withCurrentSession({
    type: "error",
    code: "internal_error",
    in_reply_to: inReplyTo,
    message: `Agent rejected incoming message: ${detail}`,
  });
  if (sender) sender.send(error);
  else _owners.broadcast(error);
}

async function _deliverUserMessage(
  msg: UserClientMessage,
  sender: PlainPeerChannel | null,
  mode: "auto" | "normal" = "auto",
): Promise<void> {
  const requestedSteer = mode === "auto" && msg.streaming_behavior === "steer";
  const inferredBusySteer = mode === "auto" && !requestedSteer && _myRoomMeta?.working === true;
  const shouldSteer = requestedSteer || inferredBusySteer;
  // A reconnecting app can correctly send `steer` while our projection has no
  // turn id (for example, the turn started while no owner was attached).
  // Also be defensive for clients that send a plain user_message while the
  // room is already working. Tell the SDK this is steering; otherwise it
  // rejects the message as a normal busy prompt. Seed the projection so
  // later chunks/done have a target instead of being dropped.
  const previousTurn = _turn;
  const seededTurnId = !shouldSteer || _turnProjection().activeTurnId === null;
  if (seededTurnId) {
    _applyTurnAndPublish({ type: "user_message_accepted", turnId: msg.id, replyTo: msg.id, source: mode === "normal" ? "queued" : "app" });
  }
  const content: Parameters<ExtensionAPI["sendUserMessage"]>[0] =
    msg.images && msg.images.length > 0
      ? [
          ...msg.images.map((img) => ({ type: "image" as const, data: img.data, mimeType: img.mime })),
          { type: "text" as const, text: msg.text },
        ]
      : msg.text;
  const wake = await _wakeAgent(
    content,
    msg.images && msg.images.length > 0
      ? `app user_message id=${msg.id} (+${msg.images.length} image)`
      : `app user_message id=${msg.id}`,
    shouldSteer ? "steer" : undefined,
  );
  if (!wake.ok) {
    if (seededTurnId) {
      const before = _turnProjection();
      _turn = previousTurn;
      _publishTurnProjection(before, _turnProjection());
    }
    if (seededTurnId) {
      _applyTurnAndPublish({ type: "delivery_error", turnId: msg.id });
    }
    _sendDeliveryError(sender, msg.id, wake.detail);
    return;
  }
  const sessionId = _currentRemoteSessionId();
  const eventId = deterministicTranscriptEventId(sessionId, "user_confirmed", msg.id);
  _appendUserConfirmedTranscriptEvent({
    sessionId,
    ts: Date.now(),
    clientMessageId: msg.id,
    text: msg.text,
    ...(msg.images && msg.images.length > 0 ? { images: msg.images } : {}),
    ...(shouldSteer ? { streamingBehavior: "steer" as const } : {}),
    eventId,
  });
  _rememberDeliveredUserEvent(msg.text, msg.images, msg.id, eventId);
  const echo: ServerMessage = _withCurrentSession({
    type: "user_message",
    id: msg.id,
    text: msg.text,
    ...(msg.images && msg.images.length > 0 ? { images: msg.images } : {}),
    ...(shouldSteer ? { streaming_behavior: "steer" as const } : {}),
  });
  _owners.broadcast(echo);
}

function _maybeDrainQueuedMessage(): void {
  const projection = _turnProjection();
  const queued = projection.queuedMessage;
  if (!queued || !projection.canDrainQueuedMessage) return;
  _applyTurnAndPublish({ type: "queued_message_clear" });
  _broadcastQueuedMessageState();
  void _deliverUserMessage(_withCurrentSession({ type: "user_message", id: queued.id, text: queued.text }), null, "normal");
}

function _maybeSendLateAttachSessionSync(): void {
  const projection = _turnProjection();
  if (!projection.canFlushLateAttachSync || projection.awaitingSyncTurnId === null) return;
  const history = _buildSessionHistoryMessage(projection.awaitingSyncTurnId, undefined);
  for (const target of projection.lateAttachSyncTargets) {
    if (target.kind !== "owner") continue;
    const channel = _owners.get(target.id);
    if (!channel) continue;
    try { channel.send(history); } catch { /* best-effort per late attach */ }
  }
  _applyTurnAndPublish({ type: "flush_late_attach_sync" });
}

export function _routeClientMessageFrom(
  sender: PlainPeerChannel,
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void {
  const sessionGate = validateClientSession(msg, _currentRemoteSessionId(_lastEventCtx ?? _lastCtx));
  if (!sessionGate.ok) {
    sender.send({
      type: "error",
      code: sessionGate.code,
      in_reply_to: "id" in msg ? msg.id : undefined,
      message: sessionGate.message,
      session_id: sessionGate.currentSessionId,
    });
    return;
  }

  // session_sync has its own internal guards — handle before the strict
  // pi-binding guard so a missing _pi doesn't drop the reply.
  if (msg.type === "session_sync") {
    _handleSessionSync(sender, msg);
    return;
  }
  if (msg.type === "cancel") {
    try {
      const aborted = _abortCurrentTurn(ctx);
      if (!aborted) {
        sender.send(_withCurrentSession({
          type: "error",
          code: "internal_error",
          in_reply_to: msg.id,
          message: "No active Pi context to abort",
        }));
        return;
      }
      _applyTurnAndPublish({ type: "cancelled", turnId: msg.target_id });
      sender.send(_withCurrentSession({ type: "cancelled", in_reply_to: msg.id, target_id: msg.target_id }));
    } catch (err) {
      sender.send(_withCurrentSession({
        type: "error",
        code: "internal_error",
        in_reply_to: msg.id,
        message: `Abort failed: ${String(err)}`,
      }));
    }
    return;
  }
  if (_disposed) {
    _sessionUnavailable(sender, msg.id);
    return;
  }
  switch (msg.type) {
    case "user_message":
      // Source-of-truth rebroadcast (plan/24 W2D fix). Echo the message
      // back to every attached owner (sender included) after the SDK accepts
      // the handoff, so optimistic app bubbles only confirm on real delivery.
      // The user_message is also recorded in _transcriptEvents after SDK
      // acceptance, so a later `session_sync` returns it in history.
      void _deliverUserMessage(msg, sender).catch((err: unknown) => {
        const detail = err instanceof Error ? err.message : String(err);
        _sendDeliveryError(sender, msg.id, detail);
      });
      break;
    case "queued_message_set":
      _applyTurnAndPublish({ type: "queued_message_set", id: msg.id, text: msg.text });
      _broadcastQueuedMessageState();
      break;
    case "queued_message_clear":
      _applyTurnAndPublish({ type: "queued_message_clear" });
      _broadcastQueuedMessageState();
      break;
    case "approve_tool":
      // Approval gate was removed (plano 10.2 revisado). Type kept in
      // ClientMessage for forward-compat with a future permissions model;
      // ignore silently if the app still sends it from an older build.
      break;
    case "ping":
      sender.send({ type: "pong", in_reply_to: msg.id });
      break;
    case "pair_request":
      // Already paired — ignore subsequent pair_request to maintain idempotency.
      // (Token is already consumed and peer is in peers.json.)
      break;
    // Plan/28 — Typed app actions. Each delegates to the pure handler in
    // `actions/handlers.ts`; the only thing this layer does is unify the
    // dep injection (sender, _pi, _lastCtx, registry). `_lastCtx` may be
    // null or a narrower Pick than the handlers want, so we cast to
    // `ActionCtx` — fields that aren't present at runtime are surfaced
    // as `action_error` by the handlers, not as a TypeError.
    case "session_compact":
      // Route through _lastEventCtx (refreshed on every session_start), NOT the
      // capturable-stale _lastCtx — compact must never hit a ctx left stale by
      // a prior New session. compact() is a base-ctx method, so the
      // session_start ctx suffices. Fall back to _lastCtx defensively if no
      // session_start has landed yet (keeps the pre-replacement happy path).
      handleSessionCompact((_lastEventCtx ?? _lastCtx) as ActionCtx | null, sender, msg);
      break;
    case "session_new": {
      const actionCtx = _lastCtx as ActionCtx | null;
      if (process.env["REMOTE_PI_DAEMON"] === "1" && !actionCtx?.newSession) {
        // Headless RPC daemon has no ExtensionCommandContext, so ctx.newSession
        // is unavailable. Ack, clear remote-pi's mirror, then exit with a
        // private code; the supervisor restarts once without --continue, which
        // creates a fresh Pi session. Later restarts resume that fresh session.
        sender.send({ type: "action_ok", session_id: msg.session_id, in_reply_to: msg.id, action: "session_new" });
        _resetSessionForNew(msg.id);
        setTimeout(() => process.exit(EXIT_DAEMON_FRESH_SESSION), 100);
        break;
      }
      void handleSessionNew(
        actionCtx,
        sender,
        msg,
        (freshCtx) => {
          // newSession just made the captured _lastCtx STALE (the SDK throws
          // if it's reused). Re-capture the fresh command-capable ctx the SDK
          // passes to withSession so later command ops (another New session,
          // list_models) run on the current session, not the stale one. The
          // runtime object also carries ui/abort/cwd, so storing it in the
          // narrowly-typed _lastCtx slot is sound (mirrors the read-site casts).
          _lastCtx = freshCtx as unknown as typeof _lastCtx;
          _lastEventCtx = freshCtx as unknown as typeof _lastEventCtx;
          _sdkSessionProjection.bindCommandContext(freshCtx as ExtensionCommandContext);
          _captureRemoteSession(freshCtx);
          if (_isAgentMessageApi(freshCtx)) _messageApi = freshCtx;
          if (_disposed && _messageApi) {
            _disposed = false;
            void _cmdRoot(freshCtx as unknown as Pick<ExtensionContext, "ui" | "cwd">);
          }
        },
      ).then((created) => {
        // Pi-side reset is durable only here: handleSessionNew swaps the SDK
        // session, but the app's session_sync log (_transcriptEvents) and the
        // session clock (_sessionStartedAt) live in this module. Reset them +
        // fan out an empty history so every owner drops the stale conversation
        // — not just the sender, who also clears locally on action_ok.
        if (created) _resetSessionForNew(msg.id);
      });
      break;
    }
    case "model_set":
      if (!_pi) {
        _sessionUnavailable(sender, msg.id, "Pi model API unavailable during session replacement");
        break;
      }
      void handleModelSet(
        _pi,
        (_lastEventCtx ?? _lastCtx) as ActionCtx | null,
        ensureModelRegistry(),
        sender,
        msg,
        _persistModelDefault,
      );
      break;
    case "thinking_set":
      if (!_pi) {
        _sessionUnavailable(sender, msg.id, "Pi thinking API unavailable during session replacement");
        break;
      }
      handleThinkingSet(_pi, sender, msg);
      break;
    case "list_models":
      handleListModels(((_lastEventCtx ?? _lastCtx) as ActionCtx | null), ensureModelRegistry(), sender, msg);
      break;
  }
}

/**
 * Backward-compatible shim for legacy callers + tests that didn't track
 * a specific sender channel. Routes to the most recently attached owner,
 * mirroring the pre-W2D singleton behavior.
 */
export const routeClientMessage = (
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void => ownerHarness.fallbackRoute(msg, ctx);

// ── session_sync handler + helpers ────────────────────────────────────────────

/**
 * `session_sync` is a per-sender query: the owner asking gets the reply,
 * not the whole broadcast. Otherwise a session_sync from owner A would
 * also dump history to owner B's wire — duplicate traffic + the wrong
 * `in_reply_to`.
 */
function _handleSessionSync(
  sender: PlainPeerChannel,
  msg: Extract<ClientMessage, { type: "session_sync" }>,
): void {
  sender.send(_queuedMessageState());

  if (_sessionStartedAt === null) {
    sender.send(_withCurrentSession({
      type: "session_history",
      in_reply_to: msg.id,
      session_started_at: 0,
      events: [],
      eos: true,
      truncated: false,
    }));
    return;
  }

  sender.send(_buildSessionHistoryMessage(msg.id, msg.limit));
}

function _buildSessionHistoryMessage(
  inReplyTo: string,
  limit: number | undefined,
): Extract<ServerMessage, { type: "session_history" }> {
  // Mirror semantics: always return the last N events. App SUBSTITUTES its
  // local cache with this response — no delta/since_ts logic.
  const serverLimit = _getSyncLimit();
  const requested = limit ?? serverLimit;
  const effectiveLimit = Math.min(requested, serverLimit);  // server clamps

  const projection = projectSessionHistory({
    sessionId: _currentRemoteSessionId(),
    events: _transcriptEvents,
    limit: effectiveLimit,
  });

  return _withCurrentSession({
    type: "session_history",
    in_reply_to: inReplyTo,
    session_started_at: _sessionStartedAt ?? 0,
    events: projection.events,
    eos: true,
    truncated: projection.truncated,
  });
}

/**
 * Resets the Pi-side session view after a SUCCESSFUL `session_new`. The app's
 * New Session clears its local store on `action_ok`, but that alone isn't
 * durable: `_transcriptEvents` (which answers `session_sync`) is append-only and
 * `_sessionStartedAt` is stamped once, so a later reconnect/restart would
 * replay the OLD history. We clear the transcript event log, restamp the clock, and
 * broadcast an EMPTY `session_history` — the exact shape `_handleSessionSync`
 * sends, just with `events: []` — so every attached owner drops the stale
 * conversation. The app's `_applyHistory` substitutes its cache wholesale, so
 * no new app-side code is needed.
 *
 * Unlike a per-request session_history reply (which must go to the sender
 * channel only), this is an intentional fan-out: a new session is global state,
 * so every owner must see the reset.
 */
function _resetSessionForNew(inReplyTo: string): void {
  _transcriptEvents = [];
  _deliveredUserEventIds.clear();
  _lastTranscriptUserId = null;
  _applyTurnAndPublish({ type: "session_shutdown" });
  _resetTurnSnapshot();
  _publishWorking(false);
  _broadcastQueuedMessageState();
  _sessionStartedAt = Date.now();
  _owners.broadcast(_withCurrentSession({
    type: "session_history",
    in_reply_to: inReplyTo,
    session_started_at: _sessionStartedAt,
    events: [],
    eos: true,
    truncated: false,
  }));
}

type ToolArgs = Record<string, unknown>;
type DiffLine =
  | { kind: "context"; oldLine?: number; newLine?: number; text: string }
  | { kind: "remove"; oldLine?: number; text: string }
  | { kind: "add"; newLine?: number; text: string }
  | { kind: "ellipsis" };

function _enrichToolArgs(tool: string, args: unknown): ToolArgs {
  if (!args || typeof args !== "object") return {};
  const base = args as ToolArgs;

  switch (tool.toLowerCase()) {
    case "edit":
      return _enrichEditToolArgs(base);
    default:
      return base;
  }
}

function _enrichEditToolArgs(base: ToolArgs): ToolArgs {
  const filePath = _stringArg(base, ["path", "file_path"]);
  const rawEdits = base["edits"];
  const edits = Array.isArray(rawEdits) ? rawEdits : [base];
  const text = _readToolFile(filePath);
  const hunks: { lines: DiffLine[] }[] = [];
  let searchFrom = 0;
  for (const rawEdit of edits) {
    if (!rawEdit || typeof rawEdit !== "object") continue;
    const edit = rawEdit as ToolArgs;
    const oldText = _stringArg(edit, ["oldText", "old_text", "old_string", "oldString"]);
    const newText = _stringArg(edit, ["newText", "new_text", "new_string", "newString"]);
    if (!oldText && !newText) continue;

    const matchAt = oldText && text !== null ? text.indexOf(oldText, searchFrom) : -1;
    const fallbackAt = oldText && matchAt < 0 && text !== null ? text.indexOf(oldText) : matchAt;
    const startOffset = fallbackAt >= 0 ? fallbackAt : searchFrom;
    if (text === null) continue;
    const hunk = _buildEditHunk(text, startOffset, oldText, newText);
    if (hunk.length > 0) hunks.push({ lines: hunk });
    searchFrom = startOffset + Math.max(oldText.length, 1);
  }

  return hunks.length === 0 ? base : { ...base, hunks };
}

function _readToolFile(filePath: string): string | null {
  if (!filePath) return null;
  const cwd = _currentCwd();
  const homePath = filePath.startsWith("~/") && process.env.HOME
    ? resolve(process.env.HOME, filePath.slice(2))
    : null;
  const candidates = [filePath, resolve(cwd, filePath), resolve(process.cwd(), filePath), homePath]
    .filter((p): p is string => typeof p === "string");
  for (const candidate of candidates) {
    try {
      return readFileSync(candidate, "utf8");
    } catch {
      // try next candidate
    }
  }
  return null;
}


function _buildEditHunk(
  fileText: string,
  startOffset: number,
  oldText: string,
  newText: string,
): DiffLine[] {
  const context = 4;
  const fileLines = fileText.split("\n");
  const oldLines = _splitPreviewLines(oldText);
  const newLines = _splitPreviewLines(newText);
  const oldStart = _lineNumberAt(fileText, startOffset);
  const newStart = oldStart;
  const startIndex = oldStart - 1;
  const beforeStart = Math.max(0, startIndex - context);
  const afterStart = startIndex + oldLines.length;
  const afterEnd = Math.min(fileLines.length, afterStart + context);
  const out: DiffLine[] = [];

  if (beforeStart > 0) out.push({ kind: "ellipsis" });
  for (let i = beforeStart; i < startIndex; i++) {
    out.push({ kind: "context", oldLine: i + 1, newLine: i + 1, text: fileLines[i] ?? "" });
  }
  let commonPrefix = 0;
  while (
    commonPrefix < oldLines.length &&
    commonPrefix < newLines.length &&
    oldLines[commonPrefix] === newLines[commonPrefix]
  ) {
    commonPrefix++;
  }

  let commonSuffix = 0;
  while (
    commonSuffix < oldLines.length - commonPrefix &&
    commonSuffix < newLines.length - commonPrefix &&
    oldLines[oldLines.length - 1 - commonSuffix] === newLines[newLines.length - 1 - commonSuffix]
  ) {
    commonSuffix++;
  }

  for (let i = 0; i < commonPrefix; i++) {
    out.push({ kind: "context", oldLine: oldStart + i, newLine: newStart + i, text: oldLines[i] ?? "" });
  }
  for (let i = commonPrefix; i < oldLines.length - commonSuffix; i++) {
    out.push({ kind: "remove", oldLine: oldStart + i, text: oldLines[i] ?? "" });
  }
  for (let i = commonPrefix; i < newLines.length - commonSuffix; i++) {
    out.push({ kind: "add", newLine: newStart + i, text: newLines[i] ?? "" });
  }
  for (let i = oldLines.length - commonSuffix; i < oldLines.length; i++) {
    const newLine = newStart + newLines.length - (oldLines.length - i);
    out.push({ kind: "context", oldLine: oldStart + i, newLine, text: oldLines[i] ?? "" });
  }
  for (let i = afterStart; i < afterEnd; i++) {
    const newLine = newStart + newLines.length + (i - afterStart);
    out.push({ kind: "context", oldLine: i + 1, newLine, text: fileLines[i] ?? "" });
  }
  if (afterEnd < fileLines.length) out.push({ kind: "ellipsis" });
  return out;
}

function _lineNumberAt(text: string, offset: number): number {
  let line = 1;
  for (let i = 0; i < Math.max(0, offset); i++) if (text[i] === "\n") line++;
  return line;
}

function _splitPreviewLines(text: string): string[] {
  if (!text) return [];
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

function _stringArg(args: ToolArgs, keys: string[]): string {
  for (const key of keys) {
    const value = args[key];
    if (typeof value === "string") return value;
  }
  return "";
}

/** Legacy adapter retained for tests and compatibility probes. The history
 * projection itself is now `mapLegacyAgentMessagesToTranscriptEvents` followed
 * by `projectSessionHistory`, so SDK-message mapping rules live in
 * `session/transcript_projection.ts` instead of this runtime module. */
export function _mapAgentMessagesToEvents(
  messages: LegacyAgentMessage[],
): SessionHistoryEvent[] {
  const sessionId = _currentRemoteSessionId();
  return projectSessionHistory({
    sessionId,
    events: mapLegacyAgentMessagesToTranscriptEvents({ sessionId, messages }),
    limit: Number.MAX_SAFE_INTEGER,
  }).events;
}

// ── Standalone CLI ────────────────────────────────────────────────────────────

// Supervisor restart command planning/execution lives in command_surface/supervisor_restart.ts.

function _isDirectRun(): boolean {
  try {
    return fileURLToPath(import.meta.url) === realpathSync(process.argv[1] ?? "");
  } catch {
    return false;
  }
}

if (_isDirectRun()) {
  const [, , subcmd, ...cliArgs] = process.argv;
  if (subcmd === "devices" || subcmd === "list") {
    const peers = await listPeers();
    if (peers.length === 0) { console.log("[remote-pi] No peers"); }
    else { for (const p of peers) console.log(`• ${p.remote_epk.slice(0, 8)} — ${p.name}`); }
  } else if (subcmd === "revoke") {
    const shortid = (cliArgs[0] ?? "").trim();
    if (!shortid) {
      console.log("Usage: revoke <shortid>");
    } else {
      const peers = await listPeers();
      const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));
      if (matches.length === 0) console.log(`No peer matching '${shortid}'`);
      else if (matches.length > 1) console.log(`Ambiguous: ${matches.map((p) => p.remote_epk.slice(0, 8)).join(", ")}`);
      else {
        const peer = matches[0]!;
        const { removePeer } = await import("./pairing/storage.js");
        await removePeer(peer.remote_epk);
        console.log(`Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`);
      }
    }
  } else if (subcmd === "set-relay") {
    const raw = (cliArgs[0] ?? "").trim();
    if (!raw) {
      console.log(`Usage: set-relay <url> (default: ${kDefaultRelayUrl})`);
    } else if (isWebSocketScheme(raw)) {
      console.log(`Use http:// or https://. The extension converts to WebSocket automatically.`);
    } else if (!isValidRelayUrl(raw)) {
      console.log(`Invalid URL: ${raw}. Must start with http:// or https://`);
    } else {
      saveConfig({ relay: raw });
      console.log(`Relay set to ${raw}`);
    }
  } else if (subcmd === "create") {
    // Standalone: `remote-pi create <cwd> [--name "X"]`. The shell already
    // split the args and stripped the outer quotes, so an arg like
    // `Tmp Agent` arrives as a single element with embedded space. Re-add
    // quotes around any arg containing whitespace so the regex-based
    // parser (shared with the slash-command path) sees the same shape
    // as it would from a Pi interactive prompt.
    const joined = cliArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    await _daemonCommands.create(joined, {
      ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"],
    });
  } else if (subcmd === "remove") {
    const id = (cliArgs[0] ?? "").trim();
    await _daemonCommands.remove(id, {
      ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"],
    });
  } else if (subcmd === "daemons") {
    // Mirror the slash handler: ask the supervisor when reachable,
    // fall back to registry-only when not.
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    await _daemonCommands.list(stubCtx);
  } else if (subcmd === "daemon") {
    // `remote-pi daemon <op> [args]`. Reuse the fleet-ops handlers — they
    // already accept a minimal ctx with `notify`.
    const op = cliArgs[0] ?? "";
    const rest = cliArgs.slice(1).map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    if      (op === "start")   { await _daemonCommands.start(stubCtx, cliArgs[1]); }
    else if (op === "stop")    { await _daemonCommands.stop(stubCtx, cliArgs[1]); }
    else if (op === "restart") { await _daemonCommands.restart(stubCtx, cliArgs[1]); }
    else if (op === "status")  { await _daemonCommands.status(stubCtx); }
    else if (op === "send")    { await _daemonCommands.send(rest, stubCtx); }
    else {
      console.log("Usage: remote-pi daemon <start|stop|restart [<id>]|status|send <id> \"<text>\">");
    }
  } else if (subcmd === "cron") {
    // `remote-pi cron <op> [args]`. Re-quote args with spaces so the shared
    // parser sees the same shape as a Pi slash prompt.
    const joined = cliArgs.map((a) => (/\s/.test(a) ? `"${a}"` : a)).join(" ");
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    await _cronCommands.run(joined, stubCtx);
  } else if (subcmd === "peers") {
    // Read-only roster of the local + cross-PC mesh. Unlike `devices` (which
    // reads paired phones from peers.json), the mesh roster lives only in the
    // running broker's memory, so we probe the UDS broker. The probe never
    // registers as a peer — it leaves no trace on the mesh (see
    // Broker._tryObserverProbe). Null = no broker reachable on this machine.
    const peers = await probeListPeers(sessionSockPath(LOCAL_SESSION_NAME));
    if (peers === null) {
      console.log("[remote-pi] Mesh offline — no agent is running on this machine.");
    } else {
      console.log(`[remote-pi] peers:\n${formatPeerInventory(peers)}`);
    }
  } else if (subcmd === "claude") {
    await _cmdClaudeCli(cliArgs);
  } else if (subcmd === "install") {
    // CLI mode = user installed via `npm install -g remote-pi`, so the
    // `remote-pi` / `pi-supervisord` bins are already on $PATH via npm's
    // global prefix. Explicit `linkCli: false` so we never stomp those
    // with symlinks pointing at a parallel Pi-extension install.
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    // Propagate failure as a non-zero exit so callers (Cockpit / CI) detect it
    // — installService throws on a failed schtasks/launchctl/systemctl step.
    if (!_serviceCommands.install(stubCtx, { linkCli: false })) process.exit(1);
  } else if (subcmd === "uninstall") {
    const stubCtx = { ui: { notify: (msg: string) => console.log(msg) } as unknown as ExtensionContext["ui"] };
    // `linkCli: true` even from the CLI: unlinking is ALWAYS safe and must run
    // regardless of how install ran. `unlinkCliBinaries` only removes OUR
    // reserved symlinks (`remote-pi` / `pi-supervisord`) under `~/.local/bin`;
    // npm-global bins live in a different prefix and are never touched. So a
    // user who installed via the TUI (`/remote-pi install`, which links) and
    // uninstalls from a shell still gets the links cleaned up — the asymmetry
    // that left an orphaned `~/.local/bin/remote-pi` behind.
    _serviceCommands.uninstall(stubCtx, { linkCli: true });
  } else if (subcmd === "restart-supervisor") {
    restartSupervisor();
  } else {
    console.log([
      "Usage: remote-pi <command>",
      "",
      "Daemon registry:",
      "  create <cwd> [--name \"Name\"]   Register a folder as a daemon",
      "  remove <id>                     Unregister a daemon",
      "  daemons                         List registered daemons",
      "",
      "Fleet control:",
      "  daemon start [<id>]             Start all daemons, or one by id",
      "  daemon stop [<id>]              Stop all daemons, or one by id",
      "  daemon restart [<id>]           Restart all daemons, or one by id",
      "  daemon status                   Show pid / uptime / restarts",
      "  daemon send <id> \"<text>\"       Send a prompt to a daemon",
      "  cron add <id> \"<expr>\" \"<txt>\"  Schedule a recurring prompt (≥60s; --tz, --wake)",
      "  cron list|run|remove|log        Manage scheduled prompts (needs the supervisor)",
      "",
      "Service:",
      "  install                         Install pi-supervisord as a system service",
      "  uninstall                       Remove the system service",
      "  restart-supervisor              Restart the pi-supervisord process",
      "",
      "Devices:",
      "  devices                         List paired phones (peers.json)",
      "  revoke <shortid>                Revoke a paired device",
      "",
      "Config:",
      "  set-relay <url>                 Set the relay URL (http:// or https://)",
      "",
      "Agent mesh:",
      "  peers                           List agents on the local + cross-PC mesh",
      "  claude [cwd]                    Start Claude Code connected to the agent mesh",
    ].join("\n"));
  }
}

// ── `remote-pi claude` — launch Claude Code connected to the mesh ─────────────

/**
 * Resolve the packaged agent-network skill path
 * (`<pkgRoot>/skills/agent-network/SKILL.md`). Single source of truth shared
 * by both runtimes: Pi discovers it via `resources_discover`, and the Claude
 * launcher injects it as a system prompt (see `_cmdClaudeCli`). Returns null
 * if the file is missing (e.g. running before `pnpm build`).
 */
function _agentNetworkSkillPath(): string | null {
  const here = fileURLToPath(import.meta.url);            // dist/index.js (or src/index.ts via tsx)
  const pkgRoot = dirname(dirname(here));                 // package root (dist → ..; src → ..)
  const skill = join(pkgRoot, "skills", "agent-network", "SKILL.md");
  return existsSync(skill) ? skill : null;
}

async function _cmdClaudeCli(args: string[]): Promise<void> {
  // Contract: `remote-pi claude [cwd] [claude-flags...]`. The optional cwd is
  // ONLY the leading positional (first token, not a flag); everything after it
  // is forwarded verbatim to the `claude` binary (e.g. `--resume`, `-c`,
  // `-p "prompt"`). Restricting cwd to the leading token avoids mistaking a
  // flag's value (e.g. the id in `--resume <id>`) for the cwd.
  const hasCwdArg = args.length > 0 && !args[0]!.startsWith("-");
  const targetCwd = hasCwdArg ? args[0]! : process.cwd();
  const passthroughArgs = hasCwdArg ? args.slice(1) : args;

  // Wizard when no local config exists
  if (!localConfigExists(targetCwd)) {
    const suggested = defaultAgentName(targetCwd);
    process.stdout.write(`\n[remote-pi] No config found for ${targetCwd}\n`);
    process.stdout.write("Let's set up this agent.\n\n");

    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const agentName: string = await new Promise((res) =>
      rl.question(`Agent name [${suggested}]: `, (ans) => { rl.close(); res(ans.trim() || suggested); }),
    );

    saveLocalConfig(targetCwd, { agent_name: agentName, auto_start_relay: true });
    process.stdout.write(`[remote-pi] Config saved: agent="${agentName}"\n\n`);
  }

  // Resolve mesh server script path (dist/mcp/mesh_server.js)
  const here = fileURLToPath(import.meta.url);
  const distRoot = dirname(here);
  const meshServerPath = resolve(distRoot, "mcp/mesh_server.js");

  if (!existsSync(meshServerPath)) {
    console.log(`[remote-pi] mesh server not found at ${meshServerPath}. Run pnpm build first.`);
    process.exit(1);
  }

  const absCwd = resolve(targetCwd);
  const SERVER_NAME = "remote-pi-mesh";

  // The mesh MCP must be visible ONLY inside a `remote-pi claude` session — a
  // plain `claude` in the same repo must NOT inherit it (otherwise every
  // ordinary session silently joins the mesh as a stray agent).
  //
  // Older builds registered the server with `claude mcp add -s local`. That
  // scope lives in `~/.claude.json` keyed by the **git repo root** and is
  // inherited by EVERY claude session under that root — which is exactly the
  // leak we're closing. So we no longer write any persistent scope; we load
  // the server through an ephemeral `--mcp-config <tmpfile>` passed on the
  // launch command line (see below). That config is session-only: it is never
  // recorded in any scope `claude mcp list` enumerates, so a normal `claude`
  // sees nothing.
  //
  // Migration: best-effort scrub of the stale `-s local` entry that prior
  // versions left behind (and that is the source of the inherited-mesh bug).
  // Idempotent — a no-op (non-zero, ignored) when the entry is already gone.
  spawnSync("claude", ["mcp", "remove", SERVER_NAME, "-s", "local"], {
    cwd: absCwd, stdio: "ignore", shell: false,
  });

  // Ephemeral MCP config consumed by `--mcp-config` below. We do NOT bake a
  // `cwd` into it: the server resolves its folder from its own `process.cwd()`,
  // which Claude sets to the directory the session was launched in (verified
  // empirically — NOT the git root, NOT CLAUDE_PROJECT_DIR). We spawn claude
  // with `cwd: absCwd`, the MCP child inherits it, so the server self-identifies
  // as the right agent without leaking that path to any other session.
  // Unique per pid so concurrent `remote-pi claude` launches don't collide.
  const mcpConfigPath = join(tmpdir(), `remote-pi-mesh-mcp-${process.pid}.json`);
  writeFileSync(mcpConfigPath, JSON.stringify({
    mcpServers: {
      [SERVER_NAME]: { command: process.execPath, args: [meshServerPath] },
    },
  }));

  // Inject the agent-network protocol as a system prompt instead of deploying a
  // skill file into ~/.claude. Anyone running `remote-pi claude` is here to use
  // the mesh, so load the protocol unconditionally — no lazy skill gating, no
  // global skills-dir pollution, and the packaged file is the single source of
  // truth shared with the Pi runtime. Skipped only if the file is missing.
  const skillPath = _agentNetworkSkillPath();

  // Launch flags:
  //   --mcp-config <tmpfile>                       — load the mesh server for
  //       THIS session only (never a persistent scope). We intentionally omit
  //       `--strict-mcp-config` so the user's own persistent MCP servers stay
  //       available alongside the mesh.
  //   --dangerously-load-development-channels TAG  — enable claude/channel push
  //       for our local (non-allowlisted) server, so incoming mesh messages
  //       wake Claude instead of waiting for a get_messages poll. Entries must
  //       be tagged: `server:<name>` for a manually configured MCP server
  //       (`plugin:<name>@<marketplace>` is the plugin form). Shows a one-time
  //       confirmation dialog at startup. Works against the `--mcp-config`
  //       server in current Claude Code; if a build ever fails to match it, the
  //       per-turn `get_messages` poll (mandated by the mesh protocol) still
  //       delivers — we lose the wake, not the messages.
  //   --dangerously-skip-permissions               — auto-approve tool calls
  //   --append-system-prompt-file=<skill>           — load the mesh protocol
  // `--append-system-prompt-file` uses the glued `--flag=value` form (a SINGLE
  // argv token) on purpose: tools that restore a session by capturing and
  // replaying the live process's argv (e.g. cmux) drop the TRAILING token,
  // which here was the skill path — leaving a dangling `--append-system-prompt-file`
  // → `claude` aborts with "argument missing" and the session never comes back.
  // As one token, the worst case is the whole flag being dropped: claude still
  // starts (just without the injected protocol), which is recoverable instead
  // of fatal. (The other flags stay separate pairs — never last, so unaffected,
  // and we don't risk a parser that may not accept `=`.)
  // Any extra args the user passed (e.g. `--resume`, `-c`) are appended last so
  // they reach the claude binary; ours come first as sensible defaults.
  try {
    spawnSync("claude", [
      "--mcp-config", mcpConfigPath,
      "--dangerously-load-development-channels", `server:${SERVER_NAME}`,
      "--dangerously-skip-permissions",
      ...(skillPath ? [`--append-system-prompt-file=${skillPath}`] : []),
      ...passthroughArgs,
    ], {
      cwd: absCwd,
      stdio: "inherit",
      shell: false,
    });
  } finally {
    // Session over — drop the ephemeral config so it never lingers as a stray
    // file. spawnSync blocks until claude exits, so claude has long since read
    // it. Best-effort: ignore if already gone.
    try { unlinkSync(mcpConfigPath); } catch { /* already removed */ }
  }
}
