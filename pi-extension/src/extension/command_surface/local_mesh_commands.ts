import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import { mkdirSync, realpathSync } from "node:fs";
import type { ByeReason } from "../../protocol/types.js";
import { acquireCwdLock, type AcquiredLock } from "../../session/cwd_lock.js";
import {
  ensureGlobalDirs,
  LOCAL_SESSION_NAME,
  sessionAuditPath,
  sessionSockPath,
  skillsDir,
} from "../../session/global_config.js";
import {
  defaultAgentName,
  effectiveAutoStartRelay,
  loadLocalConfig,
  localConfigExists,
  saveLocalConfig,
} from "../../session/local_config.js";
import { MeshNode } from "../../session/mesh_node.js";
import { formatPeerInventory } from "../../session/peer_inventory.js";
import { runSetupWizard, type WizardUI } from "../../session/setup_wizard.js";
import { ControlCommands } from "./control_commands.js";

export type RemotePiUi = {
  setStatus?: (key: string, value: string | undefined) => void;
  setTitle?: (title: string) => void;
  notify?: (message: string, type?: "info" | "warning" | "error") => void;
};

export type RemotePiUiContext = { ui?: RemotePiUi } | null | undefined;

type MeshEnvelope = { id: string; from: string; re: string | null; body: unknown };

export interface LocalMeshCommandsDeps {
  readonly isDisposed: () => boolean;
  readonly getState: () => "idle" | "started" | "paired";
  readonly meshNode: () => MeshNode | null;
  readonly setMeshNode: (node: MeshNode | null) => void;
  readonly setSessionState: (sessionName: string | null, peerCount: number) => void;
  readonly startRelay: (ctx: Pick<ExtensionContext, "ui" | "cwd">) => Promise<void>;
  readonly stopRelay: (reason?: ByeReason) => void;
  readonly status: (ctx: Pick<ExtensionContext, "ui">) => void;
  readonly controlCtx: () => Pick<ExtensionContext, "ui" | "cwd">;
  readonly emitRelayState: (force?: boolean) => void;
  readonly refreshFooter: (ctx?: RemotePiUiContext) => void;
  readonly refreshSessionPeerCount: (peer: MeshNode, ctx?: Pick<ExtensionContext, "ui"> | null) => void;
  readonly deliverMeshMessage: (env: MeshEnvelope) => void;
  readonly attachBridgeIfReady: () => void;
  readonly notify: (
    msg: string,
    type?: "info" | "warning" | "error",
    ctx?: RemotePiUiContext,
  ) => void;
  readonly sendPiMessage: (
    message: Parameters<ExtensionAPI["sendMessage"]>[0],
    options?: Parameters<ExtensionAPI["sendMessage"]>[1],
    label?: string,
  ) => boolean;
}

export class LocalMeshCommands {
  private cwdLock: AcquiredLock | null = null;
  private lockedName: string | null = null;
  private lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
  private readonly controlCommands: ControlCommands;

  constructor(private readonly deps: LocalMeshCommandsDeps) {
    this.controlCommands = new ControlCommands({
      getState: deps.getState,
      isDisposed: deps.isDisposed,
      meshNode: deps.meshNode,
      controlCtx: deps.controlCtx,
      startRelay: deps.startRelay,
      stopRelay: deps.stopRelay,
      emitRelayState: deps.emitRelayState,
      notify: deps.notify,
      sendPiMessage: deps.sendPiMessage,
    });
  }

