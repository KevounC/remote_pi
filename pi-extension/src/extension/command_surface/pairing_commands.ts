import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { pairingShortidCompletions, type PairingCoordinator } from "./pairing_coordinator.js";

/** Thin command adapter for mobile pairing/device commands. */
export class PairingCommands {
  constructor(private readonly coordinator: PairingCoordinator) {}

  pair(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> {
    return this.coordinator.showPairQr(ctx, args);
  }

  devices(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
    return this.coordinator.listDevices(ctx);
  }

  revoke(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
    return this.coordinator.revokeDevice(arg, ctx);
  }

  completeShortid(prefix: string, valuePrefix = ""): Promise<Array<{ value: string; label: string }>> {
    return pairingShortidCompletions(prefix, valuePrefix);
  }
}
