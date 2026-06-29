import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Tests import the module after stubbing `os.homedir` so the fallback
// path writes inside a temp dir instead of the dev's real ~/.pi/remote.
// vi.mock must run before the real module load.
const _tmpHome = mkdtempSync(join(tmpdir(), "pi-storage-"));
const PEERS_DIR_FOR_TEST = join(_tmpHome, ".pi", "remote");
const PEERS_FILE_FOR_TEST = join(PEERS_DIR_FOR_TEST, "peers.json");
vi.mock("node:os", async (importOriginal) => {
  const orig = await importOriginal<typeof import("node:os")>();
  return { ...orig, homedir: () => _tmpHome };
});

// Re-import after the mock is installed.
const storage = await import("./storage.js");
const {
  getOrCreateEd25519Keypair,
  KeyringUnavailableError,
  _setKeyStoreBackendForTest,
  _setKeyringExpectedForTest,
  _setKeyringRetryForTest,
  _unlinkIdentityFileForTest,
  _IDENTITY_FILE_FOR_TEST,
  addPeer,
  listPeers,
} = storage;
import type { KeyStoreBackend } from "./storage.js";

// ── In-memory backend for migration / round-trip tests ──────────────────────

class InMemoryBackend implements KeyStoreBackend {
  readonly store = new Map<string, string>();
  readonly reads: { service: string; account: string }[] = [];
  readonly writes: { service: string; account: string; value: string }[] = [];
  readonly deletes: { service: string; account: string }[] = [];
  private _failOn?: "read" | "write" | "delete";
  private _failAllOn?: "read" | "write" | "delete";

  failNext(op: "read" | "write" | "delete" | undefined) {
    this._failOn = op;
  }

  /** Persistent failure — every op of this kind throws (simulates a keyring
   *  that's locked/unavailable for the whole call, surviving retries). */
  failAll(op: "read" | "write" | "delete" | undefined) {
    this._failAllOn = op;
  }

  async read(service: string, account: string) {
    this.reads.push({ service, account });
    if (this._failAllOn === "read") throw new Error("simulated keyring locked");
    if (this._failOn === "read") {
      this._failOn = undefined;
      throw new Error("simulated keyring unavailable");
    }
    return this.store.get(`${service}|${account}`);
  }
  async write(service: string, account: string, value: string) {
    this.writes.push({ service, account, value });
    if (this._failOn === "write") {
      this._failOn = undefined;
      throw new Error("simulated keyring write failure");
    }
    this.store.set(`${service}|${account}`, value);
  }
  async delete(service: string, account: string) {
    this.deletes.push({ service, account });
    const key = `${service}|${account}`;
    const had = this.store.has(key);
    this.store.delete(key);
    return had;
  }
}

const NEW_SERVICE = "dev.remotepi.pi";
const OLD_SERVICE = "dev.remotepi.mac";
const ACCOUNT = "longterm-ed25519";
const POSIX_MODES_SUPPORTED = process.platform !== "win32";

function expectPrivateFileMode(path: string): void {
  if (!POSIX_MODES_SUPPORTED) return;
  expect(statSync(path).mode & 0o777).toBe(0o600);
}

function expectPrivateDirMode(path: string): void {
  if (!POSIX_MODES_SUPPORTED) return;
  expect(statSync(path).mode & 0o777).toBe(0o700);
}

const PHONE_PEER = {
  name: "phone",
  remote_epk: Buffer.from(new Uint8Array(32).fill(11)).toString("base64"),
  paired_at: "2026-06-28T00:00:00.000Z",
};

const TABLET_PEER = {
  name: "tablet",
  remote_epk: Buffer.from(new Uint8Array(32).fill(12)).toString("base64"),
  paired_at: "2026-06-28T00:01:00.000Z",
};

beforeEach(async () => {
  // Silence the migration / fallback console output during tests so the
  // vitest output isn't polluted.
  vi.spyOn(console, "info").mockImplementation(() => undefined);
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
  vi.spyOn(console, "error").mockImplementation(() => undefined);
  // Zero retry delay so persistent-failure tests don't sleep.
  _setKeyringRetryForTest(3, 0);
  await _unlinkIdentityFileForTest();
  rmSync(PEERS_FILE_FOR_TEST, { force: true });
});

afterEach(() => {
  _setKeyStoreBackendForTest(null);
  _setKeyringExpectedForTest(null);
  _setKeyringRetryForTest(null);
  delete process.env.REMOTE_PI_ALLOW_FILE_IDENTITY;
  vi.restoreAllMocks();
});

// ── Keyring path ────────────────────────────────────────────────────────────

