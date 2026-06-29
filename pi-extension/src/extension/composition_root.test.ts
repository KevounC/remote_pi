import { describe, expect, test, vi } from "vitest";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { RemotePiRuntimePorts } from "./ports.js";
import { createRemotePiExtensionRuntime } from "./composition_root.js";

function ports(): RemotePiRuntimePorts {
  return {
    relay: {
      status: () => "disconnected",
      start: vi.fn(),
      stop: vi.fn(),
      sendRoomMeta: vi.fn(),
      onOuterMessage: vi.fn(() => vi.fn()),
      attachCrossPcBridge: vi.fn(),
      detachCrossPcBridge: vi.fn(),
    },
    owners: {
      activeCount: () => 0,
      attach: vi.fn(),
      detach: vi.fn(),
      broadcast: vi.fn(),
      routeFrom: vi.fn(),
      lateAttachTargets: () => [],
    },
    session: {
      bindApi: vi.fn(),
      bindCommandContext: vi.fn(),
      bindSessionContext: vi.fn(),
      clearStaleContexts: vi.fn(),
      sendPiMessage: vi.fn(() => false),
      wakeAgent: vi.fn(async () => ({ ok: false, detail: "not bound" })),
      publishWorking: vi.fn(),
      handleClientMessage: vi.fn(),
    },
    commands: {
      register: vi.fn(),
    },
  };
}

describe("composition root runtime", () => {
  test("register binds the Pi API before command registration", () => {
    const p = ports();
    const pi = {} as ExtensionAPI;
    const runtime = createRemotePiExtensionRuntime(pi, p);

    runtime.register();

    expect(p.session.bindApi).toHaveBeenCalledWith(pi);
    expect(p.commands.register).toHaveBeenCalledWith(pi, runtime);
    const bindOrder = vi.mocked(p.session.bindApi).mock.invocationCallOrder[0]!;
    const registerOrder = vi.mocked(p.commands.register).mock.invocationCallOrder[0]!;
    expect(bindOrder).toBeLessThan(registerOrder);
  });

  test("dispose marks epoch before clearing resources", async () => {
    const p = ports();
    const runtime = createRemotePiExtensionRuntime({} as ExtensionAPI, p);

    expect(runtime.epoch.isCurrent()).toBe(true);
    await runtime.dispose();

    expect(runtime.epoch.disposed).toBe(true);
    expect(runtime.epoch.isCurrent()).toBe(false);
    expect(p.session.clearStaleContexts).toHaveBeenCalledOnce();
    expect(p.relay.detachCrossPcBridge).toHaveBeenCalledOnce();
    expect(p.relay.stop).toHaveBeenCalledOnce();
  });
});
