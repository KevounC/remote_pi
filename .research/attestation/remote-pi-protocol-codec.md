---
source_handle: remote-pi-protocol-codec
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/pi-extension/src/protocol/codec.ts
provenance: source-direct
---

# Remote Pi protocol codec

Paraphrased summary: `src/protocol/codec.ts` provides `encodeClient` and `decodeServer` helpers plus a `SERVER_TYPES` allowlist, but inspection and review found these helpers are defined and unit-tested rather than used as the primary runtime validation boundary in the extension. The runtime inbound paths should therefore not be described as fully codec-validated unless code changes make that true.

## Key passages

- `SERVER_TYPES` includes a subset of server message types and omits newer variants such as `user_message`, `compaction`, action replies, and `models_list`.
- `decodeServer` parses JSON, checks that a string `type` exists, checks it against `SERVER_TYPES`, and casts to `ServerMessage`.
- `encodeClient` serializes a `ClientMessage` as JSON plus newline.
- The codec file itself does not register with `RelayClient` or the extension runtime; source search in the review found runtime paths use other parsing/dispatch logic.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/forks/remote_pi/pi-extension/src/protocol/codec.ts`
