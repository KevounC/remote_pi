import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isValidRelayUrl, isWebSocketScheme, saveConfig } from "../../config.js";
import type { PairingCoordinator } from "./pairing_coordinator.js";

/** Thin command adapter for relay-facing command handlers. */
export class RelayCommands {
  constructor(private readonly coordinator: PairingCoordinator) {}

  start(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    return this.coordinator.startRelay(ctx);
  }

  setRelay(arg: string, ctx: Pick<ExtensionContext, "ui">): void {
    const raw = arg.trim();
    if (!raw) {
      ctx.ui.notify(
        "[remote-pi] Usage: /remote-pi set-relay <http:// or https:// url>",
        "warning",
      );
      return;
    }
    if (isWebSocketScheme(raw)) {
      ctx.ui.notify(
        "[remote-pi] Use http:// or https://. The extension converts to WebSocket automatically.",
        "error",
      );
      return;
    }
    if (!isValidRelayUrl(raw)) {
      ctx.ui.notify(
        `[remote-pi] Invalid URL: ${raw}. Must start with http:// or https://`,
        "error",
      );
      return;
    }
    saveConfig({ relay: raw });
    ctx.ui.notify(
      `[remote-pi] Relay set to ${raw}. Run /remote-pi start (or restart) to apply.`,
      "info",
    );
  }
}