describe("getOrCreateEd25519Keypair — keyring path", () => {
  test("returns existing entry from new service without writing", async () => {
    const backend = new InMemoryBackend();
    const original = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(1)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(2)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, original);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(1)).toString("base64"),
    );
    expect(backend.writes.length).toBe(0);
    expect(backend.deletes.length).toBe(0);
  });

  test("generates + saves a fresh keypair when neither service has an entry", async () => {
    const backend = new InMemoryBackend();
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey).toBeInstanceOf(Uint8Array);
    expect(kp.publicKey.length).toBe(32);
    expect(backend.writes.length).toBe(1);
    expect(backend.writes[0]!.service).toBe(NEW_SERVICE);
    expect(backend.writes[0]!.account).toBe(ACCOUNT);
    expect(backend.deletes.length).toBe(0);
  });

  test("idempotent across two calls — second call returns same key without write", async () => {
    const backend = new InMemoryBackend();
    _setKeyStoreBackendForTest(backend);

    const first = await getOrCreateEd25519Keypair();
    const second = await getOrCreateEd25519Keypair();

    expect(Buffer.from(first.publicKey).toString("base64")).toBe(
      Buffer.from(second.publicKey).toString("base64"),
    );
    expect(backend.writes.length).toBe(1);  // only the first call wrote
  });
});

// ── Migration path (legacy keytar service) ──────────────────────────────────

describe("getOrCreateEd25519Keypair — keytar migration (plan/27 E1)", () => {
  test("legacy entry → copies to new service + deletes old", async () => {
    const backend = new InMemoryBackend();
    const legacy = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(7)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(8)).toString("base64"),
    });
    backend.store.set(`${OLD_SERVICE}|${ACCOUNT}`, legacy);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();

    // Preserved identity
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(7)).toString("base64"),
    );
    // New entry was written
    expect(backend.store.get(`${NEW_SERVICE}|${ACCOUNT}`)).toBe(legacy);
    // Old entry was deleted
    expect(backend.store.has(`${OLD_SERVICE}|${ACCOUNT}`)).toBe(false);
    expect(backend.deletes.find((d) => d.service === OLD_SERVICE)).toBeDefined();
  });

  test("new entry already present → does NOT touch legacy entry", async () => {
    const backend = new InMemoryBackend();
    const newVal = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(3)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(4)).toString("base64"),
    });
    const stale = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(9)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(9)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, newVal);
    backend.store.set(`${OLD_SERVICE}|${ACCOUNT}`, stale);
    _setKeyStoreBackendForTest(backend);

    const kp = await getOrCreateEd25519Keypair();
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(3)).toString("base64"),
    );
    // Legacy entry untouched (we never even read it)
    expect(backend.store.get(`${OLD_SERVICE}|${ACCOUNT}`)).toBe(stale);
    expect(backend.deletes.length).toBe(0);
  });
});

// ── Headless fallback ───────────────────────────────────────────────────────

describe("getOrCreateEd25519Keypair — headless Linux fallback", () => {
  test("keyring read throws persistently (no keyring expected) → falls back to identity.json (chmod 0o600)", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(false);  // simulate headless Linux (no core keyring)

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey.length).toBe(32);

    // File exists at the expected path with restrictive perms.
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
    // POSIX-only: `chmod 0o600` is a no-op on Windows (NTFS perms aren't the
    // POSIX bits + Node reports a fixed mode), so only assert the perm bits
    // off Windows. The file-creation + fallback behavior is checked above.
    if (process.platform !== "win32") {
      const stat = statSync(_IDENTITY_FILE_FOR_TEST);
      const perms = stat.mode & 0o777;
      expect(perms & 0o077).toBe(0);  // group + other bits zero
    }

    // Round-trip: parse and check it deserializes to the same key.
    const parsed = JSON.parse(readFileSync(_IDENTITY_FILE_FOR_TEST, "utf8")) as { pk: string; sk: string };
    expect(Buffer.from(parsed.pk, "base64").length).toBe(32);
  });

  test("fallback second call returns the file-stored key (no regen)", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(false);
    const first = await getOrCreateEd25519Keypair();

    // Reset the backend so it would throw again on a fresh read.
    const backend2 = new InMemoryBackend();
    backend2.failAll("read");
    _setKeyStoreBackendForTest(backend2);
    const second = await getOrCreateEd25519Keypair();

    expect(Buffer.from(first.publicKey).toString("base64")).toBe(
      Buffer.from(second.publicKey).toString("base64"),
    );
  });

});

// ── peers.json permissions ──────────────────────────────────────────────────

