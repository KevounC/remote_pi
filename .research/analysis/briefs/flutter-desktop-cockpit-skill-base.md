---
slug: flutter-desktop-cockpit-skill-base
created: 2026-06-28
provenance: synthesis
---

# Flutter desktop cockpit skill-base brief

## Registration summary

- Commissioning item: `story-api-reference-flutter-desktop-cockpit-stack`.
- Scope authority: mixed.
- Verification rigor: floor.
- Decision relevance: decide whether to create `.agents/skills/flutter-desktop-cockpit/SKILL.md` now, and what current package/API guidance it should encode vs defer.

## Synthesis

Remote Pi should create the cockpit reference now rather than defer. Cockpit is an active desktop app with its own architecture and plugin risk profile: local guidance identifies it as a macOS-first Flutter desktop GUI, vertically sliced by feature with `flutter_modular`, and explicitly divergent from the mobile app. [remote-pi-cockpit-guidance]{1} The package set adds enough native-boundary risk to justify a reference: exact-pinned pre-1.0 `shadcn_flutter`, `flutter_modular`, Hive, PTY/terminal packages, file/window/notification/media/update plugins, and git overrides for xterm, gpt_markdown, and kyroon_pty. [remote-pi-cockpit-pubspec]{1}

The reference should be risk-first, not a package encyclopedia. The highest-risk rules are lifecycle ownership and platform boundaries: `main()` and module builders own async bootstrap, Hive boxes, window state, orphan-process cleanup, and feature module composition. [remote-pi-cockpit-bootstrap-modules]{1} `flutter_modular` source confirms that pathful modules are feature-scoped, pathless modules are root-owned, and page `provide` registrations dispose page-scoped state. [flutter-modular-7-1]{1} Terminal work must preserve the `TerminalGateway` seam, PTY environment propagation, streaming UTF-8 decode, resize wiring, bounded scrollback, and cancellation/kill disposal. [remote-pi-cockpit-terminal-surface]{1} [kyroon-pty-1-0-4]{1} [xterm-4-0-0]{1}

For UI, `shadcn_flutter` provides the design-system substrate, but Cockpit's local theme wrappers should remain the app-facing API so agents do not hardcode package-level styles. [shadcn-flutter-0-0-52]{1} File/media surfaces need the same lifecycle posture: file/LSP/media code crosses native and process boundaries, so subscriptions, debounces, documents, controllers, and mounted checks are part of correctness rather than polish. [remote-pi-cockpit-file-media-surface]{1}

## Output

- `.agents/skills/flutter-desktop-cockpit/SKILL.md`
- New attestations under `.research/attestation/` for local cockpit guidance, local package pins, module/bootstrap shape, terminal/file surfaces, Flutter desktop support, and current package docs.

## Contradictions

No source contradiction blocks the output. There is a scope tension: older cockpit guidance describes the MVP as local-only/no relay/pairing, while the current tree contains settings/connectivity/pairing-related files. The skill therefore avoids authorizing mobile-style remote-session behavior and tells agents to follow current cockpit feature/module contracts plus relevant docs when editing those surfaces, rather than treating the mobile app as the model. [remote-pi-cockpit-guidance]{1}

## Disconfirming analysis

Searched for reasons to defer the reference. The main possible deferral would be if cockpit were inactive or too small, but local code and dependencies show active desktop-specific surfaces: window state, Hive repositories, terminal/PTY, file viewer/LSP, notifications, updates, and native plugins. [remote-pi-cockpit-bootstrap-modules]{1} [remote-pi-cockpit-terminal-surface]{1} [remote-pi-cockpit-file-media-surface]{1} Current package checks also show API-drift risk in several native packages and pre-1.0/exact-pinned packages, which supports writing a reference rather than relying on tribal knowledge. [remote-pi-cockpit-pubspec]{1}

## Verification

- Citation handles in this brief correspond to `.research/attestation/*.md` files added during the engagement.
- Spot-check focus: load-bearing claims about architecture, module lifecycle, package pins, and terminal/file resource ownership are tied to local source or fetched package documentation.
- No acquisition candidates were identified; package documentation and local source were available through pub.dev archives/API or repository files.
