import { describe, expect, test, vi } from "vitest";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { registerRemotePiCommands, type RemotePiCommandSpec } from "./commands.js";

function fakePi() {
  const commands = new Map<string, { getArgumentCompletions?: (prefix: string) => Promise<Array<{ value: string; label: string }>>; handler: (args: string, ctx: ExtensionCommandContext) => Promise<void> }>();
  const pi = {
    registerCommand(name: string, spec: { getArgumentCompletions?: (prefix: string) => Promise<Array<{ value: string; label: string }>>; handler: (args: string, ctx: ExtensionCommandContext) => Promise<void> }) {
      commands.set(name, spec);
    },
  } as unknown as ExtensionAPI;
  return { pi, commands };
}

describe("registerRemotePiCommands", () => {
  test("derives root and nested registrations from one spec table", async () => {
    const { pi, commands } = fakePi();
    const setup = vi.fn();
    const revoke = vi.fn();
    const root = vi.fn();
    const specs: RemotePiCommandSpec[] = [
      { suffix: "setup", description: "Setup", run: setup },
      {
        suffix: "revoke",
        description: "Revoke",
        complete: async (prefix) => [{ value: `${prefix}abc`, label: `${prefix}abc` }],
        run: revoke,
      },
      {
        suffix: "cron",
        completionValues: ["cron", "cron add"],
        description: "Cron",
        run: vi.fn(),
      },
    ];

    registerRemotePiCommands(pi, specs, root);

    expect([...commands.keys()]).toEqual([
      "remote-pi",
      "remote-pi setup",
      "remote-pi revoke",
      "remote-pi cron",
    ]);
    await commands.get("remote-pi setup")!.handler("", {} as ExtensionCommandContext);
    expect(setup).toHaveBeenCalledOnce();
    await commands.get("remote-pi")!.handler("unknown", {} as ExtensionCommandContext);
    expect(root).toHaveBeenCalledWith("unknown", expect.anything());
    await expect(commands.get("remote-pi")!.getArgumentCompletions!("cron ")).resolves.toEqual([
      { value: "cron add", label: "cron add" },
    ]);
    await expect(commands.get("remote-pi")!.getArgumentCompletions!("revoke ")).resolves.toEqual([
      { value: "revoke abc", label: "revoke abc" },
    ]);
  });
});
