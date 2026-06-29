---
id: idea-agent-send-sandbox-egress-gate
created: 2026-06-29
updated: 2026-06-29
tags: [security, sandbox, pi-extension]
---

# Sandbox egress gate for `agent_send` / mesh tools

## Problem

The SNC `codebox` host runs a pi bubblewrap sandbox (`~/.pi/agent/extensions/sandbox/`) to
harden the agent runtime against prompt-injection credential exfiltration. The sandbox enforces
filesystem `denyRead`/`denyWrite` and a network allowlist at the OS layer for **bash**, and a
hardened `read`/`write`/`edit` tool layer in-process (Tier 1 hardening, 2026-06-29).

But the mesh tools this extension registers — `agent_send`, `agent_request`, `list_peers` — are
**not subprocesses**; bubblewrap does not mediate them. `agent_send({ to, body, re? })` accepts a
**model-controlled free-form `body`** (string or object) and delivers it to a peer agent via the
WebSocket relay (here `http://192.168.50.110:3300`). That is a real network egress channel that
sits entirely outside the sandbox's network allowlist.

Threat: an attacker delivers a prompt injection that obtains a secret via *any* un-sandboxed path
that survives (today: `background`/`monitor` spawn outside bwrap; tomorrow: a future extension
tool), then ships it as the `agent_send` `body` to a peer or `broadcast`. The payload leaves the
host via the relay, bypassing the sandbox network policy. This was finding #9 in the SNC sandbox
adversarial review (`~/SNC/.memory/sandbox-adversarial-review.md`).

`list_peers` is low-risk on its own (broker inventory query). `agent_request` is the deprecated
synchronous variant of the same channel.

## Proposed affordance

Add an egress-gate affordance to the remote-pi pi-extension so the sandbox (or any credential-
protection mode) can restrict mesh sends. Two non-exclusive options:

1. **Config flag, checked at the send site.** Something like a `meshEgressPolicy` in the extension
   config: `"open" | "block"` (default `"open"` to preserve current behavior), or an
   allowlist of recipient addresses. When `"block"`, `agent_send`/`agent_request` refuse with a
   clear error and do not open the relay channel; `list_peers` can stay available (read-only).
   The sandbox extension's `session_start` would set this when sandboxing is enabled.

2. **Secret/body scanner on send.** A redaction layer that scans the outgoing `body` for known
   secret patterns (token prefixes, key shapes) and redacts or refuses before transmission. Weaker
   than a hard block (regex-based), but useful when mesh egress must stay on.

A third option — a `tool_call` event handler in the sandbox extension that returns
`{ block: true, reason }` for `agent_send` — works WITHOUT changes here, but it's a less clean
home for the policy and doesn't compose with relay-level controls. Prefer landing the affordance
in this fork.

## Timing

Filed now because the SNC sandbox hardening effort surfaced it, but **do not implement during the
current remote-pi refactor** — this fork is mid-refactor (stewardship/private-carry/patchbay
direction per `ab87e28`); landing a send-site gate now would create merge churn. Pick up after the
refactor settles. Track here so it's not lost.

## Related

- SNC sandbox review: `~/SNC/.memory/sandbox-adversarial-review.md` (finding #9, section C3)
- SNC session note:
`~/SNC/.memory/sessions/2026-06-29-auth-exposure-audit-and-sandbox-install.md`
- Sibling gaps still open in SNC: `background`/`monitor` (parked in the nklisch/skills repo —
  `idea-background-tasks-sandbox-integration`), `umans_web_search`/`umans_vision` (umans provider
  ext, candidate `tool_call` block).
- `subagent` was tested empirically and is NOT a bypass — the hardened tools propagate to child
  sessions.
