---
source_handle: next-16-server-client-components
fetched: 2026-06-28
source_url: https://nextjs.org/docs/app/getting-started/server-and-client-components
provenance: source-direct
---

# Next 16 Server and Client Components attestation

## Source summary

Next's Server and Client Components documentation for version 16.2.9 states that App Router layouts and pages are Server Components by default, and Client Components are used when interactivity or browser APIs are needed.

## Key passages

> Frontmatter identifies the page as Next.js docs version `16.2.9`, last updated 2026-06-23.

> By default, layouts and pages are Server Components, which lets them fetch data and render UI on the server, optionally cache results, and stream to the client.

> Use Client Components for state, event handlers, lifecycle logic such as `useEffect`, browser-only APIs such as `localStorage`, `window`, or `Navigator.geolocation`, and custom hooks.

> Use Server Components for data close to the source, secrets that should not be exposed to the client, reducing JavaScript sent to the browser, improving First Contentful Paint, and progressive streaming.

> The docs show a Server Component passing props to a Client Component for client-side interactivity.

## Notes for Remote Pi

This supports the local site convention: default to server-rendered presentational components, and add `"use client"` only for interaction/browser APIs.
