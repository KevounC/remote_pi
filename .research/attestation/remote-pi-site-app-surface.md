---
source_handle: remote-pi-site-app-surface
fetched: 2026-06-28
source_path: site/src/app/layout.tsx
provenance: source-direct
---

# Remote Pi site app surface attestation

## Source summary

The site uses Next App Router under `site/src/app/`, global Tailwind/design-token CSS, typed metadata in the root layout, `next/font/google`, and mostly presentational route pages/components. Some components opt into client behavior where browser state/effects are needed.

## Key passages

> `layout.tsx` imports `Metadata` from `next`, `Space_Grotesk`, `Hanken_Grotesk`, and `JetBrains_Mono` from `next/font/google`, imports `./globals.css`, and wraps every page with `SiteHeader`, `main`, and `SiteFooter`.

> `metadata` sets `metadataBase`, title template, description, application name, authors, keywords, Open Graph, and Twitter metadata for the Remote Pi site.

> The root layout adds font CSS variables to `<html>` and renders `<body className="min-h-full flex flex-col bg-bg text-fg">`.

> `globals.css` begins with `@import "tailwindcss"`, defines the canonical dark palette and typography variables, maps Tailwind theme tokens with `@theme inline`, and contains the shared utility/component classes for the site.

> Route files under `src/app/` include landing, docs, download, tutorials, legal, cockpit, and why pages. `src/components/landing/reveal-controller.tsx`, `src/components/install-tabs.tsx`, `src/components/tabs.tsx`, and `src/components/download/sha-copy.tsx` are client components; most content components are server-rendered presentational components.

## Notes for Remote Pi

Keep root metadata and design tokens centralized. Use `"use client"` only for components that need state, effects, event handlers, clipboard, or browser APIs.
