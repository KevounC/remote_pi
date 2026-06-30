import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { CommandSurfacePort, RemotePiRuntime } from "./ports.js";

export interface CommandSurfaceDeps {
  readonly registerAgentTools: (pi: ExtensionAPI) => void;
  readonly deployAgentNetworkSkill: () => void;
  readonly refreshPairingsCache: () => void;
  readonly registerCommands: (pi: ExtensionAPI) => void;
  readonly startDaemonMode: () => void;
}

/** Behavior-preserving command/daemon registration shell. */
export class CommandSurface implements CommandSurfacePort {
  constructor(private readonly deps: CommandSurfaceDeps) {}

  register(pi: ExtensionAPI, _runtime: RemotePiRuntime): void {
    this.deps.deployAgentNetworkSkill();
    this.deps.refreshPairingsCache();
    this.deps.registerAgentTools(pi);
    this.deps.registerCommands(pi);
    if (process.env["REMOTE_PI_DAEMON"] === "1") this.deps.startDaemonMode();
  }
}

export function createCommandSurface(deps: CommandSurfaceDeps): CommandSurfacePort {
  return new CommandSurface(deps);
}
