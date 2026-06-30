import { spawnSync } from "node:child_process";
import { LAUNCHD_LABEL, SYSTEMD_UNIT, WINDOWS_TASK_NAME } from "../../daemon/install.js";

/** One step of a restart sequence. `ignoreFailure` steps don't abort the sequence. */
export interface RestartStep { cmd: string; args: string[]; ignoreFailure?: boolean }

/** Pure: OS command sequence for restarting the supervisor service. */
export function restartSupervisorCommand(
  platform: NodeJS.Platform,
  uid: number,
): RestartStep[] | null {
  if (platform === "darwin") return [{ cmd: "launchctl", args: ["kickstart", "-k", `gui/${uid}/${LAUNCHD_LABEL}`] }];
  if (platform === "linux") return [{ cmd: "systemctl", args: ["--user", "restart", SYSTEMD_UNIT] }];
  if (platform === "win32") return [
    { cmd: "schtasks", args: ["/End", "/TN", WINDOWS_TASK_NAME], ignoreFailure: true },
    { cmd: "schtasks", args: ["/Run", "/TN", WINDOWS_TASK_NAME] },
  ];
  return null;
}

/** Side-effecting standalone-CLI command for supervisor process restart. */
export function restartSupervisor(): void {
  const uid = process.getuid?.() ?? 0;
  const steps = restartSupervisorCommand(process.platform, uid);
  if (!steps) {
    console.error(
      `[remote-pi] restart-supervisor is not supported on '${process.platform}' yet. ` +
      "Restart pi-supervisord manually.",
    );
    process.exit(1);
  }
  for (const step of steps) {
    const r = spawnSync(step.cmd, step.args, { stdio: ["ignore", "pipe", "pipe"], encoding: "utf8" });
    if (r.error) {
      if (step.ignoreFailure) continue;
      console.error(`[remote-pi] restart-supervisor failed: ${step.cmd} not runnable (${r.error.message}). Is the service installed? Run \`remote-pi install\`.`);
      process.exit(1);
    }
    if (r.status !== 0 && !step.ignoreFailure) {
      const detail = (r.stderr || r.stdout || "").trim();
      console.error(`[remote-pi] restart-supervisor failed (${step.cmd} exited ${r.status})${detail ? `: ${detail}` : ""}.`);
      process.exit(r.status === null ? 1 : r.status);
    }
  }
  console.log("[remote-pi] Supervisor restarted.");
}
