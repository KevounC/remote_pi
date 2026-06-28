---
source_handle: tailwind-4-next-postcss
fetched: 2026-06-28
source_path: .research/sources/tailwind-nextjs-installation-2026-06-28.txt
provenance: source-direct
---

# Tailwind 4 Next.js/PostCSS attestation

## Source summary

Tailwind's Next.js installation guide for Tailwind 4 instructs Next projects to install `tailwindcss`, `@tailwindcss/postcss`, and `postcss`, configure the PostCSS plugin, and import Tailwind in global CSS.

## Key passages

> The guide installs Tailwind CSS with `npm install tailwindcss @tailwindcss/postcss postcss`.

> The guide says to add `@tailwindcss/postcss` to the PostCSS configuration.

> Example `postcss.config.mjs`: `const config = { plugins: { "@tailwindcss/postcss": {}, }, }; export default config;`.

> The guide says to add an `@import` to `./app/globals.css` that imports Tailwind CSS.

> Example `globals.css`: `@import "tailwindcss";`.

> The guide's example page uses utility classes directly in `className`, such as `text-3xl font-bold underline`.

## Notes for Remote Pi

This matches `site/postcss.config.mjs` and `site/src/app/globals.css`. Cockpit/site design tokens should stay centralized in CSS variables and Tailwind theme mappings rather than scattered as one-off color literals.
