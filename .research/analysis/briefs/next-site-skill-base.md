---
slug: next-site-skill-base
created: 2026-06-28
provenance: synthesis
---

# Next site skill-base brief

## Registration summary

- Commissioning item: `story-api-reference-next-site-stack`.
- Scope authority: mixed.
- Verification rigor: floor.
- Decision relevance: decide whether `site/` needs a lightweight `.agents/skills/next-site/SKILL.md` now, or a clear deferral rationale.

## Synthesis

Remote Pi should create a concise site reference rather than defer. The site is presentation-only, but it is not an inert one-page stub: local guidance names a Next 16 / React 19 / Tailwind 4 stack, Docker publishing, and explicit constraints against product logic, backend routes, lint bypassing, and committed build output. [remote-pi-site-guidance]{1} The source tree contains multiple App Router pages, client components for tabs/reveal/copy interactions, global design tokens, and a standalone Docker build. [remote-pi-site-app-surface]{1} [remote-pi-site-package-config]{1}

The reference should stay lightweight. The load-bearing guidance is: keep the site presentation-only; default to Server Components and isolate `"use client"`; preserve the Tailwind 4 PostCSS setup and centralized design tokens; check local package pins before copying latest docs; and keep `output: "standalone"` aligned with the Docker runtime. Next's docs state that App Router pages/layouts are Server Components by default and Client Components are for state, event handlers, effects, browser APIs, and custom hooks. [next-16-server-client-components]{1} React's Server Components reference reinforces that Server Components cannot use interactive APIs such as `useState`; interactivity belongs in Client Components. [react-19-server-components]{1}

The deploy/reference portion should prefer current local `site/CLAUDE.md`, `site/Dockerfile`, and `next.config.ts` over the older README wording. Next's standalone-output docs explain that `.next/standalone` does not include `public` or `.next/static` by default, matching why this repo's Dockerfile copies those folders explicitly. [next-16-output-standalone]{1} Tailwind's Next.js guide matches this repo's `@tailwindcss/postcss` config and `@import "tailwindcss"` global CSS entry. [tailwind-4-next-postcss]{1}

## Output

- `.agents/skills/next-site/SKILL.md`
- New attestations under `.research/attestation/` for local site guidance/config/source and current Next/React/Tailwind docs.

## Contradictions

No source contradiction blocks the output. A documentation drift was found: `site/README.md` still says Vercel is the expected deploy target and describes only three static routes, while current `site/CLAUDE.md`, `site/Dockerfile`, and source tree show Docker publishing and more routes. The skill records the current agent-facing rule to prefer `site/CLAUDE.md`/Dockerfile for deploy behavior until README cleanup is explicitly picked up. [remote-pi-site-guidance]{1} [remote-pi-site-app-surface]{1}

## Disconfirming analysis

The deferral argument was that current refactor work is mostly app/pi-extension/relay, and site is only presentational. That would justify a shorter reference, not no reference: package versions are current enough to have App Router/RSC/Tailwind 4 gotchas, the local deploy path has standalone-output details, and the README/CLAUDE deploy drift makes agent guidance useful. [remote-pi-site-package-config]{1} [next-16-output-standalone]{1}

## Verification

- Citation handles in this brief correspond to `.research/attestation/*.md` files added during the engagement.
- Spot-check focus: package-version claims are tied to `site/package.json` and npm metadata; Server/Client/Tailwind/standalone-output guidance is tied to current fetched docs; local site behavior is tied to source files.
- No acquisition candidates were identified; relevant current docs and local source were fetchable.
