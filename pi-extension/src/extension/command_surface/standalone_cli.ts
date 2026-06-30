import { spawnSync } from "node:child_process";
import { existsSync, realpathSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { RemotePiCommandSurfaceHarness } from "../testing.js";
import {
  isValidRelayUrl,
  isWebSocketScheme,
  kDefaultRelayUrl,
} from "../../config.js";
import {
  defaultAgentName,
  localConfigExists,
  saveLocalConfig,
} from "../../session/local_config.js";
import type { CronCommands } from "./cron_commands.js";
import type { DaemonCommands, UiCtx } from "./daemon_commands.js";
import type { ServiceCommands } from "./service_commands.js";

export interface StandaloneCliDeps {
  readonly devices: () => Promise<void>;
  readonly revoke: (shortid: string) => Promise<void>;
  readonly setRelay: (url: string) => void;
  readonly daemon: DaemonCommands;
  readonly cron: CronCommands;
  readonly service: ServiceCommands;
  readonly probePeers: () => Promise<void>;
  readonly launchClaude: (args: string[]) => Promise<void>;
  readonly restartSupervisor: () => void;
}

interface StoredPeer {
  readonly name: string;
  readonly remote_epk: string;
}

export interface StandaloneCliAdapterDeps {
  readonly commandSurface: RemotePiCommandSurfaceHarness;
  readonly listPeers: () => Promise<StoredPeer[]>;
  readonly removePeer: (remoteEpk: string) => Promise<boolean>;
  readonly saveRelayConfig: (url: string) => void;
  readonly daemon: DaemonCommands;
  readonly cron: CronCommands;
  readonly service: ServiceCommands;
  readonly probeListPeers: () => Promise<string[] | null>;
  readonly formatPeerInventory: (peers: readonly string[]) => string;
  readonly launchClaude: (args: string[]) => Promise<void>;
  readonly restartSupervisor: () => void;
}

export function createStandaloneCliDeps(input: StandaloneCliAdapterDeps): StandaloneCliDeps {
  // The harness is part of the CLI bootstrap contract: index.ts passes the same
  // command-surface test seam used by compatibility exports, so future CLI
  // commands can route through that stable seam without re-opening index.ts.
  void input.commandSurface;
  return {
    devices: async () => {
      const peers = await input.listPeers();
      if (peers.length === 0) { console.log("[remote-pi] No peers"); }
      else { for (const p of peers) console.log(`• ${p.remote_epk.slice(0, 8)} — ${p.name}`); }
    },
    revoke: async (shortid) => {
      const peers = await input.listPeers();
      const matches = peers.filter((p) => p.remote_epk.startsWith(shortid));
      if (matches.length === 0) console.log(`No peer matching '${shortid}'`);
      else if (matches.length > 1) console.log(`Ambiguous: ${matches.map((p) => p.remote_epk.slice(0, 8)).join(", ")}`);
      else {
        const peer = matches[0]!;
        await input.removePeer(peer.remote_epk);
        console.log(`Revoked: ${peer.name} (${peer.remote_epk.slice(0, 8)}…)`);
      }
    },
    setRelay: input.saveRelayConfig,
    daemon: input.daemon,
    cron: input.cron,
    service: input.service,
    probePeers: async () => {
      const peers = await input.probeListPeers();
      if (peers === null) {
        console.log("[remote-pi] Mesh offline — no agent is running on this machine.");
      } else {
        console.log(`[remote-pi] peers:\n${input.formatPeerInventory(peers)}`);
      }
    },
    launchClaude: input.launchClaude,
    restartSupervisor: input.restartSupervisor,
  };
}

export function isDirectRun(importMetaUrl: string, argv1: string | undefined): boolean {
  try {
    if (!argv1) return false;
    return fileURLToPath(importMetaUrl) === realpathSync(argv1);
  } catch {
    return false;
  }
}

export async function runStandaloneRemotePiCli(
  argv: readonly string[],
  deps: StandaloneCliDeps,
): Promise<void> {
  const [, , subcmd, ...cliArgs] = argv;
  if (subcmd === "devices" || subcmd === "list") {
    await deps.devices();
  } else if (subcmd === "revoke") {
    const shortid = (cliArgs[0] ?? "").trim();
    if (!shortid) {
      console.log("Usage: revoke <shortid>");
    } else {
      await deps.revoke(shortid);
    }
  } else if (subcmd === "set-relay") {
    const raw = (cliArgs[0] ?? "").trim();
    if (!raw) {
      console.log(`Usage: set-relay <url> (default: ${kDefaultRelayUrl})`);
    } else if (isWebSocketScheme(raw)) {
      console.log("Use http:// or https://. The extension converts to WebSocket automatically.");
    } else if (!isValidRelayUrl(raw)) {
      console.log(`Invalid URL: ${raw}. Must start with http:// or https://`);
    } else {
      deps.setRelay(raw);
      console.log(`Relay set to ${raw}`);
    }
  } else if (subcmd === "create") {
    const joined = quoteArgsWithSpaces(cliArgs);
    await deps.daemon.create(joined, consoleUiCtx());
  } else if (subcmd === "remove") {
    const id = (cliArgs[0] ?? "").trim();
    await deps.daemon.remove(id, consoleUiCtx());
  } else if (subcmd === "daemons") {
    await deps.daemon.list(consoleUiCtx());
  } else if (subcmd === "daemon") {
    const op = cliArgs[0] ?? "";
    const rest = quoteArgsWithSpaces(cliArgs.slice(1));
    const stubCtx = consoleUiCtx();
    if (op === "start") { await deps.daemon.start(stubCtx, cliArgs[1]); }
    else if (op === "stop") { await deps.daemon.stop(stubCtx, cliArgs[1]); }
    else if (op === "restart") { await deps.daemon.restart(stubCtx, cliArgs[1]); }
    else if (op === "status") { await deps.daemon.status(stubCtx); }
    else if (op === "send") { await deps.daemon.send(rest, stubCtx); }
    else {
      console.log("Usage: remote-pi daemon <start|stop|restart [<id>]|status|send <id> \"<text>\">");
    }
  } else if (subcmd === "cron") {
    const joined = quoteArgsWithSpaces(cliArgs);
    await deps.cron.run(joined, consoleUiCtx());
  } else if (subcmd === "peers") {
    await deps.probePeers();
  } else if (subcmd === "claude") {
    await deps.launchClaude([...cliArgs]);
  } else if (subcmd === "install") {
    if (!deps.service.install(consoleUiCtx(), { linkCli: false })) process.exit(1);
  } else if (subcmd === "uninstall") {
    deps.service.uninstall(consoleUiCtx(), { linkCli: true });
  } else if (subcmd === "restart-supervisor") {
    deps.restartSupervisor();
  } else {
    console.log(remotePiCliHelpText());
  }
}

function quoteArgsWithSpaces(args: readonly string[]): string {
  return args.map((arg) => (/\s/.test(arg) ? `"${arg}"` : arg)).join(" ");
}

function consoleUiCtx(): UiCtx {
  return {
    ui: {
      notify: (msg: string) => { console.log(msg); },
    } as unknown as ExtensionContext["ui"],
  };
}

function remotePiCliHelpText(): string {
  return [
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
  ].join("\n");
}

export async function launchClaudeCli(args: string[], entrypointUrl: string): Promise<void> {
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
  const here = fileURLToPath(entrypointUrl);
  const distRoot = dirname(here);
  const meshServerPath = resolve(distRoot, "mcp/mesh_server.js");

  if (!existsSync(meshServerPath)) {
    console.log(`[remote-pi] mesh server not found at ${meshServerPath}. Run pnpm build first.`);
    process.exit(1);
  }

  const absCwd = resolve(targetCwd);
  const SERVER_NAME = "remote-pi-mesh";

  // The mesh MCP must be visible ONLY inside a `remote-pi claude` session — a
  // plain `claude` in the same repo must NOT inherit it. Remove the legacy
  // local-scope entry left by older builds, then load the server ephemerally
  // through --mcp-config for this launched Claude process only.
  spawnSync("claude", ["mcp", "remove", SERVER_NAME, "-s", "local"], {
    cwd: absCwd, stdio: "ignore", shell: false,
  });

  const mcpConfigPath = join(tmpdir(), `remote-pi-mesh-mcp-${process.pid}.json`);
  writeFileSync(mcpConfigPath, JSON.stringify({
    mcpServers: {
      [SERVER_NAME]: { command: process.execPath, args: [meshServerPath] },
    },
  }));

  const skillPath = agentNetworkSkillPath(entrypointUrl);

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
    try { unlinkSync(mcpConfigPath); } catch { /* already removed */ }
  }
}

/**
 * Resolve the packaged agent-network skill path (`<pkgRoot>/skills/agent-network/SKILL.md`).
 * Uses the package entrypoint URL instead of this module URL so the path remains
 * identical after the dispatcher moves under `dist/extension/command_surface/`.
 */
function agentNetworkSkillPath(entrypointUrl: string): string | null {
  const here = fileURLToPath(entrypointUrl);
  const pkgRoot = dirname(dirname(here));
  const skill = join(pkgRoot, "skills", "agent-network", "SKILL.md");
  return existsSync(skill) ? skill : null;
}
