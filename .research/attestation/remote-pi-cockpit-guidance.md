---
source_handle: remote-pi-cockpit-guidance
fetched: 2026-06-28
source_path: cockpit/CLAUDE.md
provenance: source-direct
---

# Remote Pi cockpit guidance attestation

## Source summary

`cockpit/CLAUDE.md` defines Cockpit as the local desktop client for Remote Pi: macOS-first Flutter desktop, local `pi --mode rpc` processes, no relay/pairing/crypto in the current phase, and vertical feature slices under `lib/app/` using `flutter_modular`.

## Key passages

> Cliente **desktop** (macOS first) do Remote Pi. GUI multi-pane sobre o motor do Pi... Cada agente é um `pi --mode rpc` que o app spawna e dirige **localmente** — sem relay, sem pareamento, sem crypto.

> DI + roteamento + estado: **`flutter_modular`** (v7). Cada feature é um módulo (`createModule`) que declara **suas próprias rotas + binds**; estado page-scoped via `provide`/`addChangeNotifier`.

> **Diverge do `app/` de propósito**: o cockpit é organizado em **fatias verticais por feature** (`lib/app/<feature>/{domain,data,ui}`), não em camadas globais.

> Acessar `context` após um `await` (ou dentro de `.then/.onSuccess/.flatMap/.whenComplete`) pode crashar... Sempre transforme para `await` + guard.

## Notes for Remote Pi

The cockpit reference must not import mobile assumptions from `app/`: no provider/go_router baseline, no relay session state as current cockpit scope, and no remote crypto/pairing unless a future plan changes cockpit scope.
