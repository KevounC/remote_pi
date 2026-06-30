import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { callSupervisor, supervisorOnline, SupervisorOfflineError } from "../../daemon/client.js";
import type { DaemonInfo } from "../../daemon/control_protocol.js";
import { addDaemon, listDaemons, removeDaemon } from "../../daemon/registry.js";
import { defaultAgentName, loadLocalConfig } from "../../session/local_config.js";

export type UiCtx = Pick<ExtensionContext, "ui">;

function notifyOffline(ctx: UiCtx, err: SupervisorOfflineError): void {
  ctx.ui.notify(`[remote-pi] ${err.message}`, "warning");
}

function formatDaemonTable(daemons: DaemonInfo[]): string {
  if (daemons.length === 0) return "(no daemons registered)";
  const rows = daemons.map((d) => {
    const uptime = d.uptime_s !== undefined ? `${d.uptime_s}s` : "—";
    const pid = d.pid !== undefined ? String(d.pid) : "—";
    const restarts = d.restart_count ?? 0;
    return `  ${d.id}  ${d.state.padEnd(8)}  pid=${pid}  up=${uptime}  restarts=${restarts}  ${d.name}  ${d.cwd}`;
  });
  return rows.join("\n");
}

/** Thin command-surface adapter for daemon registry and fleet operations. */
export class DaemonCommands {
  /**
   * `/remote-pi create [<cwd>] [--name <name>]`
   *
   * Promotes a folder to a daemon entry in `~/.pi/remote/daemons.json`. The
   * cwd is normalized by `addDaemon`; daemon runtime ownership remains in the
   * supervisor/registry modules.
   */
  async create(arg: string, ctx: UiCtx): Promise<void> {
    const nameMatch = arg.match(/--name\s+"([^"]+)"|--name\s+(\S+)/);
    const name = nameMatch ? (nameMatch[1] ?? nameMatch[2]) : undefined;
    const cwdRaw = arg.replace(/--name\s+"[^"]+"|--name\s+\S+/, "").trim();
    if (!cwdRaw) {
      ctx.ui.notify(
        "[remote-pi] Usage: /remote-pi create <absolute-or-relative-cwd> [--name \"Display name\"]",
        "warning",
      );
      return;
    }

    let result: { id: string; cwd: string; name: string };
    try {
      result = addDaemon(cwdRaw, name);
    } catch (err) {
      ctx.ui.notify(`[remote-pi] create failed: ${String(err)}`, "error");
      return;
    }

    ctx.ui.notify(
      `[remote-pi] Daemon registered: id=${result.id} name="${result.name}" cwd=${result.cwd}`,
      "info",
    );

