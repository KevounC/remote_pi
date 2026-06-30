import { describe, expect, test, vi } from "vitest";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
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
      ensureStarted: vi.fn(),
      prepareSessionShutdown: vi.fn(),
      closeMesh: vi.fn(async () => undefined),
    },
  };
}

function piWithHandlers(): {
  pi: ExtensionAPI;
  handlers: Map<string, (...args: unknown[]) => unknown>;
} {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  const pi = {
    on: vi.fn((name: string, handler: (...args: unknown[]) => unknown) => {
      handlers.set(name, handler);
    }),
  } as unknown as ExtensionAPI;
  return { pi, handlers };
}

describe("composition root runtime", () => {
  test("register binds the Pi API and lifecycle hooks before command registration", () => {
    const p = ports();
    const { pi } = piWithHandlers();
    const runtime = createRemotePiExtensionRuntime(pi, p);

    runtime.register();

    expect(p.session.bindApi).toHaveBeenCalledWith(pi);
    expect(pi.on).toHaveBeenCalledWith("session_start", expect.any(Function));
    expect(pi.on).toHaveBeenCalledWith("session_shutdown", expect.any(Function));
    expect(p.commands.register).toHaveBeenCalledWith(pi, runtime);
    const bindOrder = vi.mocked(p.session.bindApi).mock.invocationCallOrder[0]!;
    const hookOrder = vi.mocked(pi.on).mock.invocationCallOrder[0]!;
    const registerOrder = vi.mocked(p.commands.register).mock.invocationCallOrder[0]!;
    expect(bindOrder).toBeLessThan(hookOrder);
    expect(hookOrder).toBeLessThan(registerOrder);
  });

  test("session_start binds fresh context and only restarts while epoch is current", () => {
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createRemotePiExtensionRuntime(pi, p);
    runtime.register();

    const ctx = { ui: {} } as ExtensionContext;
    handlers.get("session_start")?.({ type: "session_start" }, ctx);

    expect(p.session.bindSessionContext).toHaveBeenCalledWith(ctx);
    expect(p.commands.ensureStarted).toHaveBeenCalledWith(ctx);

    runtime.epoch.dispose();
    const staleCtx = { ui: {} } as ExtensionContext;
    handlers.get("session_start")?.({ type: "session_start" }, staleCtx);

    expect(p.session.bindSessionContext).toHaveBeenCalledWith(staleCtx);
    expect(p.commands.ensureStarted).toHaveBeenCalledTimes(1);
  });

  test("session_shutdown marks epoch before clearing resources and closing mesh", async () => {
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createRemotePiExtensionRuntime(pi, p);
    runtime.register();

    expect(runtime.epoch.isCurrent()).toBe(true);
    await handlers.get("session_shutdown")?.({ type: "session_shutdown" });

    expect(runtime.epoch.disposed).toBe(true);
    expect(runtime.epoch.isCurrent()).toBe(false);
    expect(p.commands.prepareSessionShutdown).toHaveBeenCalledOnce();
    expect(p.session.clearStaleContexts).toHaveBeenCalledOnce();
    expect(p.relay.detachCrossPcBridge).toHaveBeenCalledOnce();
    expect(p.relay.stop).toHaveBeenCalledOnce();
    expect(p.commands.closeMesh).toHaveBeenCalledOnce();
    const disposeOrder = vi.mocked(p.commands.prepareSessionShutdown!).mock.invocationCallOrder[0]!;
    const clearOrder = vi.mocked(p.session.clearStaleContexts).mock.invocationCallOrder[0]!;
    const stopOrder = vi.mocked(p.relay.stop).mock.invocationCallOrder[0]!;
    const closeMeshOrder = vi.mocked(p.commands.closeMesh!).mock.invocationCallOrder[0]!;
    expect(disposeOrder).toBeLessThan(clearOrder);
    expect(clearOrder).toBeLessThan(stopOrder);
    expect(stopOrder).toBeLessThan(closeMeshOrder);
  });

  test("dispose uses the same ordered shutdown path", async () => {
    const p = ports();
    const runtime = createRemotePiExtensionRuntime(piWithHandlers().pi, p);

    expect(runtime.epoch.isCurrent()).toBe(true);
    await runtime.dispose();

    expect(runtime.epoch.disposed).toBe(true);
    expect(runtime.epoch.isCurrent()).toBe(false);
    expect(p.commands.prepareSessionShutdown).toHaveBeenCalledOnce();
    expect(p.session.clearStaleContexts).toHaveBeenCalledOnce();
    expect(p.relay.detachCrossPcBridge).toHaveBeenCalledOnce();
    expect(p.relay.stop).toHaveBeenCalledOnce();
    expect(p.commands.closeMesh).toHaveBeenCalledOnce();
  });
});