describe("peers.json storage permissions", () => {
  test("addPeer writes peers.json with private file and parent directory permissions", async () => {
    await addPeer(PHONE_PEER);

    expect(existsSync(PEERS_FILE_FOR_TEST)).toBe(true);
    const parsed = JSON.parse(readFileSync(PEERS_FILE_FOR_TEST, "utf8")) as { peers: unknown[] };
    expect(parsed.peers).toEqual([PHONE_PEER]);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
    expectPrivateDirMode(PEERS_DIR_FOR_TEST);
  });

  test("listPeers hardens an existing permissive peers.json on read", async () => {
    mkdirSync(PEERS_DIR_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(PEERS_FILE_FOR_TEST, JSON.stringify({ peers: [PHONE_PEER] }, null, 2), { mode: 0o644 });
    if (POSIX_MODES_SUPPORTED) chmodSync(PEERS_FILE_FOR_TEST, 0o644);

    const peers = await listPeers();

    expect(peers).toEqual([PHONE_PEER]);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
  });

  test("addPeer migrates an existing permissive peers.json on update", async () => {
    mkdirSync(PEERS_DIR_FOR_TEST, { recursive: true, mode: 0o700 });
    writeFileSync(PEERS_FILE_FOR_TEST, JSON.stringify({ peers: [PHONE_PEER] }, null, 2), { mode: 0o644 });
    if (POSIX_MODES_SUPPORTED) chmodSync(PEERS_FILE_FOR_TEST, 0o644);

    await addPeer(TABLET_PEER);

    const parsed = JSON.parse(readFileSync(PEERS_FILE_FOR_TEST, "utf8")) as { peers: unknown[] };
    expect(parsed.peers).toEqual([PHONE_PEER, TABLET_PEER]);
    expectPrivateFileMode(PEERS_FILE_FOR_TEST);
  });
});

// ── Locked-keychain protection (the "lost pairing after a week idle" bug) ────

describe("getOrCreateEd25519Keypair — locked keyring does NOT regenerate", () => {
  test("transient read failure recovers via retry → uses keyring entry, no file written", async () => {
    const backend = new InMemoryBackend();
    const original = JSON.stringify({
      pk: Buffer.from(new Uint8Array(32).fill(5)).toString("base64"),
      sk: Buffer.from(new Uint8Array(64).fill(6)).toString("base64"),
    });
    backend.store.set(`${NEW_SERVICE}|${ACCOUNT}`, original);
    backend.failNext("read");  // first read throws, retry succeeds
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(true);  // macOS/Windows: keyring is core

    const kp = await getOrCreateEd25519Keypair();
    // Recovered the ORIGINAL paired key — not a freshly minted one.
    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(new Uint8Array(32).fill(5)).toString("base64"),
    );
    expect(backend.reads.length).toBeGreaterThanOrEqual(2);  // retried
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(false);  // no file regen
  });

  test("persistent failure on a core-keyring platform with no file → throws (refuses to regen)", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(true);  // macOS/Windows

    await expect(getOrCreateEd25519Keypair()).rejects.toBeInstanceOf(KeyringUnavailableError);
    // Critically: no new identity file was written (pairing not silently broken).
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(false);
  });

  test("persistent failure but identity.json already exists → returns the FILE key (never throws, never regen)", async () => {
    // First, create a file identity via the headless path.
    const seed = new InMemoryBackend();
    seed.failAll("read");
    _setKeyStoreBackendForTest(seed);
    _setKeyringExpectedForTest(false);
    const fileKp = await getOrCreateEd25519Keypair();

    // Now the keyring is "core" but locked; the existing file must win.
    const locked = new InMemoryBackend();
    locked.failAll("read");
    _setKeyStoreBackendForTest(locked);
    _setKeyringExpectedForTest(true);
    const kp = await getOrCreateEd25519Keypair();

    expect(Buffer.from(kp.publicKey).toString("base64")).toBe(
      Buffer.from(fileKp.publicKey).toString("base64"),
    );
  });

  test("REMOTE_PI_ALLOW_FILE_IDENTITY=1 opts into file identity even on a core-keyring platform", async () => {
    const backend = new InMemoryBackend();
    backend.failAll("read");
    _setKeyStoreBackendForTest(backend);
    _setKeyringExpectedForTest(true);
    process.env.REMOTE_PI_ALLOW_FILE_IDENTITY = "1";

    const kp = await getOrCreateEd25519Keypair();
    expect(kp.publicKey.length).toBe(32);
    expect(existsSync(_IDENTITY_FILE_FOR_TEST)).toBe(true);
  });
});
