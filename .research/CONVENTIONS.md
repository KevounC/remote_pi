# Remote Pi research conventions

Remote Pi uses a lightweight ARD-style research band for source-grounded reference work that supports `.work/` items tagged `research`.

## Layout

- `attestation/<handle>.md` — per-source source-direct attestations. These are the citation anchors for `[handle]{N}` citations in reference docs or synthesis notes.
- Additional ARD tiers (`reference/`, `precis/`, `analysis/`) may be added when a research engagement needs them. Do not invent citations without an attestation file.

## Attestation frontmatter

```yaml
---
source_handle: <handle>
fetched: YYYY-MM-DD
source_url: <url>      # for web sources
source_path: <path>    # for local source/docs files
provenance: source-direct
---
```

## Citation rule

Use `[handle]{N}` only when `<handle>` exists in `attestation/` and the attestation body records the cited detail. For local code/documentation sources, `source_path` is sufficient when the file was read directly during the engagement.
