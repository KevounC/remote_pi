---
source_handle: react-19-server-components
fetched: 2026-06-28
source_url: https://react.dev/reference/rsc/server-components
provenance: source-direct
---

# React 19 Server Components attestation

## Source summary

React's Server Components reference for React 19.2 describes Server Components as components that render ahead of time in a server environment, can run at build time or per request, and cannot use client-only interactive APIs directly.

## Key passages

> React Server Components are a type of component that renders ahead of time, before bundling, in an environment separate from the client app or SSR server.

> Server Components can run once at build time on a CI server or for each request using a web server.

> React 19 Server Components are stable, but the underlying APIs used by bundlers/frameworks do not follow semver and may break between React 19.x minors.

> Server Components can run at build time to read from the filesystem or fetch static content, so a web server is not required for that use case.

> Server Components are not sent to the browser, so they cannot use interactive APIs like `useState`; to add interactivity, compose them with a Client Component using the `"use client"` directive.

> There is no directive for Server Components; `"use server"` is not how Server Components are denoted.

## Notes for Remote Pi

This reinforces the site rule that content components should remain server components unless interactivity is needed. It also argues against upgrading React minors casually when framework/RSC integration is involved.
