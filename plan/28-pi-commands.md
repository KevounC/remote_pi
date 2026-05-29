# Plano 28 — Slash commands no App

Objetivo: expor os slash commands do Pi (`/compact`, `/model`, etc. + comandos
registrados por extensões como `/remote-pi …`) na UI do app mobile, com
duas formas de invocação:

1. Botão picker ao lado do botão de arquivos no TextField (visível só com
   input vazio) → bottom sheet com lista filtrável
2. Trigger inline ao digitar `/` na primeira posição → popover ranqueado

Comando selecionado vira **chip canonizado** no TextField — backspace deleta o
chip inteiro de uma vez. Envio com chip presente sai como `command_invoke`;
sem chip, sai como texto livre (mesmo que comece com `/`).

**Status (2026-05-28)**: Wave 0 ✅ scout do SDK concluído. Wave A/B em
execução pelo orquestrador (pi-pane ocupado).

---

## Wave 0 — Descoberta do SDK do Pi (CONCLUÍDA)

Investigação no `@mariozechner/pi-coding-agent` 0.73.1 (read-only):

### Listing

✅ **`pi.getCommands(): SlashCommandInfo[]`** existe no `ExtensionAPI`. Retorna
extensão-registered + prompt templates + skills. **NÃO inclui builtins.**

Builtins (`BUILTIN_SLASH_COMMANDS`) moram em `core/slash-commands.js` mas
`exports` field do package bloqueia deep import. Sem PR upstream, temos que
**espelhar manualmente** a lista no pi-extension.

Lista builtin no SDK 0.73.1 (mirror authoritative):

| name | description |
|---|---|
| `/settings` | Open settings menu |
| `/model` | Select model |
| `/scoped-models` | Enable/disable models for Ctrl+P cycling |
| `/export` | Export session |
| `/import` | Import and resume a session from a JSONL file |
| `/share` | Share session as a secret GitHub gist |
| `/copy` | Copy last agent message to clipboard |
| `/name` | Set session display name |
| `/session` | Show session info and stats |
| `/changelog` | Show changelog entries |
| `/hotkeys` | Show all keyboard shortcuts |
| `/fork` | Create a new fork from a previous user message |
| `/clone` | Duplicate the current session at the current position |
| `/tree` | Navigate session tree |
| `/login` | Configure provider authentication |
| `/logout` | Remove provider authentication |
| `/new` | Start a new session |
| `/compact` | Manually compact the session context |
| `/resume` | Resume a different session |
| `/reload` | Reload keybindings, extensions, skills, prompts, themes |
| `/quit` | Quit pi |

### Invocação

❌ **NÃO existe API tipo `pi.runBuiltin("compact")`**. Builtins são parseados
num `if/else` chain dentro de `interactive-mode.js`, acoplado à TUI. Alguns
têm equivalente programático via `ExtensionContextActions`:

| Builtin | Programmatic equiv |
|---|---|
| `/compact` | `ctx.compact()` |
| `/quit` | `ctx.shutdown()` |
| `/abort` (não é builtin, é hotkey) | `ctx.abort()` |
| `/model` | `pi.setModel(model)` — precisa picker de modelo na app |
| outros | sem equivalente — precisa PR upstream |

Extension-registered commands têm `handler: (args, ctx) => Promise<void>`
mas a `ExtensionAPI` não expõe lookup-by-name (só `getCommands` read-only).
Pra invocar os nossos próprios `/remote-pi …` programaticamente, mantemos
referência local dentro do `extension` factory.

### Decisão arquitetural — Caminho A (recomendado e adotado)

**Listar tudo (builtins via mirror + extensions via SDK), invocar subset
curado.**

- Lista enviada pra app inclui `invokable: boolean`
- App renderiza não-invokable grayed com tooltip "available in terminal only"
- Subset invokable inicial: `/compact`, `/quit`, `/abort` (via context),
  `/model` (via `pi.setModel` + app picker), comandos `/remote-pi *` (via
  referência local que mantemos)
