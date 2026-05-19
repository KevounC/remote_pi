# Protocol — Remote Pi

Fonte de verdade do protocolo de mensagens entre **app** (Flutter) e
**pi-extension** (Node), trafegando através do **relay** (Rust). Cada
subprojeto implementa tipos derivados desta spec; mudanças aqui disparam
realinhamento nos 3 lados.

> **Modelo MVP**: 1 pareamento = 1 sessão Pi. Sem session manager, sem
> project scope, sem switch_session. Ver `plan/00-decisions.md`.

> **Crypto E2E removida no plano 06** (2026-05-19). O `ct` do envelope
> externo é **base64 do JSON do inner em claro**. Relay continua opaco
> (nunca chama `JSON.parse(ct)`). O shape permanece igual ao desenhado
> originalmente — re-ativar Noise XX no futuro (plano 09 opcional) só
> troca o gerador/parser do `ct`, sem mexer em transporte ou schema.

---

## Camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│  Inner envelope (app ↔ pi-extension)                                  │
│  Semântica do produto. JSON em claro.                                 │
│  Schema: { type, id?, in_reply_to?, ...payload }                      │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  base64(JSON.stringify(inner))
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Outer envelope (relay)                                               │
│  Roteamento puro. Payload opaco ao relay (não decodificado).          │
│  Schema: { peer: "<id>", ct: "<base64>" }                             │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  framing JSONL (\n)
                              ▼
                          WebSocket
```

---

## Decisões fixadas

| Decisão | Valor |
|---|---|
| Framing | **JSONL** (LF-delimited, UTF-8 estrito) |
| Envelope externo | `{ "peer": "<id>", "ct": "<base64>" }` (único que o relay parseia) |
| Conteúdo de `ct` | **base64 do JSON do inner em claro** (sem cifra, sem MAC) |
| Envelope interno | `{ "type": "<kind>", "id"?: "<uuid>", "in_reply_to"?: "<uuid>", ...payload }` |
| ID de correlação | **UUIDv7** (string) em qualquer mensagem que espera resposta |
| `in_reply_to` | Campo opcional em respostas, ecoa `id` da request |
| Versionamento | **Sem campo `v` no MVP** (v1 implícito) |
| Limite de tamanho | 1 MiB do `ct` base64-decoded (relay rejeita maior) |
| Heartbeat | Qualquer lado pode iniciar `ping` após 25s de idle; outro responde `pong` |

---

## Outer envelope

```json
{ "peer": "string-peer-id", "ct": "<base64 do JSON inner>" }
```

**Semântica do campo `peer` (muda com o sentido do tráfego)**:

| Fase | Significado de `peer` |
|---|---|
| Mensagem **saindo** do peer (app/pi-ext → relay) | **destino** — quem deve receber |
| Mensagem **chegando** num peer (relay → app/pi-ext) | **remetente** — quem mandou |

Relay reescreve o campo `peer` antes de encaminhar: substitui o destino pelo
`peer_id` do remetente autenticado. Assim, quem recebe sabe imediatamente quem
mandou e pode responder usando o mesmo valor como destino na próxima mensagem.

Relay também:
- Valida que `peer` (destino, no envio) é um peer conectado
- Mede tamanho de `ct` base64-decoded (rejeita > 1 MiB)
- Encaminha pro outro peer pareado
- **Nunca** chama `JSON.parse(ct)` — payload é opaco ao roteamento
- Logs proibidos de incluir o conteúdo de `ct` (princípio mantido pós-rollback E2E)

`peer_id` é base64 STANDARD (RFC 4648 §4, com `+/=`) da Ed25519 pubkey de
longo prazo, idêntico ao que o peer enviou no `hello` do challenge-response
(ver `pairing.md`).

---

## Inner envelope — tipos do MVP

Como 1 pareamento = 1 sessão Pi, **não há `session_id`** em mensagem
nenhuma. Cada conexão peer↔peer já é exclusiva daquela sessão.

### Direção: app → extension (cliente)

| `type` | Campos | Espera resposta? |
|---|---|---|
| `pair_request` | `id`, `token`, `device_name` | Sim → `pair_ok` ou `pair_error` |
| `user_message` | `id`, `text` | Sim → stream de `agent_chunk` + `agent_done` |
| `approve_tool` | `id`, `tool_call_id`, `decision: "allow" \| "deny"` | Não (continua o fluxo) |
| `cancel` | `id`, `target_id` | Sim → `cancelled` ou `error` |
| `ping` | `id` | Sim → `pong` |

### Direção: extension → app (servidor)

| `type` | Campos | Iniciado por |
|---|---|---|
| `pair_ok` | `in_reply_to`, `session_name` | Resposta ao `pair_request` válido |
| `pair_error` | `in_reply_to`, `code`, `message` | Resposta ao `pair_request` inválido (ver `pairing.md`) |
| `agent_chunk` | `in_reply_to`, `delta` | Push streaming |
| `agent_done` | `in_reply_to`, `usage?` | Push terminal |
| `tool_request` | `tool_call_id`, `tool`, `args` | Push (espera `approve_tool`) |
| `tool_result` | `tool_call_id`, `result?`, `error?` | Push após approve |
| `error` | `in_reply_to?`, `code`, `message` | Qualquer falha não-pair |
| `cancelled` | `in_reply_to`, `target_id` | Push após cancel |
| `pong` | `in_reply_to` | Resposta ao ping |

---

## Erros — códigos canônicos

Erros do `error` genérico (qualquer momento pós-pair):

| `code` | Significado |
|---|---|
| `unknown_peer` | App tentou enviar pra peer não pareado (não está em `peers.json` do Pi) |
| `tool_approval_required` | Tool call esperando approval; tentar de novo após `approve_tool` |
| `invalid_message` | Inner envelope mal formado (JSON inválido ou campos faltando) |
| `unsupported_type` | `type` não reconhecido pelo receiver (forward-compat) |
| `too_large` | `ct` > 1 MiB no outer |
| `rate_limited` | Cliente excedeu rate limit |
| `timeout` | Operação interna excedeu prazo (ex: tool sem `approve_tool` em 60s) |
| `internal_error` | Falha não esperada no servidor; ver logs do Pi |

Erros específicos do `pair_error` (resposta a `pair_request`):

| `code` | Significado |
|---|---|
| `token_expired` | QR expirou (>60s desde geração) |
| `token_consumed` | Token já foi usado por outro `pair_request` |
| `token_unknown` | Token não foi emitido por este Pi |
| `internal_error` | Falha ao persistir peer |

`ErrorCode` é **aberto**: receivers devem tolerar codes desconhecidos
(tratar como genérico) para forward-compat.

---

## Fixtures

Pasta `fixtures/` carrega 1 exemplo JSONL por `type`. Cada subprojeto
roda seu codec contra esses arquivos pra garantir que o shape bate em TS,
Dart e Rust simultaneamente. Mudanças aqui são **breaking** — alinhar os
3 codecs antes de comitar.

Lista atual em `fixtures/` (13 arquivos):
- **Pair (novos no plano 06)**: `pair_request.jsonl`, `pair_ok.jsonl`, `pair_error.jsonl`
- **Client**: `user_message.jsonl`, `approve_tool.jsonl`, `cancel.jsonl`, `ping.jsonl`
- **Server**: `agent_stream.jsonl` (sequência de chunks + done), `tool_request.jsonl`, `tool_result.jsonl`, `error.jsonl`, `cancelled.jsonl`, `pong.jsonl`
