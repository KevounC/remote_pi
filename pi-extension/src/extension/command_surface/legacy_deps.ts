import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { CommandSurfaceDeps } from "../command_surface.js";

/**
 * Legacy command-surface seam for the incremental index split.
 *
 * The concrete factories still live in `index.ts` during step 1; this type
 * gives later command-surface extraction steps a stable import target without
 * pulling god-file globals into the pure command module.
 */
export type LegacyCommandSurfaceDeps = CommandSurfaceDeps & {
  readonly registerCommands: (pi: ExtensionAPI) => void;
};