- PR upstream pra `pi.invokeBuiltin(name, args)` fica como upgrade path
  futuro — quando aterrissa, flipamos mais `invokable: true` sem mudar wire

Caminhos descartados:

- **B — PR upstream agora**: bloqueia toda a feature em merge externo
- **C — Monkey-patch**: frágil, quebra em update do SDK

---

## Wave A — Protocolo (em execução)

Adicionar ao `pi-extension/src/protocol/types.ts`:

```ts
// ClientMessage union — nova variante:
| { type: "list_commands"; id: string }
| { type: "command_invoke"; id: string; name: string; args?: string }

// ServerMessage union — novas variantes:
| { type: "commands_list"; in_reply_to: string; commands: WireCommand[] }
| { type: "command_result"; in_reply_to: string; ok: boolean; error?: string }

// Novo tipo:
export interface WireCommand {
  /** Slash command name SEM a barra. Ex: "compact", "model", "remote-pi". */
  name: string;
  /** Descrição curta human-readable. */
  description?: string;
  /** Origem do comando no runtime do Pi. */
  source: "builtin" | "extension" | "prompt" | "skill";
  /** Whether this Pi build can invoke the command programmatically.
   *  When false, the app should render the command as a hint only
   *  (grayed out + tooltip "available in terminal only"). */
  invokable: boolean;
  /** Whether the command accepts free-text args after its name.
   *  When true, the app shows a text input after the chip is placed. */
  takes_args: boolean;
}
```

Também atualizar `PROTOCOL.md` no raiz com seção "Slash commands wire".

**DoD Wave A**:
- [ ] Tipos novos em `pi-extension/src/protocol/types.ts`
- [ ] `pnpm typecheck` verde
- [ ] Seção "Slash commands" no `PROTOCOL.md`

---

## Wave B — pi-extension handler

### Slice 1 — `list_commands` (em execução)

- Novo arquivo `pi-extension/src/commands/builtin_mirror.ts` com a lista
  espelhada da tabela acima + comentário apontando pro SDK 0.73.1 e TODO
  de PR upstream
- Em `index.ts`, no `_routeClientMessageFrom`:
  ```ts
  if (msg.type === "list_commands") {
    _handleListCommands(sender, msg);
    return;
  }
  ```
- Handler junta `BUILTIN_SLASH_COMMANDS_MIRROR` + `_pi.getCommands()`,
  mapeia pra `WireCommand[]` com `invokable` decidido por `_isInvokable(name, source)`
- Tabela `INVOKABLE_BUILTINS = new Set(["compact", "quit"])` no MVP
- Test vitest: simula `list_commands` request → asserta shape do reply

### Slice 2 — `command_invoke` (FUTURO, fora desta wave)

- Handler `_handleCommandInvoke` que despacha por nome:
  - `compact` → `_lastCtx?.compact()`
  - `quit` → `_lastCtx?.shutdown()` (com `bye` antes pro app)
  - `model` → caso especial; ver Wave D
  - `remote-pi*` → invoca via referência local
  - outros → reply `{ok:false, error:"not_invokable"}`
- Test vitest: cada nome curado retorna ok; nome não-invokable retorna erro

**DoD Wave B**:
- [ ] Slice 1: handler `list_commands` + builtin mirror + test
- [ ] Slice 2: handler `command_invoke` + matriz de dispatch + test
- [ ] `pnpm typecheck && pnpm test` verdes
- [ ] Sem regressão nos 384 testes baseline

---

## Wave C — App UI

**Toca**: `app/lib/ui/chat/`, `app/lib/data/commands/` (novo), `app/lib/domain/`

### Listagem
- Repositório `CommandsRepository` que envia `list_commands` na abertura do
  chat e cacheia por `(piPeerId, sessionId)`
- Refresh manual via pull-to-refresh ou ao receber error "stale"

