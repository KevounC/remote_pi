---
source_handle: next-16-output-standalone
fetched: 2026-06-28
source_url: https://nextjs.org/docs/app/api-reference/config/next-config-js/output
provenance: source-direct
---

# Next 16 standalone output attestation

## Source summary

Next's `output` config documentation for version 16.2.9 explains output file tracing and `output: 'standalone'`, which creates `.next/standalone` with the files needed for production deployment.

## Key passages

> Frontmatter identifies the page as Next.js docs version `16.2.9`, last updated 2026-06-23.

> During `next build`, Next.js automatically traces each page and its dependencies to determine all files needed for deploying a production version of the application.

> `output: 'standalone'` creates a `.next/standalone` folder that copies only the necessary files for a production deployment, including select files in `node_modules`.

> The docs show `module.exports = { output: 'standalone' }`.

> The `.next/standalone` folder does not copy the `public` or `.next/static` folders by default; these can be copied manually into `standalone/public` and `standalone/.next/static` so the minimal server can serve them.

> The minimal standalone server is run with `node .next/standalone/server.js`.

## Notes for Remote Pi

This matches `site/next.config.ts` and `site/Dockerfile`: the Docker runtime copies `/app/public`, `.next/standalone`, and `.next/static`, then starts `node server.js`.
