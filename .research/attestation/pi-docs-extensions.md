---
source_handle: pi-docs-extensions
fetched: 2026-06-28
source_path: /home/agent/.local/lib/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md
provenance: source-direct
---

# Pi coding agent extension docs — lifecycle hooks

Paraphrased summary: The Pi extension docs define the extension event lifecycle and the session-replacement ordering Remote Pi relies on. `/new` and `/resume` emit `session_before_switch`, then `session_shutdown`, then `session_start` with reason `new` or `resume`, then resource discovery. `/fork` and `/clone` also shut down the old session instance and start a new one with reason `fork`. The docs say cleanup belongs in `session_shutdown` and in-memory state should be reestablished in `session_start`.

## Key passages

- `session_start` is fired when a session is started, loaded, or reloaded; its reason can be `startup`, `reload`, `new`, `resume`, or `fork`.
- `session_before_switch` is fired before `/new` or `/resume`; after a successful switch/new action Pi emits `session_shutdown` for the old extension instance, reloads/rebinds extensions, then emits `session_start` for the new session.
- `session_shutdown` is fired before a started session runtime is torn down; docs name reasons `quit`, `reload`, `new`, `resume`, and `fork` and instruct extensions to clean up resources opened from `session_start` or other session-scoped hooks.
- Agent event docs define `turn_start` and `turn_end` around each LLM response/tool-call turn, and `session_before_compact`/`session_compact` for compaction.

## Structural metadata

- Source type: installed package documentation
- Path: `/home/agent/.local/lib/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md`
- Relevant sections: event lifecycle diagram, `session_start`, `session_before_switch`, `session_shutdown`, `turn_start`, `turn_end`, compaction hooks.