  /**
   * Root handler for `/remote-pi`. On first run (no local config) drops into
   * the wizard; on subsequent runs auto-joins the local mesh + starts the
   * relay (if opted in during setup), then prints the status.
   *
   * `/remote-pi` is intentionally the only command users need day-to-day:
   * idempotent connect + status display.
   */
  async root(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    this.rememberCtx(ctx);
    // This instance was torn down (session replacement) before its deferred
    // auto-init ran — don't connect, or we'd resurrect a ghost the broker can't
    // reach. The replacement instance (fresh module) drives the live connect.
    if (this.deps.isDisposed()) return;

    const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
    // Lock identity is (cwd, name). Several agents may run in the SAME folder; the
    // requested name just has to be made unique. Derive the name the same way
    // `join` does so the lock and the mesh registration agree on identity.
    const requestedName = loadLocalConfig(cwd).agent_name || defaultAgentName(cwd);

    // Per-(cwd,name) lock, but COLLISION DOESN'T REFUSE — it auto-suffixes. If
    // `(cwd, "Backoffice")` is already held by a live agent, try
    // `(cwd, "Backoffice#2")`, `#3`, … until one binds. So a second agent with the
    // same name in the same folder comes up as `Backoffice#2` (matching the
    // broker's `_uniqueName` suffix scheme) instead of being turned away. The
    // suffix N matches the broker's (`#2`-based) so lock + mesh name line up. The
    // lock is a UDS socket (kernel auto-releases on exit/crash) bound for THIS
    // process's lifetime; repeat `/remote-pi` calls are idempotent.
    if (this.cwdLock === null) {
      for (let n = 1; n <= 1000; n++) {
        const candidate = n === 1 ? requestedName : `${requestedName}#${n}`;
        const result = await acquireCwdLock(cwd, candidate);
        if (result.ok) { this.cwdLock = result; this.lockedName = candidate; break; }
      }
      if (this.cwdLock === null) {
        ctx.ui.notify(
          `[remote-pi] Could not start: too many agents named "${requestedName}" already running in this folder.`,
          "warning",
        );
        return;
      }
    }

    // First-time wizard: no local config in this cwd → run interactive setup.
    if (!localConfigExists(cwd)) {
      const ui = ctx.ui as unknown as WizardUI;
      if (typeof ui.select !== "function") {
        this.deps.status(ctx);
        return;
      }
      const baseDefault = defaultAgentName(cwd);
      const newConfig = await runSetupWizard(ui, {
        agent_name: baseDefault,
        use_relay: true,
      });
      if (!newConfig) {
        ctx.ui.notify("[remote-pi] Setup cancelled.", "info");
        return;
      }
      saveLocalConfig(cwd, newConfig);
      ctx.ui.notify(
        `[remote-pi] Config saved to ${cwd}/.pi/remote-pi/config.json`,
        "info",
      );
      await this.join(ctx);
      if (effectiveAutoStartRelay(newConfig)) await this.deps.startRelay(ctx);
      this.deps.status(ctx);
      return;
    }

    // Returning user with config: ALWAYS join the local UDS mesh on connect; the
    // relay is the only thing gated by auto_start_relay. So auto_start_relay:false
    // now means "local mesh, no relay" (matching the first-time/wizard path and
    // the field's documented intent) — previously a false flag skipped the mesh
    // join entirely, leaving the agent (incl. daemons) fully idle.
    const config = loadLocalConfig(cwd);
    if (!this.deps.meshNode()) await this.join(ctx);
    // `join` aborts cleanly when a `session_shutdown` lands mid-connect, but
    // returns void — so recheck here before bringing the relay up, or we'd start
    // a ghost relay connection on an already-disposed instance (the replacement
    // instance owns the live connect).
    if (this.deps.isDisposed()) return;
    if (effectiveAutoStartRelay(config) && this.deps.getState() === "idle") await this.deps.startRelay(ctx);
    this.deps.status(ctx);
  }

  /**
   * `/remote-pi setup` — re-run the wizard. Defaults pre-fill from the
   * existing config so it doubles as an "edit" flow.
   */
  async setup(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    this.rememberCtx(ctx);
    const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
    const ui = ctx.ui as unknown as WizardUI;
    if (typeof ui.select !== "function") {
      ctx.ui.notify("[remote-pi] Setup requires an interactive UI.", "warning");
      return;
    }
    const current = loadLocalConfig(cwd);
    const baseDefault = defaultAgentName(cwd);
    const newConfig = await runSetupWizard(ui, {
      agent_name: current.agent_name ?? baseDefault,
      use_relay: effectiveAutoStartRelay(current),
    });
    if (!newConfig) {
      ctx.ui.notify("[remote-pi] Setup cancelled.", "info");
      return;
    }
    saveLocalConfig(cwd, newConfig);
    ctx.ui.notify(
      "[remote-pi] Config updated. Run /remote-pi to apply now.",
      "info",
    );
  }

  /**
   * Plan/25 Wave D: `/remote-pi peers`.
   *
   * Queries the local broker for the aggregated peer inventory (`list_peers`
   * returns locals + cross-PC entries prefixed with `<pc_label>:`). Formats
   * the result grouped by source so users can see at a glance who's on
   * their machine vs. on a paired sibling Pi.
   */
  async peers(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const meshNode = this.deps.meshNode();
    if (!meshNode) {
      ctx.ui.notify("[remote-pi] Not on the local mesh. Run /remote-pi to join.", "warning");
      return;
    }
    let peers: string[];
    try {
      const reply = await meshNode.request("broker", { type: "list_peers" }, 2000);
      peers = (reply.body as { peers?: string[] } | null)?.peers ?? [];
    } catch (err) {
      ctx.ui.notify(`[remote-pi] peers list failed: ${String(err)}`, "error");
      return;
    }
    // Exclude self from the printed list — `list_peers` returns every peer
    // registered with the broker including the caller, which is noise here.
    const selfName = meshNode.name();
    ctx.ui.notify(`[remote-pi] peers:\n${formatPeerInventory(peers, selfName)}`, "info");
  }