    try {
      await callSupervisor({ op: "start", id: result.id });
      ctx.ui.notify(`[remote-pi] Daemon started: id=${result.id}`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) {
        ctx.ui.notify(
          `[remote-pi] Registered, but the supervisor is offline — not running yet. ` +
          `Run \`remote-pi install\` (or start \`pi-supervisord\`); it auto-starts on the next supervisor boot.`,
          "warning",
        );
        return;
      }
      ctx.ui.notify(`[remote-pi] Registered, but auto-start failed: ${String(err)}`, "error");
    }
  }

  async remove(arg: string, ctx: UiCtx): Promise<void> {
    const id = arg.trim();
    if (!id) {
      ctx.ui.notify(
        "[remote-pi] Usage: /remote-pi remove <id>. Run /remote-pi daemons to see ids.",
        "warning",
      );
      return;
    }

    try {
      const data = await callSupervisor({ op: "unregister", id });
      if (!data.removed) {
        const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
        ctx.ui.notify(`[remote-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
        return;
      }
      ctx.ui.notify(
        `[remote-pi] Daemon removed + process stopped: id=${id} cwd=${data.cwd}. ` +
        `Local config at ${data.cwd}/.pi/remote-pi/config.json was kept.`,
        "info",
      );
      return;
    } catch (err) {
      if (!(err instanceof SupervisorOfflineError)) {
        ctx.ui.notify(`[remote-pi] remove failed: ${String(err)}`, "error");
        return;
      }
    }

    let result: { removed: boolean; cwd?: string };
    try {
      result = removeDaemon(id);
    } catch (err) {
      ctx.ui.notify(`[remote-pi] remove failed: ${String(err)}`, "error");
      return;
    }

    if (!result.removed) {
      const known = listDaemons().map((d) => d.id).join(", ") || "(none)";
      ctx.ui.notify(`[remote-pi] No daemon with id "${id}". Known ids: ${known}`, "warning");
      return;
    }

    ctx.ui.notify(
      `[remote-pi] Daemon removed from registry: id=${id} cwd=${result.cwd}. ` +
      `Supervisor was offline, so any running process was NOT stopped. Local config kept.`,
      "warning",
    );
  }

  async list(ctx: UiCtx): Promise<void> {
    if (!(await supervisorOnline())) {
      const registry = listDaemons();
      if (registry.length === 0) {
        ctx.ui.notify("[remote-pi] No daemons registered. Run /remote-pi create <cwd>.", "info");
        return;
      }
      const rows = registry.map((d) => {
        const cfg = loadLocalConfig(d.cwd);
        const name = cfg.agent_name ?? defaultAgentName(d.cwd);
        return `  ${d.id}  ${name}  ${d.cwd}  (supervisor offline)`;
      }).join("\n");
      ctx.ui.notify(`[remote-pi] Daemons (registry only — run install to bring supervisor up):\n${rows}`, "info");
      return;
    }
    try {
      const data = await callSupervisor({ op: "list" });
      ctx.ui.notify(`[remote-pi] Daemons:\n${formatDaemonTable(data.daemons)}`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[remote-pi] daemons failed: ${String(err)}`, "error");
    }
  }

  async status(ctx: UiCtx): Promise<void> {
    try {
      const data = await callSupervisor({ op: "status" });
      ctx.ui.notify(`[remote-pi] Fleet status:\n${formatDaemonTable(data.daemons)}`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[remote-pi] status failed: ${String(err)}`, "error");
    }
  }

  async start(ctx: UiCtx, id?: string): Promise<void> {
    try {
      if (id) {
        const data = await callSupervisor({ op: "start", id });
        ctx.ui.notify(
          data.started
            ? `[remote-pi] Started daemon ${id} (${data.state}).`
            : `[remote-pi] Daemon ${id} already ${data.state}.`,
          "info",
        );
        return;
      }
      const data = await callSupervisor({ op: "start_all" });
      ctx.ui.notify(
        `[remote-pi] Started ${data.started.length} daemon(s), ` +
        `${data.already_running.length} already running.`,
        "info",
      );
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[remote-pi] start failed: ${String(err)}`, "error");
    }
  }

  async stop(ctx: UiCtx, id?: string): Promise<void> {
    try {
      if (id) {
        const data = await callSupervisor({ op: "stop", id });
        ctx.ui.notify(
          data.stopped
            ? `[remote-pi] Stopped daemon ${id}.`
            : `[remote-pi] Daemon ${id} already ${data.state}.`,
          "info",
        );
        return;
      }
      const data = await callSupervisor({ op: "stop_all" });
      ctx.ui.notify(
        `[remote-pi] Stopped ${data.stopped.length} daemon(s), ` +
        `${data.already_stopped.length} already stopped.`,
        "info",
      );
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[remote-pi] stop failed: ${String(err)}`, "error");
    }
  }

  async restart(ctx: UiCtx, id?: string): Promise<void> {
    try {
      if (id) {
        const data = await callSupervisor({ op: "restart", id });
        ctx.ui.notify(`[remote-pi] Restarted daemon ${id} (${data.state}).`, "info");
        return;
      }
      const data = await callSupervisor({ op: "restart_all" });
      ctx.ui.notify(`[remote-pi] Restarted ${data.restarted.length} daemon(s).`, "info");
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[remote-pi] restart failed: ${String(err)}`, "error");
    }
  }

  async send(arg: string, ctx: UiCtx): Promise<void> {
    const m = arg.match(/^(\S+)\s+(?:"([^"]*)"|(.*))$/);
    if (!m) {
      ctx.ui.notify(
        "[remote-pi] Usage: /remote-pi daemon send <id> \"<prompt text>\"",
        "warning",
      );
      return;
    }
    const id = m[1]!;
    const text = (m[2] ?? m[3] ?? "").trim();
    if (!text) {
      ctx.ui.notify("[remote-pi] daemon send: prompt text is empty.", "warning");
      return;
    }
    try {
      const data = await callSupervisor({ op: "send", id, text });
      if (data.delivered) {
        ctx.ui.notify(`[remote-pi] Sent to ${id}: ${text.slice(0, 60)}${text.length > 60 ? "…" : ""}`, "info");
      } else {
        ctx.ui.notify(`[remote-pi] daemon ${id} did not accept the prompt (not running?)`, "warning");
      }
    } catch (err) {
      if (err instanceof SupervisorOfflineError) { notifyOffline(ctx, err); return; }
      ctx.ui.notify(`[remote-pi] daemon send failed: ${String(err)}`, "error");
    }
  }
}
