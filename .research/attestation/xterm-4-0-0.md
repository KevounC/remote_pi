---
source_handle: xterm-4-0-0
fetched: 2026-06-28
source_url: https://pub.dev/api/archives/xterm-4.0.0.tar.gz
provenance: source-direct
---

# xterm 4.0.0 attestation

## Source summary

The fetched `xterm` README describes `xterm.dart` as a Flutter terminal emulator for mobile and desktop. Its basic API creates a `Terminal`, handles user output via `onOutput`, renders via `TerminalView`, and writes terminal data via `terminal.write`. The source exposes `TerminalView` configuration for terminal, controller, theme, text style, focus node, shortcuts, key events, cursor, scroll, and other terminal behavior.

## Key passages

> `xterm.dart` is described as a fast, fully-featured terminal emulator for Flutter applications, with support for mobile and desktop platforms.

> README quick start creates `Terminal()`, assigns `terminal.onOutput`, renders `TerminalView(terminal)`, and calls `terminal.write('Hello, world!')`.

> Features include wide-character support, frontend-independent terminal core, Flutter shortcut integration, runtime theme changes, better performance, and IME support.

> `lib/src/terminal_view.dart` defines `TerminalView` with `Terminal terminal`, optional `TerminalController`, `TerminalTheme`, `TerminalStyle`, padding, scroll controller, auto resize, focus node, shortcuts, key event handler, read-only mode, and scroll simulation.

## Notes for Remote Pi

Cockpit uses a git override/fork for xterm block/box glyph rendering and forks `TerminalView` locally to inject a custom renderer. Treat `implementation_imports` in terminal UI as a deliberate local exception, not a general permission to import private package internals elsewhere.
