import type { ExtensionAPI, ExtensionFactory } from "@earendil-works/pi-coding-agent";
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
      ports.commands.register(pi, runtime);
    },
    async dispose() {
      epoch.dispose();
      ports.session.clearStaleContexts();
      ports.relay.detachCrossPcBridge();
      ports.relay.stop();
    },
  };
  return runtime;
}

export function createRemotePiExtensionFactory(
  createPorts: () => RemotePiRuntimePorts,
): ExtensionFactory {
  return (pi: ExtensionAPI) => {
    const runtime = createRemotePiExtensionRuntime(pi, createPorts());
    runtime.register();
  };
}
