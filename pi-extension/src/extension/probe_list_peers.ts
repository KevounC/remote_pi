/**
 * Read-only probe of the local UDS broker for the mesh roster, backing
 * `remote-pi peers`. Opens a raw connection to `sockPath`, sends a single
 * unregistered `list_peers` request, and resolves with the peer names from the
 * broker's reply (local UDS peers + cross-PC `<pc>:<peer>` entries).
 *
 * The probe deliberately does NOT register as a peer: the broker answers
 * observer probes without assigning a name or broadcasting peer_joined/left
 * (see Broker._tryObserverProbe), so a shell query never perturbs the mesh —
 * no phantom peer flashes in anyone's roster, local or cross-PC.
 *
 * Resolves null when no broker is reachable (connection refused / no socket
 * file — i.e. no Pi or daemon is leading the mesh on this machine), or on
 * timeout, so the caller can print an "offline" message instead of an empty
 * roster.
 */
export async function probeListPeers(
  sockPath: string,
  timeoutMs = 2000,
): Promise<string[] | null> {
  const { createConnection } = await import("node:net");
  return new Promise<string[] | null>((resolve) => {
    const sock = createConnection({ path: sockPath });
    let buf = "";
    let settled = false;
    const done = (result: string[] | null): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { sock.destroy(); } catch { /* already gone */ }
      resolve(result);
    };
    const timer = setTimeout(() => done(null), timeoutMs);
    sock.setEncoding("utf8");
    sock.on("connect", () => {
      try { sock.write(JSON.stringify({ type: "list_peers" }) + "\n"); }
      catch { done(null); }
    });
    sock.on("data", (chunk: string) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;  // wait for a full line
      const line = buf.slice(0, nl);
      try {
        const env = JSON.parse(line) as { body?: { type?: string; peers?: unknown } };
        const body = env.body;
        if (body && body.type === "list_peers_reply" && Array.isArray(body.peers)) {
          done(body.peers.filter((p): p is string => typeof p === "string"));
          return;
        }
      } catch { /* fall through */ }
      done(null);  // a line arrived but it wasn't the reply we expected
    });
    sock.on("error", () => done(null));  // ECONNREFUSED / ENOENT → mesh offline
    sock.on("close", () => done(null));
  });
}
