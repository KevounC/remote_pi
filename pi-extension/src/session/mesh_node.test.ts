import { describe, expect, test, vi, beforeEach } from "vitest";

type Handler = (...args: unknown[]) => void;

class FakeBroker {
  public remoteRouter: unknown = null;

  constructor(readonly name: string, readonly cwd: string) {}

  setRemoteRouter(router: unknown): void {
    this.remoteRouter = router;
  }

  remoteListenerCount(): number {
    return this.remoteRouter === null ? 0 : 1;
  }
}

class FakeSessionPeer {
  private onReconnectCb: null | (() => void) = null;
  private readonly broker: FakeBroker;

  constructor(
    public readonly opts: {
      sockPath: string;
      name: string;
      cwd?: string;
      auditPath?: string;
      defaultTimeoutMs?: number;
    },
  ) {
    this.broker = new FakeBroker(opts.name, opts.cwd ?? "");
  }

  async start(): Promise<string> {
    return this.opts.name;
  }

  onReconnect(cb: () => void): () => void {
    this.onReconnectCb = cb;
    return () => {
      this.onReconnectCb = null;
    };
  }

  currentRole(): "leader" | "follower" {
    return "leader";
  }

  localBroker(): FakeBroker {
    return this.broker;
  }

  name(): string {
    return this.opts.name;
  }

  address(): string {
    return this.opts.name;
  }

  async leave(): Promise<void> {
    return;
  }

  // Unused passthroughs included to satisfy mesh-node call sites if they appear.
  send(): Promise<void> { return Promise.resolve(); }
  sendWithAck(): Promise<unknown> { return Promise.resolve(undefined); }
  request(): Promise<unknown> { return Promise.resolve({ body: null } as never); }
  onMessage(): () => void { return () => {}; }
  on(_event: string, _handler: () => void): void { }
}

class FakeRelayClient {
  public static readonly instances: FakeRelayClient[] = [];
  private readonly listeners = new Map<string, Set<Handler>>();

  constructor(readonly url: string, readonly keypair: unknown) {
    FakeRelayClient.instances.push(this);
  }

  connect = vi.fn(async () => {});
  close = vi.fn(() => {
    this.emit("close");
  });
  send = vi.fn((_line: string) => {});
  on = vi.fn((event: string, handler: Handler): this => {
    const set = this.listeners.get(event) ?? new Set<Handler>();
    set.add(handler);
    this.listeners.set(event, set);
    return this;
  });
  off = vi.fn((event: string, handler: Handler): this => {
    this.listeners.get(event)?.delete(handler);
    return this;
  });

  emit(event: string, ...args: unknown[]): void {
    for (const handler of this.listeners.get(event) ?? []) handler(...args);
  }

  listenerCount(event: string): number {
    return this.listeners.get(event)?.size ?? 0;
  }
}

const attachCrossPcBridgeMock = vi.fn(
  async (opts: { broker: FakeBroker; relay: FakeRelayClient }) => makeTrackedBridge(opts.relay, opts.broker),
);

const keypair = {
  publicKey: new Uint8Array([1, 2, 3]),
  secretKey: new Uint8Array([4, 5, 6]),
};