### UI do TextField
- Botão "/" ao lado do botão de arquivos, visível **só quando input vazio**
  (`controller.text.isEmpty`)
- Tap → bottom sheet com `ListView` filtrável
- Item: `nome • descrição • badge da source • indicador "terminal only" se !invokable`

### Trigger inline
- `TextField` com listener que, ao detectar `/` no índice 0 com input limpo
  acima, abre `OverlayEntry` posicionado acima do TextField
- Continua filtrando enquanto digita; Esc/tap-fora fecha
- Tap em item canoniza → substitui o texto por um chip widget

### Chip canonizado
- `CommandChip` widget dentro de `Row` com o TextField — usar `TextField` com
  `prefixIcon` carregando o chip OU substituir por `RichText` editable
- Decisão de implementação: provavelmente `flutter_chips_input`-style custom
  widget. Detalhe técnico fica pro agent do app
- Backspace na borda esquerda do texto pós-chip → deleta chip inteiro
- Texto depois do chip = `args`

### Envio
- Sem chip: `user_message` normal
- Com chip: `command_invoke { name: chip.name, args: textAfterChip.trim() }`
- Aguarda `command_result` → mostra toast de erro ou nada se ok
  (efeitos visíveis virão por `agent_chunk`/`agent_done` se o comando produz
  output)

**DoD Wave C**:
- [ ] Botão picker visível só com input vazio
- [ ] Bottom sheet filtrável funcional
- [ ] Trigger inline por `/` com overlay
- [ ] Chip canonizado + backspace atômico
- [ ] Envio diferenciado (text vs command_invoke)
- [ ] Não-invokable: chip grayed + bloqueio no envio com toast
- [ ] `flutter test` cobrindo lógica de canonização e envio
- [ ] Smoke: pair → rodar `/compact` via picker → ver chat compactado

---

## Wave D — Polish + futuras integrações

- **`/model` UX especial**: ao escolher `/model`, app abre um sub-picker com
  lista de modelos disponíveis (já temos `mesh_models` ou similar?). Envia
  `command_invoke { name: "model", args: "<model_id>" }`
- **Cross-PC**: listar comandos de um Pi irmão. Requer roteamento via
  envelope cross-PC. Fora do MVP — adicionar no Plan/26 quando a UI
  multi-Pi entrar
- **Push de mudanças**: SDK não emite `commands_changed`, mas a extensão
  pode emitir `commands_changed` no `session_start` (reason=reload) pra
  app refrescar
- **PR upstream**:
  - Adicionar `BUILTIN_SLASH_COMMANDS` ao `exports` do package (1 linha)
  - Adicionar `pi.invokeBuiltin(name, args)` à `ExtensionAPI`
  - Quando merged, deletar o mirror local e atualizar a tabela
    `INVOKABLE_BUILTINS`
- **Docs**:
  - Atualizar `PROTOCOL.md` com seção definitiva
  - Atualizar `pi-extension/README.md` mencionando suporte a slash commands no app
  - Atualizar `site/` doc com screenshot/diagrama do picker

**DoD Wave D**:
- [ ] `/model` com sub-picker funcional
- [ ] PR upstream aberto (link no plano)
- [ ] Docs atualizadas

---

## DoD consolidado

- [ ] Wave 0: scout do SDK ✅
- [ ] Wave A: tipos no protocolo + seção em PROTOCOL.md
- [ ] Wave B Slice 1: handler `list_commands` + mirror + test
- [ ] Wave B Slice 2: handler `command_invoke` + dispatch + test
- [ ] Wave C: UI completa no app
- [ ] Wave D: `/model` sub-picker, PR upstream, docs

## Próximos planos

- Plan 26 retomado: sessões cross-PC na UI (lista de comandos por sibling)
- Plan upstream: PR `BUILTIN_SLASH_COMMANDS` + `invokeBuiltin` no SDK do Pi
