import { installService, linkCliBinaries, uninstallService, unlinkCliBinaries } from "../../daemon/install.js";
import type { UiCtx } from "./daemon_commands.js";

/** Thin command-surface adapter for supervisor service install/uninstall. */
export class ServiceCommands {
  /** Returns true on success, false when install failed. */
  install(ctx: UiCtx, opts: { linkCli?: boolean } = {}): boolean {
    const linkCli = opts.linkCli ?? false;
    try {
      const result = installService();
      const sections = [
        `[remote-pi] Supervisor service installed (${result.platform}).`,
        `  Unit: ${result.unitPath}`,
        `  Steps:\n${result.log.map((l) => "    " + l).join("\n")}`,
      ];
      if (linkCli) {
        const link = linkCliBinaries();
        sections.push(
          `  CLI bins linked into ${link.binDir}:`,
          link.links.map((l) => `    ${l.name} → ${l.target}`).join("\n"),
          `  Steps:\n${link.log.map((l) => "    " + l).join("\n")}`,
        );
        if (!link.onPath) {
          if (process.platform === "win32") {
            sections.push(
              `  ⚠ ${link.binDir} was just added to your user PATH (it wasn't there yet).`,
              `    Open a NEW terminal and run \`remote-pi daemons\` to verify.`,
            );
          } else {
            sections.push(
              `  ⚠ ${link.binDir} is not on $PATH yet. Add this line to ~/.zshrc / ~/.bashrc:`,
              `      export PATH="$HOME/.local/bin:$PATH"`,
              `    Then open a new terminal and run \`remote-pi daemons\` to verify.`,
            );
          }
        }
      }
      ctx.ui.notify(sections.join("\n"), "info");
      return true;
    } catch (err) {
      ctx.ui.notify(`[remote-pi] install failed: ${String(err)}`, "error");
      return false;
    }
  }

  uninstall(ctx: UiCtx, opts: { linkCli?: boolean } = {}): void {
    const linkCli = opts.linkCli ?? false;
    try {
      const result = uninstallService();
      const sections = [
        `[remote-pi] Supervisor service uninstalled (${result.platform}).`,
        `  Unit: ${result.unitPath} (${result.removed ? "removed" : "not present"})`,
        `  Steps:\n${result.log.map((l) => "    " + l).join("\n")}`,
        `  Note: daemons registry (~/.pi/remote/daemons.json) kept — re-install restores everything.`,
      ];
      if (linkCli) {
        const unlink = unlinkCliBinaries();
        sections.push(
          `  CLI bins cleanup (${unlink.binDir}):`,
          unlink.removed
            .map((r) => `    ${r.name} (${r.existed ? "removed" : "not present"})`)
            .join("\n"),
        );
      }
      ctx.ui.notify(sections.join("\n"), "info");
    } catch (err) {
      ctx.ui.notify(`[remote-pi] uninstall failed: ${String(err)}`, "error");
    }
  }
}
