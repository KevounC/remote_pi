import { describe, expect, test, vi } from "vitest";

class FakeSessionPeer {
  private onReconnectCb: null | (() => void) = null;

  constructor(
    public readonly opts: {
      sockPath: string;
      name: string;
      cwd?: string;
      auditPath?: string;
      defaultTimeoutMs?: number;
    },
  ) {}

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

  localBroker(): object {
    return {
      name: this.opts.name,
      cwd: this.opts.cwd ?? "",
    };
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

  constructor(readonly url: string, readonly keypair: unknown) {
    FakeRelayClient.instances.push(this);
  }

  connect = vi.fn(async () => {});
  on = vi.fn((_event: string, _handler: () => void) => { });
  close = vi.fn(() => {});
}

const attachCrossPcBridgeMock = vi.fn(async () => ({
  brokerRemote: {
    detach: vi.fn(),
    setSiblings: vi.fn(),
    onLocalPeersChanged: vi.fn(),
  },
  piForward: {
    detach: vi.fn(),
  },
}));

const keypair = {
  publicKey: new Uint8Array([1, 2, 3]),
  secretKey: new Uint8Array([4, 5, 6]),
};

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
});
