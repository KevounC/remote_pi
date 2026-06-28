---
name: next-site
description: Remote Pi Next/React/Tailwind site reference. Read before editing or reviewing site/ code, Next App Router routes/layouts/metadata, React Server/Client Components, Tailwind 4/PostCSS styling, next/image usage, static/presentational site content, Docker standalone build/deploy, or site lint/build workflows.
updated: 2026-06-28
provenance: skill-reference
---

# Next Site Reference

> Local scope: `site/`
> Versions/context: Next `16.2.6`, React `19.2.4`, React DOM `19.2.4`, TypeScript `^5`, Tailwind `^4` via `@tailwindcss/postcss`, ESLint `^9`, pnpm, `output: "standalone"`. [remote-pi-site-package-config]{1}
> Canonical local docs: `site/CLAUDE.md`, `site/package.json`, `site/next.config.ts`, `site/Dockerfile`.

## When to load

- Any edit or review under `site/`.
- Any change involving `src/app/` routes/layouts/metadata, `next/font`, `next/image`, React Server/Client Components, Tailwind tokens/classes, static docs/landing content, Docker build/deploy, or lint/build commands.
- Any proposed backend/API route, analytics/tracking, product feature, or deploy-model change.

## Commands

Run from `site/`: [remote-pi-site-guidance]{1}

```bash
pnpm install
pnpm dev
pnpm lint
pnpm build
pnpm start
```

`pnpm build` first runs `scripts/sync-install-sh.mjs`, then `next build`. [remote-pi-site-package-config]{1}

Deploy/publish is Docker-based per current cockpit/site guidance: `pnpm lint && pnpm build`, then `./push-docker.sh` after Docker Hub login. [remote-pi-site-guidance]{1}

Do not commit `.next/`, `out/`, `node_modules/`, local env files, generated build output, or secrets.

## Site responsibility boundary

`site/` is the institutional landing/docs site for Remote Pi, not a product surface. It should present the project, docs, install/download content, GitHub links, and legal pages; chat, pairing, relay controls, account logic, or backend APIs belong elsewhere unless a plan explicitly changes the site scope. [remote-pi-site-guidance]{1}

Rules:

- Keep the site presentation-only; do not introduce API routes/backends without a plan. [remote-pi-site-guidance]{1}
- No analytics/tracking cookies unless the privacy posture is explicitly updated.
- Prefer static/server-rendered content and simple typed components.
- Keep product protocol facts in durable docs such as `PROTOCOL.md`; site copy should summarize, not become the source of truth.

## App Router and React component model

Next App Router layouts and pages are Server Components by default. Use Client Components only when the component needs state, event handlers, lifecycle effects, browser-only APIs, or custom hooks. [next-16-server-client-components]{1}

React's Server Components reference says Server Components render ahead of time in a separate server environment, can run at build time or per request, and cannot use interactive APIs such as `useState`; interactivity is added by composing with Client Components using `"use client"`. [react-19-server-components]{1}

Project rules:

- Route files live under `site/src/app/`. [remote-pi-site-guidance]{1}
- Default to server components for pages, layout, content sections, docs shells, legal pages, and static CTA blocks.
- Add `"use client"` only for state/effects/events/browser APIs such as tabs, clipboard, reveal animations, or download copy actions. [next-16-server-client-components]{1} [remote-pi-site-app-surface]{1}
- Do not mark a parent page/client boundary just because one child is interactive; isolate a small client component and pass serializable props.
- Do not use `"use server"` as a marker for Server Components; React docs state there is no directive for Server Components. [react-19-server-components]{1}

## Layout, metadata, fonts, and paths

`src/app/layout.tsx` is the root shell: it imports global CSS, sets typed `Metadata`, loads Google fonts through `next/font/google`, adds font CSS variables to `<html>`, and wraps pages with `SiteHeader`, `main`, and `SiteFooter`. [remote-pi-site-app-surface]{1}

