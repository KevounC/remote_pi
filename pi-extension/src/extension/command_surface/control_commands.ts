import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { MeshNode } from "../../session/mesh_node.js";
import type { ByeReason } from "../../protocol/types.js";
import { saveLocalConfig } from "../../session/local_config.js";

export interface ControlCommandsDeps {
  readonly getState: () => "idle" | "started" | "paired";
  readonly isDisposed: () => boolean;
  readonly meshNode: () => MeshNode | null;
  readonly controlCtx: () => Pick<ExtensionContext, "ui" | "cwd">;
  readonly startRelay: (ctx: Pick<ExtensionContext, "ui" | "cwd">) => Promise<void>;
  readonly stopRelay: (reason?: ByeReason) => void;
  readonly emitRelayState: (force?: boolean) => void;
  readonly notify: (
    msg: string,
    type?: "info" | "warning" | "error",
    ctx?: { ui?: { notify?: (message: string, type?: "info" | "warning" | "error") => void } } | null,
  ) => void;
  readonly sendPiMessage: (
    message: Parameters<ExtensionAPI["sendMessage"]>[0],
    options?: Parameters<ExtensionAPI["sendMessage"]>[1],
    label?: string,
  ) => boolean;
}

export class ControlCommands {
  constructor(private readonly deps: ControlCommandsDeps) {}

  /**
   * Handle a transparent control command from an RPC client (Cockpit), received
   * as a `CTRL_PREFIX`-tagged input the `input` hook swallowed. Toggles the relay
   * WITHOUT leaving the local mesh (relay-only: relay start up / idle down), then
   * emits the fresh state. `relay:status` just re-emits (no change) so the client
   * can sync its button after (re)attaching to the RPC stream.
   */
  async handle(cmd: string): Promise<void> {
    // `rename:<new-name>` carries an argument, so it's matched before the
    // fixed-verb switch. Renames the agent live (broker re-register + relay room
    // swap) WITHOUT restarting the process or losing the SDK session.
    if (cmd.startsWith("rename:")) {
      await this.renameAgent(cmd.slice("rename:".length).trim());
      return;
    }
    switch (cmd) {
      case "relay:on":
        if (this.deps.getState() === "idle") await this.deps.startRelay(this.deps.controlCtx());
        this.deps.emitRelayState(true);
        return;
      case "relay:off":
        if (this.deps.getState() !== "idle") this.deps.stopRelay("peer_stop");
        this.deps.emitRelayState(true);
        return;
      case "relay:toggle":
        if (this.deps.getState() === "idle") await this.deps.startRelay(this.deps.controlCtx());
        else this.deps.stopRelay("peer_stop");
        this.deps.emitRelayState(true);
        return;
      case "relay:status":
        this.deps.emitRelayState(true);
        return;
      default:
        // Unknown control verb — ignore (forward-compat: a newer client may send
        // verbs an older extension doesn't know).
        return;
    }
  }

  /**
   * Rename the agent LIVE (plan/38/41), without restarting the process or losing
   * the SDK session/conversation. Touches two layers:
   *   1. **Broker (mesh)**: `MeshNode.rename` does a soft leave+rejoin → new
   *      address `<cwd>@<newName>` (broker may add `#N` on a same-(cwd,name)
   *      collision — we use the assigned result).
   *   2. **Relay room (App↔Pi)**: the room is keyed by `(cwd, name)`, so the new
   *      name = a new room. We cycle the relay (idle → start) so the room
   *      follows; the app re-keys the conversation onto the new tile (the
   *      inherent cost of room-per-name). Skipped when the relay was off.
   * Finally re-emits `remote-pi:name-assigned` so the Cockpit updates its label.
   *
   * The explicit name IS persisted (decision E only skips the runtime `#N`).
   */
  private async renameAgent(newName: string): Promise<void> {
    if (!newName) return;  // empty rename → no-op
    const ctx = this.deps.controlCtx();
    const cwd = process.cwd();
    saveLocalConfig(cwd, { agent_name: newName });

    const meshNode = this.deps.meshNode();
    if (!meshNode) {
      // Not on the mesh yet — config persisted; applies on the next join.
      return;
    }

    // Relay room is derived from the name → cycle it so it follows. Tear down
    // first (also detaches the bridge) so the broker re-register below starts
    // clean; bring it back up after with the new name.
    const wasStarted = this.deps.getState() !== "idle";
    if (wasStarted) this.deps.stopRelay("peer_stop");

    let assigned = newName;
    try {
      assigned = await meshNode.rename(newName);  // broker soft rejoin
    } catch (err) {
      this.deps.notify(`[remote-pi] rename failed: ${String(err)}`, "error", ctx);
    }

    if (wasStarted && !this.deps.isDisposed()) await this.deps.startRelay(ctx);  // relay back up → roomIdFor(cwd, assigned)

    this.deps.sendPiMessage({
      customType: "remote-pi:name-assigned",
      content: assigned === newName
        ? `Mesh name: ${assigned}`
        : `Mesh name reassigned: "${newName}" → "${assigned}" (collision)`,
      details: { requested: newName, assigned, changed: assigned !== newName },
      display: false,
    }, undefined, "name-assigned");
  }
}