  /**
   * `/remote-pi stop` — full teardown. Leaves the local UDS mesh AND closes
   * the relay. Safe when one or both are already off. To resume, run
   * `/remote-pi` again.
   */
  async stop(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const meshNode = this.deps.meshNode();
    const meshUp = meshNode !== null;
    const relayUp = this.deps.getState() !== "idle";
    if (!meshUp && !relayUp) {
      ctx.ui.notify("[remote-pi] Already stopped — nothing to do.", "info");
      return;
    }

    if (meshNode) {
      try {
        await meshNode.close();
      } catch { /* best-effort */ }
      this.deps.setMeshNode(null);
      this.deps.setSessionState(null, 0);
    }

    if (relayUp) this.deps.stopRelay("peer_stop");

    ctx.ui.notify("[remote-pi] Stopped (mesh + relay disconnected).", "info");
    this.deps.refreshFooter(ctx);
  }

  /**
   * Joins the fixed local UDS mesh ("local" session — see LOCAL_SESSION_NAME).
   * Called by `root` on first run and on subsequent runs when the relay
   * is up and the user hasn't explicitly stopped. The session name is no
   * longer user-configurable: every Pi on the same machine joins the same
   * broker.
   */
  async join(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    this.rememberCtx(ctx);
    const cwd = "cwd" in ctx ? (ctx as ExtensionCommandContext).cwd : process.cwd();
    const local = loadLocalConfig(cwd);
    const sessionName = LOCAL_SESSION_NAME;
    // What the user configured for this agent…
    const requestedName = local.agent_name || defaultAgentName(cwd);
    // …and what we actually register: the name the cwd-lock reserved, which is
    // `requestedName` or a `#N` variant when same-named agents share this folder.
    // Falls back to requestedName when join runs without a prior `root` lock
    // (e.g. legacy/test paths).
    const agentName = this.lockedName ?? requestedName;

    if (this.deps.meshNode()) {
      ctx.ui.notify("[remote-pi] Already on the local mesh.", "warning");
      return;
    }

    ensureGlobalDirs();
    mkdirSync(join(skillsDir(), "..", "sessions", sessionName), { recursive: true });

    const sock = sessionSockPath(sessionName);
    const audit = sessionAuditPath(sessionName);
    // Forward the cwd so the broker keys this peer by (cwd, name): a same-folder
    // same-name reincarnation (switch_session re-eval, app restart) takes over the
    // name instead of registering behind a mute `name#N` ghost. Canonicalize via
    // realpath so symlinked cwds map to one identity (matches roomIdForCwd).
    let canonCwd = cwd;
    try { canonCwd = realpathSync(cwd); } catch { /* cwd missing — use raw path */ }
    const peer = new MeshNode({ sockPath: sock, name: agentName, cwd: canonCwd, auditPath: audit });

    peer.onMessage((env) => {
      const body = env.body as { type?: string } | null;
      // Broker system events: re-query broker for authoritative count.
      // Incremental ±1 drifts when peer_left is missed (leader leaves cleanly,
      // failover, etc.) — querying list_peers makes the count self-healing.
      if (body && (body.type === "peer_joined" || body.type === "peer_left")) {
        this.deps.refreshSessionPeerCount(peer, ctx);
        // Plan/25 Wave B: push fresh peer list to all siblings so their
        // remotePeers cache stays current without polling.
        void peer.request("broker", { type: "list_peers" }, 2000)
          .then((reply) => {
            const body = reply.body as {
              peers?: string[];
              peers_detailed?: Array<{ pc?: string; address?: string }>;
            } | null;
            // onLocalPeersChanged wants LOCAL-only addresses (list_peers returns
            // the aggregated local + cross-PC roster). Prefer the structured
            // roster (plan/38): a local peer has no `pc`. This is drive-letter
            // safe — a Windows local address `C:\\…@app` contains ':' but is NOT
            // remote, so the old naive `!p.includes(":")` misclassified it.
            let local: string[] | null = null;
            const detailed = body?.peers_detailed;
            if (Array.isArray(detailed)) {
              local = detailed
                .filter((p) => !p.pc && typeof p.address === "string")
                .map((p) => p.address as string);
            } else if (Array.isArray(body?.peers)) {
              // Fallback for a legacy broker without `peers_detailed`.
              local = body!.peers!.filter((p) => !p.includes(":"));
            }
            // No-op when the bridge isn't up (follower / relay down).
            if (local) peer.onLocalPeersChanged(local);
          })
          .catch(() => { /* bridge not bound yet, or list_peers failed */ });
        return;
      }
      if (env.from === "broker") return;  // other broker control messages — ignore

      // Real agent-to-agent message (SessionPeer already correlated replies via
      // env.re before this point). Show it in the app's TOOL timeline and wake
      // the agent as a CUSTOM message — never as the user's own message.
      this.deps.deliverMeshMessage(env);
    });

    // After failover (leader died, we re-elected): the new broker's peers map
    // starts fresh, but our cached peer count is stale. Re-seed it so
    // surviving peers don't carry the pre-failover count forever.
    //
    // The cross-PC bridge re-attach on failover (drop the stale broker ref,
    // re-wire against the fresh `localBroker()` if we were promoted to leader)
    // is handled INSIDE MeshNode — no manual teardown/ensure needed here.
    peer.onReconnect(() => {
      this.deps.refreshSessionPeerCount(peer, ctx);
    });

    try {
      const assigned = await peer.connect();
      // Race guard: a `session_shutdown` may have landed while `connect()` was
      // in flight (the broker now has us registered, but this instance is being
      // discarded). Leave immediately instead of publishing a ghost peer that
      // the replacement instance would then collide with as `name#2`.
      if (this.deps.isDisposed()) {
        try { await peer.close(); } catch { /* best-effort */ }
        return;
      }
      this.deps.setMeshNode(peer);
      this.deps.setSessionState(sessionName, 1);  // optimistic — overwritten by list_peers below
      // Broker broadcasts `peer_joined` only to existing peers when a new one
      // arrives — the newcomer doesn't get retroactive joined events. Ask the
      // broker for the live peer list to seed the count correctly on join.
      this.deps.refreshSessionPeerCount(peer, ctx);
      // Tell RPC clients (e.g. Cockpit) the EFFECTIVE mesh name. The broker
      // appends a `#N` suffix only on a same-(cwd,name) collision, so the name we
      // requested and the one actually assigned can differ. Emit a pure-data event
      // (display:false) carrying both + a `changed` flag so the client can rename
      // the agent in its own UI to match what the mesh/relay will show. Fired on
      // every join (incl. failover re-elect, which can re-assign the name), so the
      // client always reflects the live name, not just the first one.
      //
      // plan/38 decision E: we deliberately DO NOT persist `assigned`. A `#N` is a
      // RUNTIME collision resolution; freezing it into `agent_name` fossilizes an
      // accident and causes cross-folder name ping-pong across restarts. The clean
      // name (wizard / explicit `agent_name`) already lives in config or re-derives
      // from `basename(cwd)`; the event above carries the live `#N` for the UI.
      this.deps.sendPiMessage({
        customType: "remote-pi:name-assigned",
        content: assigned === requestedName
          ? `Mesh name: ${assigned}`
          : `Mesh name reassigned: "${requestedName}" → "${assigned}" (collision)`,
        details: { requested: requestedName, assigned, changed: assigned !== requestedName },
        display: false,
      }, undefined, "name-assigned");
      ctx.ui.notify(
        `[remote-pi] Joined local mesh as "${assigned}" (${peer.currentRole()})`,
        "info",
      );
      this.deps.refreshFooter(ctx);
      // Plan/25 Wave B/C: try to bring up cross-PC routing now that the
      // local broker exists. No-op if the relay isn't up yet (will fire
      // again from relay start).
      this.deps.attachBridgeIfReady();
    } catch (err) {
      this.deps.notify(`[remote-pi] join failed: ${String(err)}`, "error", ctx);
    }
  }

  async handleControl(cmd: string): Promise<void> {
    await this.controlCommands.handle(cmd);
  }

  getLockedNameForTest(): string | null {
    return this.lockedName;
  }

  /** Test-only: release + clear the cwd lock (the lock normally survives stop). */
  resetCwdLockForTest(): void {
    this.releaseCwdLock();
  }

  /** Session shutdown cleanup for the lock this controller owns. */
  releaseCwdLock(): void {
    try { this.cwdLock?.release(); } catch { /* ignored */ }
    this.cwdLock = null;
    this.lockedName = null;
    this.lastCtx = null;
  }

  private rememberCtx(ctx: Pick<ExtensionContext, "ui" | "cwd">): void {
    const maybe = ctx as Partial<Pick<ExtensionContext, "ui" | "abort" | "cwd">>;
    this.lastCtx = {
      ui: maybe.ui as ExtensionContext["ui"],
      abort: typeof maybe.abort === "function" ? maybe.abort.bind(ctx) : (() => undefined),
      cwd: typeof maybe.cwd === "string" ? maybe.cwd : process.cwd(),
    };
  }
}
