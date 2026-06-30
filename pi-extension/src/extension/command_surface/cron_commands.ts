import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { callSupervisor, SupervisorOfflineError } from "../../daemon/client.js";
import type { ControlRequest } from "../../daemon/control_protocol.js";
import type { UiCtx } from "./daemon_commands.js";

/** Splits an arg string into tokens, honoring double-quoted groups. */
function tokenizeArgs(s: string): string[] {
  const out: string[] = [];
  const re = /"([^"]*)"|(\S+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(s)) !== null) out.push(m[1] !== undefined ? m[1] : m[2]!);
  return out;
}

/** Thin command-surface adapter for scheduled-prompt commands. */
export class CronCommands {
  async run(arg: string, ctx: UiCtx): Promise<void> {
    const trimmed = arg.trim();
    const sp = trimmed.indexOf(" ");
    const sub = (sp === -1 ? trimmed : trimmed.slice(0, sp)).toLowerCase();
    const rest = sp === -1 ? "" : trimmed.slice(sp + 1).trim();
    try {
      switch (sub) {
        case "":
        case "list":    return await this.list(ctx);
        case "add":     return await this.add(rest, ctx);
        case "remove":
        case "rm":      return await this.mutate({ op: "cron_remove", job_id: rest.trim() }, rest.trim(), ctx);
        case "enable":  return await this.mutate({ op: "cron_enable", job_id: rest.trim(), enabled: true }, rest.trim(), ctx);
        case "disable": return await this.mutate({ op: "cron_enable", job_id: rest.trim(), enabled: false }, rest.trim(), ctx);
        case "run":     return await this.runJob(rest.trim(), ctx);
        case "log":     return await this.log(rest, ctx);
        default:
          ctx.ui.notify("[remote-pi] Usage: /remote-pi cron <add|list|remove|enable|disable|run|log>", "warning");
      }
    } catch (err) {
      if (err instanceof SupervisorOfflineError) {
        ctx.ui.notify(
          "[remote-pi] Cron needs the supervisor running. Run `remote-pi install` " +
          "(or start `pi-supervisord`).",
          "warning",
        );
        return;
      }
      ctx.ui.notify(`[remote-pi] cron ${sub || "list"} failed: ${String(err)}`, "error");
    }
  }

  private async add(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const toks = tokenizeArgs(rest);
    let tz: string | undefined;
    let wake = false;
    let skipBusy = true;
    let catchup = false;
    const pos: string[] = [];
    for (let i = 0; i < toks.length; i++) {
      const t = toks[i]!;
      if (t === "--wake") wake = true;
      else if (t === "--no-skip-busy") skipBusy = false;
      else if (t === "--catchup") catchup = true;
      else if (t === "--tz") tz = toks[++i];
      else pos.push(t);
    }
    const [daemonId, schedule, prompt] = pos;
    if (!daemonId || !schedule || !prompt) {
      ctx.ui.notify(
        '[remote-pi] Usage: /remote-pi cron add <daemonId> "<cron-expr>" "<prompt>" ' +
        "[--tz Area/City] [--wake] [--no-skip-busy] [--catchup]",
        "warning",
      );
      return;
    }
    const req: Extract<ControlRequest, { op: "cron_add" }> = {
      op: "cron_add", daemon_id: daemonId, schedule, prompt,
    };
    if (tz) req.tz = tz;
    if (wake) req.wake = true;
    if (!skipBusy) req.skip_if_busy = false;
    if (catchup) req.catchup = true;
    const data = await callSupervisor(req);
    ctx.ui.notify(
      `[remote-pi] Cron ${data.job.id} added → daemon ${daemonId}: "${schedule}"` +
      `${tz ? ` (${tz})` : ""}. Next run: ${data.job.next_run ?? "?"}`,
      "info",
    );
  }

  private async list(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const data = await callSupervisor({ op: "cron_list" });
    if (data.jobs.length === 0) {
      ctx.ui.notify("[remote-pi] No cron jobs.", "info");
      return;
    }
    const lines = data.jobs.map((j) =>
      `${j.enabled ? "✓" : "✗"} ${j.id}  "${j.schedule}"${j.tz ? ` (${j.tz})` : ""}  → ${j.daemon_id}  ` +
      `next:${j.next_run ?? "?"}  last:${j.last_status ?? "—"}${j.last_run ? `@${j.last_run}` : ""}`,
    );
    ctx.ui.notify(`[remote-pi] Cron jobs (${data.jobs.length}):\n${lines.join("\n")}`, "info");
  }

  private async mutate(
    req: Extract<ControlRequest, { op: "cron_remove" | "cron_enable" }>,
    jobId: string,
    ctx: Pick<ExtensionContext, "ui">,
  ): Promise<void> {
    if (!jobId) {
      ctx.ui.notify(`[remote-pi] Usage: /remote-pi cron ${req.op === "cron_remove" ? "remove" : "enable|disable"} <jobId>`, "warning");
      return;
    }
    if (req.op === "cron_remove") {
      const data = await callSupervisor(req);
      ctx.ui.notify(data.removed ? `[remote-pi] Cron ${jobId} removed.` : `[remote-pi] No cron job ${jobId}.`, data.removed ? "info" : "warning");
    } else {
      const data = await callSupervisor(req);
      ctx.ui.notify(
        data.updated ? `[remote-pi] Cron ${jobId} ${data.enabled ? "enabled" : "disabled"}.` : `[remote-pi] No cron job ${jobId}.`,
        data.updated ? "info" : "warning",
      );
    }
  }

  private async runJob(jobId: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    if (!jobId) {
      ctx.ui.notify("[remote-pi] Usage: /remote-pi cron run <jobId>", "warning");
      return;
    }
    const data = await callSupervisor({ op: "cron_run", job_id: jobId });
    ctx.ui.notify(`[remote-pi] Cron ${jobId} fired now → ${data.result}`, "info");
  }

  private async log(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    const toks = tokenizeArgs(rest);
    let jobId: string | undefined;
    let tail = 20;
    for (let i = 0; i < toks.length; i++) {
      const t = toks[i]!;
      if (t === "--tail") { const n = Number(toks[++i]); if (Number.isFinite(n)) tail = n; }
      else if (!t.startsWith("--")) jobId = t;
    }
    const req: Extract<ControlRequest, { op: "cron_log" }> = { op: "cron_log", tail };
    if (jobId) req.job_id = jobId;
    const data = await callSupervisor(req);
    if (data.entries.length === 0) {
      ctx.ui.notify("[remote-pi] No cron log entries.", "info");
      return;
    }
    const lines = data.entries.map((e) =>
      `${new Date(e.ts).toISOString()}  ${e.fired ? "▶" : "∅"} ${e.result}  ${e.job_id} → ${e.daemon_id}  ${e.prompt_preview}`,
    );
    ctx.ui.notify(`[remote-pi] Cron log (last ${data.entries.length}):\n${lines.join("\n")}`, "info");
  }
}
