---
source_handle: remote-pi-site-guidance
fetched: 2026-06-28
source_path: site/CLAUDE.md
provenance: source-direct
---

# Remote Pi site guidance attestation

## Source summary

`site/CLAUDE.md` defines `site/` as the Remote Pi institutional landing/docs site. It is presentation-only, with no product logic, and uses Next 16 App Router, React 19, TypeScript 5, Tailwind 4 via `@tailwindcss/postcss`, ESLint 9, and pnpm.

## Key passages

> Landing page institucional do Remote Pi. Apresenta projeto, links pro GitHub, documentação do MVP. **Apenas apresentação — não tem lógica de produto.**

> Stack: NextJS 16 (App Router), React 19, TypeScript 5, Tailwind 4 (via `@tailwindcss/postcss`), ESLint 9, pnpm.

> Convenções: **Server Components por padrão** — só usar `"use client"` quando necessário (state, events, hooks); routes live in `src/app/`; styles are Tailwind utility-first; images use `next/image`; typed component props and no `any`.

> NÃO fazer: do not add product features such as chat/pairing; do not commit `.next/`, `out/`, or `node_modules`; do not disable lint just to pass; do not introduce backend/API routes without registering a plan.

> Production deploy currently runs as a Docker image `jacobmoura7/remote-pi-site`; publish flow is git push plus `pnpm lint && pnpm build`, then `./push-docker.sh`.

## Notes for Remote Pi

The site should remain a static/presentational surface unless a plan explicitly expands it. `site/README.md` contains older deploy/static-route wording, so agent-facing deployment guidance should prefer `site/CLAUDE.md`, `site/Dockerfile`, and `site/push-docker.sh` until the README is refreshed.
