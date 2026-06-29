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
export function createCommandSurface(deps: CommandSurfaceDeps): CommandSurfacePort {
  return {
    register(pi: ExtensionAPI, _runtime: RemotePiRuntime): void {
      deps.deployAgentNetworkSkill();
      deps.refreshPairingsCache();
      deps.registerAgentTools(pi);
      deps.registerCommands(pi);
      if (process.env["REMOTE_PI_DAEMON"] === "1") deps.startDaemonMode();
    },
  };
}
