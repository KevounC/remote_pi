import type { ExtensionAPI, ExtensionContext, ExtensionFactory } from "@earendil-works/pi-coding-agent";
import type { RemotePiRuntimePorts, RuntimeEpoch } from "./ports.js";

let nextEpochId = 1;

export interface RemotePiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: RemotePiRuntimePorts;
  register(): void;
  dispose(): Promise<void>;
}

export function createRuntimeEpoch(): RuntimeEpoch {
  let disposed = false;
  const id = nextEpochId++;
  return {
    id,
    get disposed() {
      return disposed;
    },
    isCurrent() {
      return !disposed;
    },
    dispose() {
      disposed = true;
    },
  };
}

export function createRemotePiExtensionRuntime(
  pi: ExtensionAPI,
  ports: RemotePiRuntimePorts,
): RemotePiRuntime {
  const epoch = createRuntimeEpoch();
  const runtime: RemotePiRuntime = {
    epoch,
    ports,
    register() {
      ports.session.bindApi(pi);
      registerLifecycleHooks(pi, ports, epoch);
      ports.commands.register(pi, runtime);
    },
    async dispose() {
      await disposeRuntimePorts(ports, epoch);
    },
  };
  return runtime;
}

export function registerLifecycleHooks(
  pi: ExtensionAPI,
  ports: RemotePiRuntimePorts,
  epoch: RuntimeEpoch,
): void {
  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    ports.session.bindSessionContext(ctx);
    if (!epoch.isCurrent()) return;
    void ports.commands.ensureStarted?.(ctx);
  });

  pi.on("session_shutdown", async () => {
    await disposeRuntimePorts(ports, epoch);
  });
}

async function disposeRuntimePorts(
  ports: RemotePiRuntimePorts,
  epoch: RuntimeEpoch,
): Promise<void> {
  epoch.dispose();
  ports.commands.prepareSessionShutdown?.();
  ports.session.clearStaleContexts();
  ports.relay.detachCrossPcBridge();
  ports.relay.stop();
  await ports.commands.closeMesh?.();
}

export function createRemotePiExtensionFactory(
  createPorts: () => RemotePiRuntimePorts,
): ExtensionFactory {
  return (pi: ExtensionAPI) => {
    const runtime = createRemotePiExtensionRuntime(pi, createPorts());
    runtime.register();
  };
}