Rules:

- Keep global metadata in `layout.tsx` unless route-specific metadata is needed.
- Use `@/*` imports for `src/*` paths; `tsconfig.json` defines the alias. [remote-pi-site-package-config]{1}
- Keep global font families and design tokens centralized in `globals.css` / root layout.
- Keep props typed and avoid `any`; TypeScript strict mode is enabled. [remote-pi-site-package-config]{1}

## Tailwind 4 and CSS

Tailwind's Next.js guide for Tailwind 4 uses `@tailwindcss/postcss` in `postcss.config.mjs` and `@import "tailwindcss"` in global CSS. [tailwind-4-next-postcss]{1}

Project rules:

- Use Tailwind utility classes and centralized CSS variables/tokens; do not introduce CSS modules or styled-components. [remote-pi-site-guidance]{1}
- `globals.css` owns the dark palette, typography variables, `@theme inline` token mapping, and shared site classes. [remote-pi-site-app-surface]{1}
- Keep the canonical accent/palette stable unless doing explicit design work.
- Prefer reusable presentational components for repeated callouts/cards/docs shells over copy-pasted class blobs.

## Images and assets

Next's `Image` docs use `next/image` with `src`, dimensions or fill sizing, and `alt`; static imports can infer width/height, and function props such as `onLoad`/`onError` require Client Components. [next-16-image-component]{1}

Rules:

- Use `next/image` where optimization, responsive sizing, or layout stability matters. [remote-pi-site-guidance]{1}
- Plain `<img>` or inline SVG is acceptable for small icons/brand SVGs or intentionally unoptimized static assets.
- Keep meaningful `alt` text for content images; decorative assets should be intentionally marked.
- Do not add remote image domains or SVG optimization config casually; Next documents security/performance concerns around SVG optimization. [next-16-image-component]{1}

## Standalone Docker build/deploy

The site uses `output: "standalone"`. Next's output docs say standalone output creates `.next/standalone` with only necessary files, but `public` and `.next/static` are not copied into that folder by default. [next-16-output-standalone]{1}

Project rules:

- Keep `next.config.ts` `output: "standalone"` aligned with `site/Dockerfile`. [remote-pi-site-package-config]{1}
- Docker runtime must copy `public`, `.next/standalone`, and `.next/static`; this repo's Dockerfile does so before running `node server.js`. [next-16-output-standalone]{1}
- Preserve `NEXT_TELEMETRY_DISABLED=1`, non-root runtime user, port/hostname env, and healthcheck unless changing deploy policy.
- Treat `site/README.md` deploy wording as potentially stale if it conflicts with `site/CLAUDE.md`/Dockerfile; refresh it when doing site docs cleanup. [remote-pi-site-guidance]{1}

## Anti-patterns

- Adding product features, pairing/chat state, account logic, or API routes to the site without a scoped plan.
- Marking whole pages/layouts `"use client"` because a small child needs interactivity.
- Copying current Next/React/Tailwind examples without checking the local package pins and lockfile. [remote-pi-site-package-config]{1}
- Scattering raw colors/fonts instead of using site tokens.
- Disabling lint rules or weakening TypeScript to ship copy changes.
- Trusting stale README deploy/static-route claims over `site/CLAUDE.md`, `site/Dockerfile`, and current source.

## Review checklist

- [ ] Does the change keep `site/` presentation-only and backend-free?
- [ ] Are Server Components still the default, with `"use client"` isolated to genuinely interactive/browser-only components?
- [ ] Are route files, metadata, fonts, and global tokens in the appropriate App Router locations?
- [ ] Are Tailwind tokens/classes consistent with `globals.css` and no new styling system was introduced?
- [ ] Are images using `next/image` or a justified static/SVG path with correct alt behavior?
- [ ] Did package/API examples match local pins and `pnpm-lock.yaml`?
- [ ] Did `pnpm lint` and `pnpm build` pass, or were skips reported with a reason?
