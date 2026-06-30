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
import {
  SettingsManager,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionContext,
  type ExtensionFactory,
} from "@earendil-works/pi-coding-agent";
import { qrSession } from "./pairing/qr.js";
import type { Ed25519Keypair } from "./pairing/crypto.js";
import {
  addPeer,
  getOrCreateEd25519Keypair,
  KeyringUnavailableError,
  listPeers,
  removePeer,
} from "./pairing/storage.js";
import type {
  ClientMessage,
  ServerMessage,
  SessionHistoryEvent,
  ThinkingLevel,
} from "./protocol/types.js";
import type { TranscriptEvent } from "./session/transcript_event.js";
import {
  deterministicTranscriptEventId,
  stringifyToolResult,
  type LegacyAgentMessage,
} from "./session/transcript_projection.js";
import { RelayClient, RoomAlreadyOpenError } from "./transport/relay_client.js";
import type { PeerChannel, PlainPeerChannel } from "./transport/peer_channel.js";
import { OwnerMultiplexer } from "./extension/owner_multiplexer.js";
import {
  createRemotePiCommandSurfaceHarness,
  createRemotePiTestHarness,
  type OwnerMultiplexerTestHarness,
  type RemotePiCommandSurfaceHarness,
  type RemotePiTestHarness,
} from "./extension/testing.js";
import { createCommandSurface } from "./extension/command_surface.js";
import { registerRemotePiCommands, type RemotePiCommandSpec } from "./extension/command_surface/commands.js";
import { LocalMeshCommands } from "./extension/command_surface/local_mesh_commands.js";
import { DaemonCommands } from "./extension/command_surface/daemon_commands.js";
import { CronCommands } from "./extension/command_surface/cron_commands.js";
import { PairingCommands } from "./extension/command_surface/pairing_commands.js";
import { PairingCoordinator } from "./extension/command_surface/pairing_coordinator.js";
import { RelayCommands } from "./extension/command_surface/relay_commands.js";
import { ServiceCommands } from "./extension/command_surface/service_commands.js";
import { restartSupervisor, restartSupervisorCommand } from "./extension/command_surface/supervisor_restart.js";
import { createStandaloneCliDeps, isDirectRun, launchClaudeCli, runStandaloneRemotePiCli } from "./extension/command_surface/standalone_cli.js";
import { probeListPeers } from "./extension/probe_list_peers.js";
export { probeListPeers } from "./extension/probe_list_peers.js";
export { restartSupervisorCommand as _restartSupervisorCommand } from "./extension/command_surface/supervisor_restart.js";
export type { RestartStep } from "./extension/command_surface/supervisor_restart.js";
import { createRemotePiExtensionRuntime, registerLifecycleHooks } from "./extension/composition_root.js";
import { createLegacyIndexPorts, type LegacyIndexDeps } from "./extension/legacy_ports.js";
import type { CommandSurfacePort, WakeAgentResult } from "./extension/ports.js";
import { SdkSessionProjection } from "./session/sdk_session_projection.js";
import { roomIdFor } from "./rooms.js";
import { registerAgentTools } from "./session/tools.js";
import { formatPeerInventory } from "./session/peer_inventory.js";
import { MeshNode } from "./session/mesh_node.js";
import { reachabilityBackoffMs } from "./reachability/reachability_contract.js";
import {
  createRelayTransportPort,
  RelayStartAbortedError,
  type RelayStateSnapshot,
} from "./extension/relay_transport.js";
import { validateClientSession } from "./session/session_gate.js";
import type { TurnEvent, TurnProjection } from "./session/turn_state.js";
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
} from "./session/local_config.js";
import { updateFooter, type FooterState } from "./ui/footer.js";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, copyFileSync, existsSync, unlinkSync, readFileSync, writeFileSync } from "node:fs";
import { hostname } from "node:os";
import {
  resolveRelayUrl,
  saveConfig,
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

/** Relay connectivity as seen by an RPC client (Cockpit). Derived by the relay
 *  transport adapter: "disconnected" = relay off (idle); "connected" = live
 *  WS; "reconnecting" = was on, WS dropped, retrying. Surfaced via the
 *  `remote-pi:relay-state` custom message (see `_emitRelayState`). */
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";

/** Sentinel prefix for a transparent control message an RPC client sends on the
 *  `prompt` channel (stdin). The `input` hook intercepts it, runs the action,
 *  and swallows it (`action:"handled"`) so it never becomes an LLM turn or a
 *  transcript entry. Starts with NUL so it can't collide with real user input
 *  and doesn't begin with "/" (which would route to the command parser). */
export const CTRL_PREFIX = "\x00remote-pi-ctrl:";
let _myRoomId: string | null = null;   // this Pi's room id (derived from cwd)

const _relayTransport = createRelayTransportPort({
  createRelay: (url, keypair) => new RelayClient(url, keypair),
  toWebSocketUrl,
  backoffMs: reachabilityBackoffMs,
  now: () => Date.now(),
  setTimer: (cb, delayMs) => setTimeout(cb, delayMs),
  clearTimer: (timer) => clearTimeout(timer),
  emitRelayState: (snapshot) => _sendRelayStateSnapshot(snapshot),
});

const _owners: OwnerMultiplexer = new OwnerMultiplexer({
  createChannel: (input) => _relayTransport.createPeerChannel({
    peerId: input.peerId,
    roomId: input.roomId ?? _myRoomId ?? undefined,
    onMessage: input.onMessage,
    onDisconnect: input.onDisconnect,
  }),
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
      sessionStartedAt: _sdkSessionProjection.sessionStartedAtOrNow(),
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
    _sdkSessionProjection.recordOwnerAttached(peerId);
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

let _stopOwnerIngress: (() => void) | null = null;

function _ensureOwnerIngressListener(): void {
  if (_stopOwnerIngress) return;
  _stopOwnerIngress = _relayTransport.onOuterMessage((line) => {
    void _handleOwnerOuterLine(line);
  });
}

function _stopOwnerIngressListener(): void {
  _stopOwnerIngress?.();
  _stopOwnerIngress = null;
}

async function _handleOwnerOuterLine(line: string): Promise<void> {
  const currentRelay = _relayTransport.currentRelayForOwnerChannels();
  if (!currentRelay) return;
  await _owners.handleOuterLine({
    line,
    relay: currentRelay,
    roomId: _myRoomId ?? undefined,
    turnActive: () => _turnProjection().working,
    isCurrent: () => (
      !_disposed &&
      _state === "started" &&
      currentRelay === _relayTransport.currentRelayForOwnerChannels()
    ),
    onMessage: (message, sender) => _routeClientMessageFrom(
      sender as PlainPeerChannel,
      message,
      _lastEventCtx ?? _lastCtx ?? _noopCtx,
    ),
    onDisconnect: (peerId) => _onPeerDisconnect(peerId),
    sendToPeer: (peerId, message) => _sendOwnerMessageToPeer(peerId, message),
  });
}

function _sendOwnerMessageToPeer(peerId: string, message: ServerMessage): void {
  const existing = _owners.get(peerId);
  if (existing) {
    existing.send(message);
    return;
  }

  let transient: (PeerChannel & { detach(): void }) | null = null;
  try {
    transient = _relayTransport.createPeerChannel({
      peerId,
      roomId: _myRoomId ?? undefined,
      onMessage: () => undefined,
      onDisconnect: () => undefined,
    });
    transient.send(message);
  } catch {
    // Best-effort error/pair response: relay reconnect + app session_sync recover.
  } finally {
    try { transient?.detach(); } catch { /* best-effort transient channel cleanup */ }
  }
}

const _pairingCoordinator = new PairingCoordinator({
  getState: () => _state,
  setState: (state) => { _state = state; },
  relay: () => _relayTransport.currentRelayForOwnerChannels(),
  setRelay: () => { /* relay ownership lives in relay_transport.ts */ },
  relayUrl: () => _relayTransport.currentRelayUrl(),
  setRelayUrl: () => { /* relay URL ownership lives in relay_transport.ts */ },
  roomId: () => _myRoomId,
  setRoomId: (roomId) => { _myRoomId = roomId; },
  roomMeta: () => _myRoomMeta,
  setRoomMeta: (meta) => { _myRoomMeta = meta as typeof _myRoomMeta; },
  sessionStartedAt: () => _sdkSessionProjection.sessionStartedAtValue(),
  setSessionStartedAt: (ts) => { _sdkSessionProjection.setSessionStartedAt(ts); },
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
    _sdkSessionProjection.recordOwnerAttached(peerId);
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
  handleClientMessage: (sender, message) => _sdkSessionProjection.handleClientMessage(sender, message),
  joinLocalMesh: async (ctx) => { if (!_meshNode) await _cmdJoin(ctx); },
  refreshFooter: (ctx) => _refreshFooter(ctx),
  notify: (message, type, ctx) => _notify(message, type, ctx),
  sendPiMessage: (message, options, label) => _sendPiMessage(message, options, label),
  onRelayClose: () => _onRelayClose(),
  attachBridgeIfReady: () => _attachBridgeIfReady(),
  emitRelayState: (force) => _emitRelayState(force),
  setSiblings: (siblings) => { _meshNode?.setSiblings(siblings); },
});
_pairingCoordinator.startRelay = (ctx) => _startRelayViaTransport(ctx);

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
// MeshNode owns the local UDS mesh plus BrokerRemote/PiForwardClient internals.
// RelayTransport owns when the app relay is handed to MeshNode for cross-PC
// bridge attach/detach during relay start, reconnect, close, and stop.
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
  _publishRoomMetaPatch({ model: name });
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
  _relayTransport.sendRoomMeta(patch);
}

// ── Cross-PC mesh wiring (plan/25 Wave B/C) ───────────────────────────────────

/** Compatibility shim for command-surface call sites that discover the local
 * mesh after relay start. RelayTransport owns the actual bridge lifecycle. */
function _attachBridgeIfReady(): void {
  void _relayTransport.attachCrossPcBridge({
    meshNode: () => _meshNode,
    keypair: () => _pairingCoordinator.currentKeypair() ?? null,
  });
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
  const delivered = _sdkSessionProjection.sendPiMessage(message, options);
  if (!delivered) console.error(`[remote-pi] ${label}: Pi rejected message: agent session not bound yet`);
  return delivered;
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

// SDK session identity, session clock, and transcript replay state are owned by
// SdkSessionProjection. Index keeps only thin compatibility wrappers for legacy
// command/test surfaces.

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
async function connectForTest(ctx: unknown): Promise<void> {
  const real = ctx as Parameters<typeof _cmdJoin>[0];
  await _cmdJoin(real);
  await _cmdStart(real);
}

/** Test-only: tear everything down (mirrors `/remote-pi stop`). */
async function stopForTest(ctx: unknown): Promise<void> {
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
  _sdkSessionProjection.setLegacyMessageBufferForTest(msgs);
}

export function _setTranscriptEventsForTest(events: TranscriptEvent[]): void {
  _sdkSessionProjection.setTranscriptEventsForTest(events);
}

/** Test-only accessor: returns a defensive copy of the transcript event log. */
export function _getTranscriptEventsForTest(): TranscriptEvent[] {
  return _sdkSessionProjection.getTranscriptEventsForTest();
}

/** Test-only override of session started timestamp. */
export function _setSessionStartedAtForTest(ts: number | null): void {
  _sdkSessionProjection.setSessionStartedAt(ts);
}

export function _getRemoteSessionIdForTest(): string | null {
  return _sdkSessionProjection.currentSessionIdForTest();
}

export function _setRemoteSessionIdForTest(id: string | null): void {
  _sdkSessionProjection.setSessionIdForTest(id);
}

function _currentRemoteSessionId(ctx?: unknown): string {
  return _sdkSessionProjection.currentRemoteSessionId(ctx ?? _lastEventCtx ?? _lastCtx ?? undefined);
}

function _withCurrentSession<T extends object>(msg: T): T & { session_id: string } {
  return _sdkSessionProjection.currentSessionMessage(msg);
}

function _appendTranscriptEvent(event: TranscriptEvent): void {
  _sdkSessionProjection.appendTranscriptEvent(event);
}

function _rememberDeliveredUserEvent(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
  clientMessageId: string,
  eventId: string,
): void {
  _sdkSessionProjection.rememberDeliveredUserEvent(text, images, clientMessageId, eventId);
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
  _sdkSessionProjection.appendUserConfirmedTranscriptEvent(input);
}

function _appendLegacySdkMessageToTranscript(message: LegacyAgentMessage): void {
  _sdkSessionProjection.appendLegacySdkMessageToTranscript(message);
}

function _captureRemoteSession(ctx: unknown): string {
  return _sdkSessionProjection.captureRemoteSession(ctx);
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
  _sdkSessionProjection.clearApiBindings();
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

function _turnProjection(): TurnProjection {
  return _sdkSessionProjection.turnProjection();
}

function _applyTurnAndPublish(event: TurnEvent): TurnProjection {
  return _sdkSessionProjection.applyTurn(event);
}

function _resetTurnSnapshot(): void {
  _sdkSessionProjection.resetTurnSnapshot();
}

function _activeReplyTarget(): string | null {
  const projection = _turnProjection();
  return projection.replyTo ?? projection.activeTurnId;
}

// Module-level pi reference
let _pi: ExtensionAPI | null = null;

// ── Relay reconnect state ─────────────────────────────────────────────────────
// Backoffs in ms: 1s, 2s, 5s, 10s, 30s, then stays at 30s; the transport
// adapter owns the timer/counter and this test hook observes that owner.

/** Test-only: exposes pending reconnect timer state. */
export function _hasPendingReconnect(): boolean {
  return _relayTransport.hasPendingReconnect();
}

/**
 * Public state-snapshot helper. Returns the derived UX state, not the raw
 * `_state` enum: the W2D refactor collapsed the internal machine to
 * `idle | started` and made `paired` a derived metric
 * (`ownerMultiplexer.activeCount() > 0`). Tests and the footer keep the
 * three-state mental model via this getter.
 */
function getStateForTest(): "idle" | "started" | "paired" {
  if (_state === "idle") return "idle";
  return _owners.activeCount() > 0 ? "paired" : "started";
}

export const commandSurfaceHarness: RemotePiCommandSurfaceHarness = createRemotePiCommandSurfaceHarness({
  connect: (ctx) => connectForTest(ctx),
  stop: (ctx) => stopForTest(ctx),
  state: () => getStateForTest(),
  handleControl: (cmd) => _handleControl(cmd),
  resetCwdLock: () => _resetCwdLockForTest(),
  restartSupervisorCommand: (platform, uid) => restartSupervisorCommand(platform, uid),
});

/** Test-only: number of owners currently attached via PlainPeerChannel. */
export const _getActivePeerCountForTest = (): number => ownerHarness.activeOwnerCount();

/** Test-only: true if a specific peer (base64 std) has an attached channel. */
export const _hasActivePeerForTest = (appPeerIdStd: string): boolean => ownerHarness.hasOwner(appPeerIdStd);


// ── Multi-channel helpers ─────────────────────────────────────────────────────

function _currentQueueStateMessage(): Extract<ServerMessage, { type: "queued_message_state" }> {
  return _sdkSessionProjection.queuedMessageState();
}

function _broadcastQueuedMessageState(): void {
  _sdkSessionProjection.broadcastQueuedMessageState();
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

  _stopOwnerIngressListener();

  // Tear down every per-owner channel and clear the multiplexer registry.
  _owners.detachAll();
  _applyTurnAndPublish({ type: "session_shutdown" });
  _resetTurnSnapshot();
  _publishWorking(false);

  // Cancel any pending reconnect attempt and close the live relay. Critical:
  // /remote-pi stop must win the race against a scheduled reconnect.
  _relayTransport.stop(byeReason);

  // Stop the mesh poller — it's bound to the relay-up lifecycle so a new
  // relay start will spin up a fresh instance (with potentially a new relay
  // URL if the user changed it via /remote-pi relay url).
  _pairingCoordinator.stopSelfRevoke();

  // Preserve projection-owned sessionStartedAt + transcript events across
  // stop/start cycles. The Pi agent session outlives the relay connection —
  // `message_end` keeps firing for terminal turns even while idle, and the
  // transcript event log must survive so those turns appear in session_sync.
  // Only Pi session replacement resets these.

  _state = "idle";
  _refreshFooter();
  _emitRelayState();  // → disconnected
}

/**
 * Called when the relay WS closes unexpectedly (network drop, relay restart,
 * etc.). Does a **partial** teardown — keeps projection-owned session clock,
 * transcript events, and relay-transport-owned retry state so the session can resume on reconnect.
 *
 * Peer (app) reconnect after a successful relay reconnect is handled by the
 * existing auto-listener via `peers.json` lookup, so we don't need to track
 * the prior peer here; we just go back to `started` and wait.
 */
function _onRelayClose(): void {
  if (_state === "idle") return;  // already torn down (e.g. /remote-pi stop)

  // Keep owner ingress subscribed through the relay transport so the fresh
  // reconnect socket can reattach known peers from their first post-reconnect
  // message. Only per-owner channels are relay-socket-specific.

  // Detach every per-owner channel — relay is gone, none can route. The
  // auto-listener re-attaches owners after `_attemptReconnect` succeeds
  // (via the same known-peer + pair_request paths used on first connect).
  // Relay drop is not an explicit stop: do not send bye and do not clear
  // session history or reconnect-owned state.
  _owners.detachAllForRelayDrop();
  if (!_turnProjection().working) _resetTurnSnapshot();

  _state = "started";
  _refreshFooter();
}

// ── Relay state event + transparent control channel (Cockpit toggle) ─────────

/** Current relay connectivity, derived by the relay transport adapter. */
function _relayStatus(): RelayConnectivity {
  if (getStateForTest() === "idle") return "disconnected";
  return _relayTransport.status();
}

/**
 * Ask the relay transport to emit the `remote-pi:relay-state` custom message.
 * The transport owns the dedupe and snapshot shape; index only bridges to Pi's
 * message API.
 */
function _emitRelayState(force = false): void {
  _relayTransport.emitRelayState(force);
}

function _sendRelayStateSnapshot(snapshot: RelayStateSnapshot): void {
  // During session_shutdown we intentionally clear the message API before
  // tearing down relay state. There is no live Pi session to notify, and the
  // replacement instance / withSession rearm will publish its own fresh state.
  if (!_messageApi && !_pi) return;
  _sendPiMessage({
    customType: "remote-pi:relay-state",
    content: `Relay ${snapshot.status}`,
    details: {
      status: snapshot.status,
      connected: snapshot.connected,
      ...(snapshot.relayUrl ? { relayUrl: snapshot.relayUrl } : {}),
      ...(snapshot.room ? { room: snapshot.room } : {}),
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
    sessionStartedAt: _sdkSessionProjection.sessionStartedAtOrNow(),
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

function _isAgentMessageApi(value: unknown): value is AgentMessageApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<AgentMessageApi>;
  return typeof candidate.sendMessage === "function" && typeof candidate.sendUserMessage === "function";
}

const _sdkSessionProjection: SdkSessionProjection = new SdkSessionProjection({
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
    _publishRoomMetaPatch({ thinking: level });
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

  // Cumulative transcript event log is fed via `message_end`, which fires once
  // per persisted message (user, assistant, toolResult) — same hook the SDK uses
  // to persist to sessionManager (see agent-session.js:298-309). Appending typed
  // transcript events here accumulates the whole session over time, so
  // session_sync can replay every turn — including turns initiated from the Pi
  // terminal (source:"interactive") or RPC. Previous impl overwrote on
  // `agent_end` and lost everything but the last turn (see diagnostics 14, 15).
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
    if (m.role === "assistant" && m.stopReason === "error") {
      const message = typeof m.errorMessage === "string" && m.errorMessage
        ? m.errorMessage
        : "Provider error";
      const replyTo = _activeReplyTarget();
      const sessionId = _currentRemoteSessionId();
      const ts = Date.now();
      _appendTranscriptEvent({
        kind: "provider_error",
        eventId: deterministicTranscriptEventId(sessionId, "provider_error", replyTo ?? String(ts)),
        sessionId,
        ts,
        ...(replyTo ? { replyTo } : {}),
        code: "provider_error",
        message,
      });
      _applyTurnAndPublish({ type: "provider_error", turnId: replyTo });
      if (_owners.activeCount() === 0) return;
      const errMsg: ServerMessage = _withCurrentSession(replyTo
        ? { type: "error", in_reply_to: replyTo, code: "provider_error", message }
        : { type: "error", code: "provider_error", message });
      _owners.broadcast(errMsg);
    }
  });

  pi.on("agent_end", () => {
    // Message content is fed by `message_end`; here we record the terminal
    // assistant_done boundary and finalize the outbound turn signal.
    const before = _turnProjection();
    const finishedTurnId = before.replyTo ?? before.activeTurnId;
    if (finishedTurnId === null) return;
    const sessionId = _currentRemoteSessionId();
    _appendTranscriptEvent({
      kind: "assistant_done",
      eventId: deterministicTranscriptEventId(sessionId, "assistant_done", finishedTurnId),
      sessionId,
      ts: Date.now(),
      replyTo: finishedTurnId,
    });
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

  // Re-capture the freshest base ctx on every session replacement and tear down
  // outgoing session resources through the composition-root ports. The bound
  // legacy port methods preserve the stale-context and in-flight connect guards
  // that previously lived inline here.
  registerLifecycleHooks(pi, legacyRuntime.ports, legacyRuntime.epoch);

  // ── Commands ──────────────────────────────────────────────────────────────
  legacyRuntime.ports.commands.register(pi, legacyRuntime);

};

export default extension;

function createIndexDeps(): LegacyIndexDeps {
  return {
    relay: {
      status: _relayStatus,
      start: (input) => {
        _ensureOwnerIngressListener();
        return _relayTransport.start({
          ...input,
          keypair: input.keypair ?? _pairingCoordinator.currentKeypair() ?? undefined,
          isDisposed: () => _disposed,
          onUnexpectedClose: () => _onRelayClose(),
        });
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
      onOuterMessage: (handler) => _relayTransport.onOuterMessage(handler),
      attachCrossPcBridge: (input) => _relayTransport.attachCrossPcBridge(input),
      detachCrossPcBridge: () => { _relayTransport.detachCrossPcBridge(); },
      relay: () => _relayTransport.currentRelayForOwnerChannels(),
      setRelay: () => { /* relay ownership lives in relay_transport.ts */ },
    },
    owners: {
      activeCount: () => _owners.activeCount(),
      attach: (input) => {
        const channel = _owners.attach({
          ...input,
          roomId: input.roomId ?? _myRoomId ?? undefined,
          turnActive: _turnProjection().working,
        });
        _sdkSessionProjection.recordOwnerAttached(input.peerId);
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
        _sdkSessionProjection.clearStaleContexts();
        _lastCtx = null;
        _lastEventCtx = null;
        _messageApi = null;
        _pi = null;
      },
      sendPiMessage: (...args) => _sendPiMessage(...args),
      wakeAgent: (...args) => _sdkSessionProjection.wakeAgent(...args),
      publishWorking: _publishWorking,
      handleClientMessage: (sender, message) => _sdkSessionProjection.handleClientMessage(sender, message),
    },
    commands: {
      register: (boundPi, runtime) => { createLegacyCommandSurface().register(boundPi, runtime); },
      ensureStarted: (ctx) => {
        if (!_disposed) return;
        _disposed = false;
        void _cmdRoot(ctx);
      },
      prepareSessionShutdown: () => {
        _disposed = true;
      },
      closeMesh: async () => {
        if (_meshNode) {
          try { await _meshNode.close(); } catch { /* best-effort */ }
          _meshNode = null;
          _owners.setMeshSession(null);
          _owners.setSessionPeerCount(0);
        }
        _localMeshCommands.releaseCwdLock();
      },
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

function _bindReplacementSessionContext(freshCtx: ActionCtx): void {
  _lastCtx = freshCtx as unknown as typeof _lastCtx;
  _lastEventCtx = freshCtx as unknown as typeof _lastEventCtx;
  _pi = null;
  _sdkSessionProjection.bindReplacementContext(freshCtx);
  _messageApi = _sdkSessionProjection.messageApiBinding();
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
  getState: getStateForTest,
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
  const relayUrl = _relayTransport.currentRelayUrl() ?? resolveRelayUrl().url;
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

type PairingCoordinatorRelayInternals = {
  cachedEd25519: Ed25519Keypair | null;
  ensureSelfRevoke(relayUrl: string, edKp: Ed25519Keypair): void;
};

function _pairingCoordinatorInternals(): PairingCoordinatorRelayInternals {
  return _pairingCoordinator as unknown as PairingCoordinatorRelayInternals;
}

async function _startRelayViaTransport(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  if (_state !== "idle") {
    ctx.ui.notify("[remote-pi] Already started.", "warning");
    return;
  }

  let edKp: Ed25519Keypair;
  try {
    edKp = await getOrCreateEd25519Keypair();
  } catch (err) {
    if (err instanceof KeyringUnavailableError) {
      ctx.ui.notify(
        "[remote-pi] Could not read this machine's identity: the system " +
        "keychain is locked or access was denied. Unlock it (open the app / " +
        "log in) and run /remote-pi again. Your pairing is NOT lost. " +
        "(Set REMOTE_PI_ALLOW_FILE_IDENTITY=1 only for headless hosts.)",
        "error",
      );
      return;
    }
    throw err;
  }
  _pairingCoordinatorInternals().cachedEd25519 = edKp;

  const { url: relayUrl, source } = resolveRelayUrl();
  const myShort = Buffer.from(edKp.publicKey).toString("base64").slice(0, 8);
  const cwd = "cwd" in ctx && typeof ctx.cwd === "string" ? ctx.cwd : process.cwd();
  const sessionName = _displayName(cwd);
  const roomId = roomIdFor(cwd, sessionName);

  if (!_currentModelName()) {
    try {
      const c = ctx as Partial<ExtensionContext> & {
        model?: { name?: string; id?: string };
        getModel?: () => { name?: string; id?: string } | undefined;
      };
      const live = c.getModel?.() ?? c.model;
      if (live) {
        _currentModel = live.name ?? live.id ?? undefined;
      } else {
        const sm = SettingsManager.create(cwd);
        const provider = sm.getDefaultProvider();
        const modelId = sm.getDefaultModel();
        if (modelId) {
          const found = provider ? ensureModelRegistry().find(provider, modelId) : undefined;
          _currentModel = found?.name ?? modelId;
        }
      }
    } catch { /* defensive — never block start on a model lookup */ }
  }

  try {
    _currentThinking = _pi?.getThinkingLevel() as ThinkingLevel | undefined;
  } catch { /* defensive — never block /remote-pi start on this */ }

  const sessionId = _currentRemoteSessionId(ctx);
  const roomMeta = { name: sessionName, cwd, session_id: sessionId } as NonNullable<typeof _myRoomMeta>;
  const modelName = _currentModelName();
  if (modelName) roomMeta.model = modelName;
  if (_currentThinking) roomMeta.thinking = _currentThinking;
  _myRoomMeta = roomMeta;

  ctx.ui.notify(`[remote-pi] Connecting to relay ${relayUrl} (source: ${source}, room: ${roomId})…`, "info");

  try {
    _ensureOwnerIngressListener();
    await _relayTransport.start({
      relayUrl,
      keypair: edKp,
      roomId,
      roomMeta,
      isDisposed: () => _disposed,
      onUnexpectedClose: () => _onRelayClose(),
    });
  } catch (err) {
    if (err instanceof RelayStartAbortedError) return;
    if (err instanceof RoomAlreadyOpenError) {
      ctx.ui.notify(
        "[remote-pi] Already running in this cwd. Stop the other terminal first.",
        "error",
      );
      return;
    }
    _notify(`[remote-pi] relay connect failed: ${String(err)}`, "error", ctx);
    return;
  }

  _myRoomId = roomId;
  _state = "started";
  _sdkSessionProjection.ensureSessionStarted();
  _refreshFooter(ctx);

  _pairingCoordinatorInternals().ensureSelfRevoke(relayUrl, edKp);
  _attachBridgeIfReady();
  _emitRelayState();
  ctx.ui.notify(`[remote-pi] state: started (peer=${myShort}) — Connected to relay ${relayUrl}`, "info");
}

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _startRelayViaTransport(ctx);
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

async function _wakeAgent(
  content: Parameters<ExtensionAPI["sendUserMessage"]>[0],
  label: string,
  steeringBehavior?: SendUserMessageOptions["deliverAs"],
): Promise<WakeAgentResult> {
  const wake = steeringBehavior
    ? await _sdkSessionProjection.wakeAgent(content, { deliverAs: steeringBehavior })
    : await _sdkSessionProjection.wakeAgent(content);
  if (!wake.ok) {
    const detail = wake.detail ?? "agent session not bound yet";
    console.error(`[remote-pi] ${label}: agent rejected incoming message: ${detail}`);
    _notify(`[remote-pi] failed to process incoming message: ${detail}`, "error");
    return { ok: false, detail };
  }
  return wake;
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
      _sdkSessionProjection.forgetStaleBinding(candidate);
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
  const turnSeed = _sdkSessionProjection.seedUserMessageTurn({
    turnId: msg.id,
    source: mode === "normal" ? "queued" : "app",
    shouldSteer,
  });
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
    turnSeed.rollback();
    if (turnSeed.seeded) {
      _applyTurnAndPublish({ type: "delivery_error", turnId: msg.id });
    }
    _sendDeliveryError(sender, msg.id, wake.detail ?? "agent session not bound yet");
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
  _sdkSessionProjection.maybeDrainQueuedMessage((queued) => _deliverUserMessage(queued, null, "normal"));
}

function _maybeSendLateAttachSessionSync(): void {
  _sdkSessionProjection.maybeSendLateAttachSessionSync((turnId) => _buildSessionHistoryMessage(turnId, undefined));
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
      // The user_message is also recorded in the projection transcript after
      // SDK acceptance, so a later `session_sync` returns it in history.
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
    // `actions/handlers.ts`; this adapter now obtains Pi SDK capabilities only
    // through SdkSessionProjection's fresh bindings. A session replacement clears
    // stale bindings, so app actions either hit the current SDK context or return
    // an explicit sender-scoped error.
    case "session_compact":
      handleSessionCompact(_sdkSessionProjection.freshActionCtx(), sender, msg);
      break;
    case "session_new": {
      const actionCtx = _sdkSessionProjection.freshCommandActionCtx();
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
          // newSession marks every pre-replacement SDK context stale. Re-capture
          // the fresh command/event/message/action capabilities in one projection
          // method and drop the old module-level _pi so later app actions cannot
          // fall back to a known-stale SDK object.
          _bindReplacementSessionContext(freshCtx);
          if (_disposed && _messageApi) {
            _disposed = false;
            void _cmdRoot(freshCtx as unknown as Pick<ExtensionContext, "ui" | "cwd">);
          }
        },
      ).then((created) => {
        // Pi-side reset is durable only here: handleSessionNew swaps the SDK
        // session, but the app's session_sync log and session clock live in
        // SdkSessionProjection. Reset them + fan out an empty history so every
        // owner drops the stale conversation
        // — not just the sender, who also clears locally on action_ok.
        if (created) _resetSessionForNew(msg.id);
      });
      break;
    }
    case "model_set": {
      const pi = _sdkSessionProjection.currentActionPi("model_set");
      if (!pi) {
        _sessionUnavailable(sender, msg.id, "Pi model API unavailable for the current session");
        break;
      }
      void handleModelSet(
        pi,
        _sdkSessionProjection.freshActionCtx(),
        ensureModelRegistry(),
        sender,
        msg,
        _persistModelDefault,
      );
      break;
    }
    case "thinking_set": {
      const pi = _sdkSessionProjection.currentActionPi("thinking_set");
      if (!pi) {
        _sessionUnavailable(sender, msg.id, "Pi thinking API unavailable for the current session");
        break;
      }
      handleThinkingSet(pi, sender, msg);
      break;
    }
    case "list_models":
      handleListModels(_sdkSessionProjection.freshActionCtx(), ensureModelRegistry(), sender, msg);
      break;
  }
}

/**
 * Backward-compatible shim for legacy callers + tests that didn't track
 * a specific sender channel. Routes to the most recently attached owner,
 * mirroring the pre-W2D singleton behavior.
 */
const routeClientMessageForTest = (
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void => ownerHarness.fallbackRoute(msg, ctx);

export const remotePiTestHarness: RemotePiTestHarness = createRemotePiTestHarness({
  connect: (ctx) => connectForTest(ctx),
  stop: (ctx) => stopForTest(ctx),
  state: () => getStateForTest(),
  routeClientMessage: (message, ctx) => routeClientMessageForTest(message, ctx),
});

// Legacy compatibility aliases. Keep these private test exports available while
// new tests migrate to the named harness above.
export const _connectForTest = remotePiTestHarness.connect;
export const _stopForTest = remotePiTestHarness.stop;
export const _getState = remotePiTestHarness.state;
export const routeClientMessage = remotePiTestHarness.routeClientMessage;

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
  sender.send(_currentQueueStateMessage());

  sender.send(_buildSessionHistoryMessage(msg.id, msg.limit));
}

function _buildSessionHistoryMessage(
  inReplyTo: string,
  limit: number | undefined,
): Extract<ServerMessage, { type: "session_history" }> {
  return _sdkSessionProjection.buildSessionHistoryMessage(inReplyTo, limit);
}

/**
 * Resets the Pi-side session view after a SUCCESSFUL `session_new`. The app's
 * New Session clears its local store on `action_ok`, but that alone isn't
 * durable: the projection transcript (which answers `session_sync`) is append-only
 * and sessionStartedAt is stamped once, so a later reconnect/restart would replay
 * the OLD history. We clear the transcript event log, restamp the clock, and
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
  _applyTurnAndPublish({ type: "session_shutdown" });
  _resetTurnSnapshot();
  _publishWorking(false);
  _broadcastQueuedMessageState();
  _sdkSessionProjection.resetSessionForNew(inReplyTo);
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
 * projection itself lives behind SdkSessionProjection, so SDK-message mapping
 * rules live in `session/transcript_projection.ts` instead of this runtime module. */
export function _mapAgentMessagesToEvents(
  messages: LegacyAgentMessage[],
): SessionHistoryEvent[] {
  return _sdkSessionProjection.mapAgentMessagesToEvents(messages);
}

// ── Standalone CLI ────────────────────────────────────────────────────────────

if (isDirectRun(import.meta.url, process.argv[1])) {
  await runStandaloneRemotePiCli(process.argv, createStandaloneCliDeps({
    commandSurface: commandSurfaceHarness,
    listPeers: () => listPeers(),
    removePeer: (remoteEpk) => removePeer(remoteEpk),
    saveRelayConfig: (url) => { saveConfig({ relay: url }); },
    daemon: _daemonCommands,
    cron: _cronCommands,
    service: _serviceCommands,
    probeListPeers: () => probeListPeers(sessionSockPath(LOCAL_SESSION_NAME)),
    formatPeerInventory: (peers) => formatPeerInventory([...peers]),
    launchClaude: (args) => launchClaudeCli(args, import.meta.url),
    restartSupervisor: () => restartSupervisor(),
  }));
}
