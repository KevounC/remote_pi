---
source_handle: kyroon-pty-1-0-4
fetched: 2026-06-28
source_url: https://pub.dev/api/archives/kyroon_pty-1.0.4.tar.gz
provenance: source-direct
---

# kyroon_pty 1.0.4 attestation

## Source summary

The fetched `kyroon_pty` README describes a Flutter PTY plugin that spawns child processes attached to native pseudo-terminals, supports Linux/macOS/Windows/Android, uses ConPTY on Windows, and pairs naturally with `xterm` for interactive terminal widgets.

## Key passages

> `kyroon_pty` spawns a child process attached to a pseudo-terminal so line editing, ANSI colors, cursor control, job control, and resize work as in a real terminal.

> It implements the PTY in native code and pairs naturally with `xterm` to render a fully interactive terminal widget.

> Platform support table marks Linux, macOS, Windows, and Android as supported; Windows uses ConPTY and requires Windows 10 1809+.

> Quick start uses `Pty.start(...)`, `pty.output`, `pty.write(...)`, `pty.exitCode`, `pty.resize(...)`, and `pty.kill()`.

> Configuration includes executable, arguments, working directory, environment, rows, columns, and `ackRead`.

> The README says `kyroon_pty` always sets `TERM=xterm-256color` and `LANG=en_US.UTF-8`, copies a small set of environment variables, and recommends passing `Platform.environment` for a real terminal, especially on Windows.

> The API reference notes that a PTY does not distinguish stdout from stderr; both arrive on `output`, and there is no guarantee output has drained when `exitCode` completes.

## Notes for Remote Pi

Cockpit overrides `kyroon_pty` to a fork ref `v1.0.5`; the public README still grounds the API shape, while local source/pin explains the fork. Terminal lifecycle must kill PTYs and cancel output subscriptions to avoid orphan processes.
