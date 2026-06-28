---
source_handle: remote-pi-cockpit-terminal-surface
fetched: 2026-06-28
source_path: cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway.dart
provenance: source-direct
---

# Remote Pi cockpit terminal surface attestation

## Source summary

Cockpit's terminal surface wraps `kyroon_pty` behind a domain `TerminalGateway`, connects it to an `xterm` `Terminal`, decodes streaming PTY output, supports resize and title changes, handles clipboard/image paste, and disposes subscriptions plus the PTY. The UI uses a local fork of xterm's `TerminalView` to inject Cockpit-specific rendering and scroll behavior.

## Key passages

> `PtyTerminalGateway` implements `TerminalGateway`, starts `Pty.start(...)` with working directory, rows/columns, shell, args, and environment; exposes `output`, `write`, `resize`, and `kill`.

> `_terminalEnv()` spreads `Platform.environment` and sets `TERM=xterm-256color` plus `COLORTERM=truecolor` so TUIs know the terminal supports 256-color/truecolor output.

> `_shell()` uses `powershell.exe` on most Windows, `cmd.exe` on Windows ARM, and `$SHELL` or `/bin/zsh` elsewhere; `_shellArgs()` uses `-l` on macOS/Linux for a login shell.

> `TerminalSession` creates `Terminal(maxLines: 10000, inputHandler: CascadeInputHandler([...]))`, starts the gateway, decodes `gateway.output` with `Utf8Decoder(allowMalformed: true)`, writes decoded data into the terminal, forwards `terminal.onOutput` to the gateway, forwards resize, and tracks OSC title changes.

> `TerminalSession.dispose()` cancels the output subscription, kills the gateway, and then calls `super.dispose()`.

> `CockpitTerminal` comments say it is a fork of xterm's `TerminalView`; the only intended difference is using `CockpitTerminalRender` with a picture cache instead of xterm's original render object.

## Notes for Remote Pi

Terminal changes must preserve resource ownership, environment propagation, Unicode/ANSI tolerance, max-line bounds, resize wiring, and explicit kill/cancel disposal. Private xterm imports are a contained terminal-surface exception.