function deferred<T = void>(): { promise: Promise<T>; resolve: (value: T) => void; reject: (reason?: unknown) => void } {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function makeTrackedBridge(relay: FakeRelayClient, broker: FakeBroker) {
  const relayListener: Handler = () => {};
  relay.on("message", relayListener);
  const piForward = {
    detach: vi.fn(() => {
      relay.off("message", relayListener);
    }),
  };
  const brokerRemote = {
    detach: vi.fn(() => {
      broker.setRemoteRouter(null);
    }),
    setSiblings: vi.fn(),
    onLocalPeersChanged: vi.fn(),
  };
  broker.setRemoteRouter(brokerRemote);
  return { brokerRemote, piForward };
}

vi.mock("./peer.js", () => ({
  SessionPeer: FakeSessionPeer,
}));

vi.mock("../transport/pi_forward_client.js", () => ({
  PiForwardClient: class {
    detach = vi.fn();
  },
}));

vi.mock("../transport/relay_client.js", () => ({
  RelayClient: FakeRelayClient,
}));

vi.mock("./bridge.js", () => ({
  attachCrossPcBridge: attachCrossPcBridgeMock,
}));

vi.mock("../pairing/storage.js", () => ({
  getOrCreateEd25519Keypair: async () => keypair,
}));

vi.mock("../rooms.js", () => ({
  roomIdFor: (cwd: string, roomName: string) => `${cwd}::${roomName}`,
}));

vi.mock("../config.js", () => ({
  toWebSocketUrl: (url: string) => url,
}));

const { MeshNode } = await import("./mesh_node.js");

beforeEach(() => {
  FakeRelayClient.instances.length = 0;
  attachCrossPcBridgeMock.mockReset();
  attachCrossPcBridgeMock.mockImplementation(
    async (opts: { broker: FakeBroker; relay: FakeRelayClient }) => makeTrackedBridge(opts.relay, opts.broker),
  );
});

describe("MeshNode relay reconnect policy", () => {
  const makeMeshNode = (): InstanceType<typeof MeshNode> =>
    new MeshNode({
      sockPath: "/tmp/relay-mesh.sock",
      name: "mesh-node",
      bridge: {
        relayUrl: "wss://example.invalid/relay",
        cwd: "/tmp/project",
      },
    });

  test("relay reconnect delays use the shared 1,2,5,10,30-second ladder with cap", () => {
    const meshNode = makeMeshNode();
    const mesh = meshNode as any;
    const setTimeoutSpy = vi.spyOn(globalThis, "setTimeout");
    const delays: number[] = [];

    for (let attempt = 0; attempt < 6; attempt++) {
      mesh.relayBackoffIdx = attempt;
      if (mesh.relayReconnectTimer) {
        clearTimeout(mesh.relayReconnectTimer);
        mesh.relayReconnectTimer = null;
      }

      mesh._scheduleRelayReconnect();
      const lastCall = setTimeoutSpy.mock.calls.at(-1);
      expect(lastCall).toBeDefined();
      expect(lastCall?.[1]).toBeTypeOf("number");
      delays.push(lastCall?.[1] as number);

      if (mesh.relayReconnectTimer) {
        clearTimeout(mesh.relayReconnectTimer);
        mesh.relayReconnectTimer = null;
      }
      setTimeoutSpy.mockClear();
    }

    expect(delays).toEqual([1_000, 2_000, 5_000, 10_000, 30_000, 30_000]);
    setTimeoutSpy.mockRestore();
  });

  test("successful reconnect attempt resets relay backoff index", async () => {
    const meshNode = makeMeshNode();
    const mesh = meshNode as any;
    mesh.relayBackoffIdx = 7;

    await mesh._maybeBridge();

    expect(mesh.relayBackoffIdx).toBe(0);
    expect(FakeRelayClient.instances.length).toBeGreaterThanOrEqual(1);
  });

  test("detachBridge invalidates an in-flight injected bridge and detaches stale listeners", async () => {
    const meshNode = new MeshNode({ sockPath: "/tmp/injected-mesh.sock", name: "mesh-node" });
    const broker = meshNode.localBroker() as unknown as FakeBroker;
    const relay = new FakeRelayClient("wss://example.invalid/relay", keypair);
    const gate = deferred<void>();
    let bridge: ReturnType<typeof makeTrackedBridge> | null = null;
    attachCrossPcBridgeMock.mockImplementationOnce(async (opts: { broker: FakeBroker; relay: FakeRelayClient }) => {
      await gate.promise;
      bridge = makeTrackedBridge(opts.relay, opts.broker);
      return bridge;
    });

    const attachPromise = meshNode.attachBridge({
      relay: relay as never,
      relayUrl: "https://example.invalid/relay",
      keypair,
    });

    expect(attachCrossPcBridgeMock).toHaveBeenCalledTimes(1);
    meshNode.detachBridge();
    expect(relay.close).not.toHaveBeenCalled();

    gate.resolve(undefined);
    await attachPromise;

    expect(meshNode.hasBridge()).toBe(false);
    expect(bridge?.brokerRemote.detach).toHaveBeenCalledTimes(1);
    expect(bridge?.piForward.detach).toHaveBeenCalledTimes(1);
    expect(relay.listenerCount("message")).toBe(0);
    expect(broker.remoteListenerCount()).toBe(0);
    expect(relay.close).not.toHaveBeenCalled();
  });

  test("close invalidates an in-flight injected bridge without closing the injected relay", async () => {
    const meshNode = new MeshNode({ sockPath: "/tmp/closing-mesh.sock", name: "mesh-node" });
    const broker = meshNode.localBroker() as unknown as FakeBroker;
    const relay = new FakeRelayClient("wss://example.invalid/relay", keypair);
    const gate = deferred<void>();
    let bridge: ReturnType<typeof makeTrackedBridge> | null = null;
    attachCrossPcBridgeMock.mockImplementationOnce(async (opts: { broker: FakeBroker; relay: FakeRelayClient }) => {
      await gate.promise;
      bridge = makeTrackedBridge(opts.relay, opts.broker);
      return bridge;
    });

    const attachPromise = meshNode.attachBridge({
      relay: relay as never,
      relayUrl: "https://example.invalid/relay",
      keypair,
    });

    expect(attachCrossPcBridgeMock).toHaveBeenCalledTimes(1);
    await meshNode.close();
    expect(relay.close).not.toHaveBeenCalled();

    gate.resolve(undefined);
    await attachPromise;

    expect(meshNode.hasBridge()).toBe(false);
    expect(bridge?.brokerRemote.detach).toHaveBeenCalledTimes(1);
    expect(bridge?.piForward.detach).toHaveBeenCalledTimes(1);
    expect(relay.listenerCount("message")).toBe(0);
    expect(broker.remoteListenerCount()).toBe(0);
    expect(relay.close).not.toHaveBeenCalled();
  });
});
