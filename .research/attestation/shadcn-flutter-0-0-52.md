---
source_handle: shadcn-flutter-0-0-52
fetched: 2026-06-28
source_url: https://pub.dev/api/archives/shadcn_flutter-0.0.52.tar.gz
provenance: source-direct
---

# shadcn_flutter 0.0.52 attestation

## Source summary

The fetched `shadcn_flutter` 0.0.52 README presents the package as a cohesive Flutter UI ecosystem with components, theming, design tokens, and optional Material/Cupertino interop across mobile, web, and desktop. The source exposes `ThemeData`, `Theme`, and a `BuildContext` theme extension.

## Key passages

> `shadcn_flutter` is described as "A cohesive shadcn/ui ecosystem for Flutter—components, theming, and tooling—ready to ditch Material and Cupertino".

> The README says it is a standalone ecosystem with no Material or Cupertino requirement, optional interop, shadcn/ui design tokens, a New York theme, and first-class support across Android, iOS, Web, macOS, Windows, and Linux.

> The README says users can adopt it incrementally inside an existing MaterialApp/CupertinoApp, keep routing such as GoRouter, and align visuals with the shadcn_flutter theme.

> The README links a widget catalog and an `llms-full.txt` component reference.

> `lib/src/theme/theme.dart` defines `ThemeData`, `ThemeData.dark`, `Theme.of(context)`, and `ThemeData.copyWith`; `lib/src/theme/theme_extension.dart` exposes `context.theme` and `context.componentTheme<T>()`.

## Notes for Remote Pi

Cockpit pins `shadcn_flutter` exactly at `0.0.52` because it is pre-1.0. Agents should use local `context.colors` / `context.typo` wrappers from Cockpit's theme layer rather than hardcoding package-level styles everywhere.
