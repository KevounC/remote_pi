---
source_handle: next-16-image-component
fetched: 2026-06-28
source_url: https://nextjs.org/docs/app/api-reference/components/image
provenance: source-direct
---

# Next 16 Image component attestation

## Source summary

Next's `Image` component documentation for version 16.2.9 describes optimized image usage through `next/image`, including static imports, explicit width/height or fill sizing, and client-component requirements for function props.

## Key passages

> Frontmatter identifies the page as Next.js docs version `16.2.9`, last updated 2026-06-23.

> Basic usage imports `Image` from `next/image` and renders an image with `src`, `width`, `height`, and `alt`.

> Static imports are supported; when using static image imports, Next.js automatically sets width and height based on the file.

> The docs show responsive images by setting `sizes` and styles such as `width: '100%'` and `height: 'auto'`.

> Function props such as `onLoad` and `onError` require Client Components so the function can be serialized/provided on the client side.

> By default, Next.js does not optimize SVG images for several security/performance reasons and requires explicit configuration for SVG optimization behavior.

## Notes for Remote Pi

For static site assets, prefer `next/image` where optimization and layout behavior matter. Plain `<img>`/SVG can still be appropriate for inline icons or intentionally unoptimized static assets, but interactive image handlers require `"use client"`.
