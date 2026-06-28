---
source_handle: remote-pi-site-package-config
fetched: 2026-06-28
source_path: site/package.json
provenance: source-direct
---

# Remote Pi site package/config attestation

## Source summary

`site/package.json` pins the site to Next 16.2.6, React 19.2.4, TypeScript 5, Tailwind 4, ESLint 9, and pnpm scripts. `next.config.ts` enables `output: "standalone"`; PostCSS uses `@tailwindcss/postcss`; ESLint composes Next core web vitals and TypeScript configs; TypeScript is strict and maps `@/*` to `src/*`.

## Key passages

> Scripts: `dev` runs `next dev`; `build` runs `node scripts/sync-install-sh.mjs && next build`; `start` runs `next start`; `lint` runs `eslint`.

> Dependencies: `next: 16.2.6`, `react: 19.2.4`, `react-dom: 19.2.4`.

> Dev dependencies include `@tailwindcss/postcss: ^4`, `eslint: ^9`, `eslint-config-next: 16.2.6`, `tailwindcss: ^4`, and `typescript: ^5`.

> `next.config.ts` sets `output: "standalone"`.

> `postcss.config.mjs` configures `"@tailwindcss/postcss": {}`.

> `eslint.config.mjs` uses `eslint-config-next/core-web-vitals` and `eslint-config-next/typescript`, with global ignores for `.next/**`, `out/**`, `build/**`, and `next-env.d.ts`.

> `tsconfig.json` enables `strict`, `noEmit`, `moduleResolution: "bundler"`, `jsx: "react-jsx"`, the Next TypeScript plugin, and `paths: { "@/*": ["./src/*"] }`.

## Checked package-version facts

From npm package metadata fetched on 2026-06-28:

- `next`: local `16.2.6`, npm latest `16.2.9`.
- `react`: local `19.2.4`, npm latest `19.2.7`.
- `tailwindcss`: local range `^4`, npm latest `4.3.1`.
- `@tailwindcss/postcss`: local range `^4`, npm latest `4.3.1`.
- `eslint`: local range `^9`, npm latest `10.6.0`.
- `typescript`: local range `^5`, npm latest `6.0.3`.

## Notes for Remote Pi

Follow the local lockfile and package pins for implementation. Latest-doc examples are useful for patterns, but version-moving changes should be explicit dependency work.
