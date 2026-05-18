# Plano 03 — Protocolo de mensagens

Objetivo: definir e implementar (em stubs) o protocolo de mensagens trafegado entre **app** (Flutter) e **pi-extension** (Node) através do **relay** (Rust). O relay vê só o envelope externo opaco; toda semântica vive no envelope interno entre app e extensão.

**Este plano não cobre criptografia.** O envelope externo terá um campo `ct` (ciphertext), mas neste plano `ct` é um placeholder em base64 do JSON em claro. A cifra real (Curve25519 + ChaCha20-Poly1305 / Noise) entra no plano 04 (pareamento). Isso permite implementar e testar o **shape** do protocolo sem bloquear em crypto.

---

## Contexto

Pi expõe `AgentSession`, `SessionManager`, `ModelRegistry` como APIs públicas. O `pi-extension` consome essas APIs e traduz para mensagens estruturadas. O `app` envia/recebe essas mesmas mensagens. O `relay` só roteia.

Para os 3 subprojetos não divergirem, a **fonte de verdade** vira `.orchestration/contracts/protocol.md`. Cada subprojeto implementa tipos derivados desse contrato. Mudanças no contrato disparam tarefas de realinhamento nos 3 lados.

Este é o primeiro plano que **toca múltiplos subprojetos simultaneamente** — gatilho natural pra ativar o overlay `.orchestration/`.

---

## Decisões fixadas (não revisitar a menos que apareça evidência forte)

| Decisão | Valor | Justificativa |
|---|---|---|
| Framing | **JSONL** (LF-delimited, `\n`) | Mesmo formato que o Pi RPC mode já usa. UTF-8 |
| Envelope externo | `{ "peer": "<id>", "ct": "<base64>" }` | Único contrato que o relay enxerga |
| Envelope interno | `{ "type": "<kind>", "id": "<uuid>", ...payload }` | Discriminated union por `type` |
| ID de correlação | UUIDv7 (string) em qualquer mensagem que espera resposta | Ordenável temporalmente; mais útil que UUIDv4 pra logs |
| `in_reply_to` | Campo opcional em respostas, ecoa `id` da request | Cliente correlaciona |
| Encoding | UTF-8 estrito | |
| Versionamento | **Sem campo `v` no MVP** | v1 implícito. Adicionar `v` quando v2 surgir e cobrir migração |
| Limite de tamanho | 1 MiB por mensagem inner (decidido aqui) | Suficiente pra diffs gordos; relay rejeita maior |
| Erros | Tipo `error` com `code`, `message`, opcional `in_reply_to` | |
| Heartbeat | Cliente envia `ping` a cada 25s, servidor responde `pong` | WebSocket idle timeout em CDN típico é 60s |

---

## Estrutura final esperada após este plano

```
remote_pi/
├── .orchestration/                            ← novo
│   ├── INSTRUCTIONS.md                        ← passo 1
│   └── contracts/
│       ├── protocol.md                        ← passo 2 (fonte de verdade)
│       └── fixtures/                          ← passo 2
│           ├── user_message.jsonl
│           ├── list_sessions.jsonl
│           ├── tool_request.jsonl
│           └── ...
├── pi-extension/
│   └── src/protocol/                          ← passo 3
│       ├── types.ts                           ← discriminated union
│       ├── codec.ts                           ← encode/decode + validação
│       └── codec.test.ts                      ← roundtrip + fixtures
├── app/
│   └── lib/protocol/                          ← passo 4
│       ├── protocol.dart                      ← sealed classes
│       ├── codec.dart                         ← encode/decode
│       └── (test em app/test/protocol_test.dart)
└── relay/
    └── src/protocol/                          ← passo 5
        ├── mod.rs
        ├── outer.rs                           ← OuterEnvelope (peer + ct)
        └── outer_test.rs                      ← parse de framing JSONL
```

---

## Passo 1 — Overlay `.orchestration/` + `INSTRUCTIONS.md`

**Função**: ativa o modo orquestrado. Os 4 CLAUDE.md de subprojeto já têm o gatilho `[ORCH:<id>]` apontando para este arquivo.

**Localização**: `.orchestration/INSTRUCTIONS.md`

**Conteúdo mínimo**:

```markdown
# Orchestration overlay

Você está em modo orquestrado se o prompt começou com `[ORCH:<task-id>]`.
Em modo solo (sem marker), ignore este arquivo.

## Regras

1. Trabalhe **apenas no seu subprojeto** (seu cwd)
2. Trate `.orchestration/contracts/` como **read-only**. Mudanças de contrato
   vêm de uma task explícita, nunca no meio de outra
3. Não rode `git commit` — o orquestrador comita por wave
4. Mate dev servers/watchers que você iniciou antes de encerrar
5. Não escreva fora do seu cwd e fora de `.orchestration/results/` (quando
   existir)

## Onde achar contratos cross-project

- `contracts/protocol.md` — formato das mensagens app ↔ extension
- `contracts/fixtures/*.jsonl` — exemplos canônicos para teste roundtrip

Outros workers podem estar rodando em paralelo. Não assuma exclusividade
sobre arquivos fora do seu cwd.
```

**Critério de aceite**:
- `.orchestration/INSTRUCTIONS.md` existe
- Linkado dos 4 CLAUDE.md de subprojeto (já está, do plano 02)

---

## Passo 2 — `contracts/protocol.md` + fixtures

**Função**: especificação canônica. Toda mudança de protocolo passa por aqui primeiro.

**Localização**: `.orchestration/contracts/protocol.md`

**Conteúdo do `protocol.md`**:

### Camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│  Inner envelope (app ↔ pi-extension)                                  │
│  Semântica do produto. Cifrado E2E.                                   │
│  Schema: { type, id?, in_reply_to?, ...payload }                      │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  cifrado (plano 04 cobre)
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Outer envelope (relay)                                               │
│  Roteamento puro. Nada de payload visível.                            │
│  Schema: { peer: "<id>", ct: "<base64>" }                             │
└──────────────────────────────────────────────────────────────────────┘
                              ▲
                              │  framing JSONL (\n)
                              ▼
                          WebSocket
```

### Outer envelope

```json
{ "peer": "string-peer-id", "ct": "<base64 do inner serializado>" }
```

Único formato que o relay parseia. Não há outros campos. Relay:
- Valida que `peer` é um peer conectado
- Calcula tamanho de `ct` (rejeita > 1 MiB)
- Encaminha pro outro peer pareado
- **Nunca** abre `ct`

### Inner envelope — tipos mínimos pro MVP

#### Direção: app → extension

| `type` | Campos | Espera resposta? |
|---|---|---|
| `list_sessions` | `id` | Sim → `session_list` |
| `open_session` | `id`, `session_id` | Sim → `session_history` |
| `switch_session` | `id`, `session_id` | Sim → `active_session_changed` ou `error` |
| `user_message` | `id`, `text` | Sim → stream de `agent_chunk` + `agent_done` |
| `approve_tool` | `id`, `tool_call_id`, `decision: "allow"\|"deny"` | Não (continua o fluxo) |
| `cancel` | `id`, `target_id` | Sim → `cancelled` ou `error` |
| `ping` | `id` | Sim → `pong` |

#### Direção: extension → app

| `type` | Campos | Iniciado por |
|---|---|---|
| `session_list` | `in_reply_to`, `sessions: [{ id, title, last_activity, is_live, owner_pid? }]` | Resposta |
| `session_history` | `in_reply_to`, `session_id`, `entries: [...]` | Resposta |
| `active_session_changed` | `session_id` | Push ou resposta |
| `agent_chunk` | `in_reply_to`, `delta` | Push streaming |
| `agent_done` | `in_reply_to`, `usage?` | Push terminal |
| `tool_request` | `tool_call_id`, `tool`, `args` | Push (espera `approve_tool`) |
| `tool_result` | `tool_call_id`, `result?`, `error?` | Push após approve |
| `error` | `in_reply_to?`, `code`, `message` | Qualquer falha |
| `cancelled` | `in_reply_to`, `target_id` | Push após cancel |
| `pong` | `in_reply_to` | Resposta ao ping |

### Exemplos (fixtures que cada subprojeto consome)

`contracts/fixtures/user_message.jsonl`:
```json
{"type":"user_message","id":"018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6b","text":"por que o token expira antes da hora?"}
```

`contracts/fixtures/agent_chunk.jsonl` (sequência):
```json
{"type":"agent_chunk","in_reply_to":"018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6b","delta":"Vou olhar o "}
{"type":"agent_chunk","in_reply_to":"018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6b","delta":"middleware..."}
{"type":"agent_done","in_reply_to":"018f9c2a-7b1e-7000-9a3b-1c2d3e4f5a6b","usage":{"input_tokens":120,"output_tokens":340}}
```

`contracts/fixtures/tool_request.jsonl`:
```json
{"type":"tool_request","tool_call_id":"tc_018f9c2b","tool":"Bash","args":{"command":"rm -rf node_modules"}}
{"type":"approve_tool","id":"018f9c2c-...","tool_call_id":"tc_018f9c2b","decision":"deny"}
```

(Lista completa: 1 fixture por `type` listado, ~12 arquivos)

### Erros — códigos canônicos

| `code` | Significado |
|---|---|
| `unknown_session` | `session_id` não existe no scope |
| `session_locked` | Sessão está ativa em outro processo Pi |
| `not_active_session` | Tentou mandar `user_message` numa sessão não-ativa |
| `tool_approval_required` | Tool call esperando approval; tentar de novo após `approve_tool` |
| `invalid_message` | Inner envelope mal formado |
| `too_large` | `ct` > 1 MiB no outer |
| `rate_limited` | Cliente excedeu rate limit |

**Critério de aceite**:
- `protocol.md` existe com seções acima
- `contracts/fixtures/*.jsonl` tem pelo menos 1 exemplo por `type` (∼12 arquivos)
- Lint mental: cada `type` aparece exatamente uma vez como chave de tabela

---

## Passo 3 — Stub TypeScript (`pi-extension/src/protocol/`)

**Função**: tipos + codec em TS que cobre o inner envelope. Sem networking ainda.

**Localização**: `pi-extension/src/protocol/`

### Arquivos

**`types.ts`** — discriminated union:
```typescript
export type ClientMessage =
  | { type: "list_sessions"; id: string }
  | { type: "open_session"; id: string; session_id: string }
  | { type: "switch_session"; id: string; session_id: string }
  | { type: "user_message"; id: string; text: string }
  | { type: "approve_tool"; id: string; tool_call_id: string; decision: "allow" | "deny" }
  | { type: "cancel"; id: string; target_id: string }
  | { type: "ping"; id: string };

export type ServerMessage =
  | { type: "session_list"; in_reply_to: string; sessions: SessionSummary[] }
  | { type: "session_history"; in_reply_to: string; session_id: string; entries: unknown[] }
  | { type: "active_session_changed"; session_id: string }
  | { type: "agent_chunk"; in_reply_to: string; delta: string }
  | { type: "agent_done"; in_reply_to: string; usage?: Usage }
  | { type: "tool_request"; tool_call_id: string; tool: string; args: unknown }
  | { type: "tool_result"; tool_call_id: string; result?: unknown; error?: string }
  | { type: "error"; in_reply_to?: string; code: ErrorCode; message: string }
  | { type: "cancelled"; in_reply_to: string; target_id: string }
  | { type: "pong"; in_reply_to: string };

export type SessionSummary = {
  id: string;
  title: string;
  last_activity: string; // ISO-8601
  is_live: boolean;
  owner_pid?: number;
};

export type Usage = { input_tokens: number; output_tokens: number };

export type ErrorCode =
  | "unknown_session"
  | "session_locked"
  | "not_active_session"
  | "tool_approval_required"
  | "invalid_message"
  | "too_large"
  | "rate_limited";
```

**`codec.ts`** — encode/decode com narrow guard:
```typescript
export function encodeClient(msg: ClientMessage): string {
  return JSON.stringify(msg) + "\n";
}

export function decodeServer(line: string): ServerMessage {
  const obj = JSON.parse(line);
  // narrow guard: rejeita se !type ou type fora do union conhecido
  return obj as ServerMessage;
}
```

**`codec.test.ts`** — roundtrip + fixtures:
```typescript
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const fixtureDir = join(__dirname, "../../../.orchestration/contracts/fixtures");

for (const file of readdirSync(fixtureDir)) {
  test(`decode ${file}`, () => {
    const content = readFileSync(join(fixtureDir, file), "utf8");
    for (const line of content.split("\n").filter(Boolean)) {
      const decoded = JSON.parse(line);
      expect(typeof decoded.type).toBe("string");
    }
  });
}
```

**Dependência nova**: `vitest` ou `node:test` built-in. Usar `node:test` pra evitar dep nova:
```bash
cd pi-extension
# Adicionar script "test": "node --test src/**/*.test.ts" no package.json
```

**Critério de aceite**:
- `pnpm typecheck` passa
- `pnpm build` gera os tipos
- `pnpm test` (a configurar) roda contra fixtures e cada uma desserializa
- TypeScript reclama em compile-time se omitir um campo obrigatório

---

## Passo 4 — Stub Dart (`app/lib/protocol/`)

**Função**: tipos + codec equivalentes, no app.

**Localização**: `app/lib/protocol/`

### Estrutura

**`protocol.dart`** — sealed classes:
```dart
sealed class ClientMessage {
  Map<String, dynamic> toJson();
}

class UserMessage extends ClientMessage {
  final String id;
  final String text;
  UserMessage({required this.id, required this.text});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user_message',
    'id': id,
    'text': text,
  };
}

// ... outras 6 ClientMessage subclasses

sealed class ServerMessage {
  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'session_list':
        return SessionList.fromJson(json);
      case 'agent_chunk':
        return AgentChunk.fromJson(json);
      // ... demais
      default:
        throw FormatException('unknown server type: ${json['type']}');
    }
  }
}

// ... subclasses
```

**`codec.dart`** — encode/decode:
```dart
String encodeClient(ClientMessage m) => '${jsonEncode(m.toJson())}\n';

ServerMessage decodeServer(String line) =>
    ServerMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
```

**Test** (`app/test/protocol_test.dart`):
```dart
void main() {
  test('decode fixtures', () async {
    final dir = Directory('../.orchestration/contracts/fixtures');
    await for (final f in dir.list()) {
      final lines = await File(f.path).readAsLines();
      for (final line in lines.where((l) => l.isNotEmpty)) {
        // só verifica que parseia
        final msg = decodeServer(line);
        expect(msg, isNotNull);
      }
    }
  });
}
```

**Critério de aceite**:
- `flutter analyze` zero issues
- `flutter test` passa (pelo menos 1 teste novo)
- Sealed switch é exhaustive (compilador reclama se faltar caso)

---

## Passo 5 — Outer envelope no relay (Rust)

**Função**: relay sabe parsear o outer envelope. **Nunca** abre o `ct`.

**Localização**: `relay/src/protocol/`

### Estrutura

**`mod.rs`**:
```rust
pub mod outer;
```

**`outer.rs`**:
```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OuterEnvelope {
    pub peer: String,
    pub ct: String, // base64 — nunca decodificado aqui
}

pub const MAX_CT_BYTES: usize = 1024 * 1024; // 1 MiB

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("invalid json: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("payload too large: {0} bytes (max {1})")]
    TooLarge(usize, usize),
}

pub fn parse_line(line: &str) -> Result<OuterEnvelope, ParseError> {
    let env: OuterEnvelope = serde_json::from_str(line)?;
    let estimated = env.ct.len() * 3 / 4; // base64 → bytes aproximado
    if estimated > MAX_CT_BYTES {
        return Err(ParseError::TooLarge(estimated, MAX_CT_BYTES));
    }
    Ok(env)
}
```

**Adicionar deps**:
```bash
cd relay
cargo add thiserror
cargo add base64
```

**`outer_test.rs`** (ou inline `#[cfg(test)]`):
```rust
#[test]
fn parses_minimal_envelope() {
    let line = r#"{"peer":"abc","ct":"AAA="}"#;
    let env = parse_line(line).unwrap();
    assert_eq!(env.peer, "abc");
}

#[test]
fn rejects_too_large() {
    let big = "A".repeat(2 * 1024 * 1024);
    let line = format!(r#"{{"peer":"abc","ct":"{}"}}"#, big);
    assert!(matches!(parse_line(&line), Err(ParseError::TooLarge(..))));
}
```

**Critério de aceite**:
- `cargo build` passa
- `cargo test` 2+ testes passam
- `cargo clippy -- -D warnings` zero
- **Confirmação visual**: nada no relay decodifica `ct`. Só `serde_json::from_str` no envelope externo

---

## Passo 6 — Cross-language fixture round-trip

**Função**: garantia mecânica que TS e Dart decodificam o mesmo bytes pra estruturas equivalentes.

**Como funciona**:

1. `contracts/fixtures/*.jsonl` é a fonte de verdade
2. `pi-extension/src/protocol/codec.test.ts` itera todas as fixtures, decodifica, valida `type`
3. `app/test/protocol_test.dart` faz o mesmo
4. Quando uma fixture muda, ambos os testes refletem

Não há comparação automatizada cross-linguagem no MVP. A confiança vem de:
- Ambos lados decodificam mesmo JSON sem erro
- Schema canônico no protocol.md serve de referee em PR review

**Critério de aceite**:
- Os 2 test suites (TS + Dart) leem do mesmo `fixtures/` e passam
- Mudança numa fixture quebra ambos os testes ao mesmo tempo

---

## Definition of Done

- [ ] `.orchestration/INSTRUCTIONS.md` existe e está coerente com gatilho `[ORCH:]` nos CLAUDE.md
- [ ] `.orchestration/contracts/protocol.md` cobre outer + inner + todos os tipos listados
- [ ] `.orchestration/contracts/fixtures/` tem 1 fixture por `type` (≥ 12 arquivos)
- [ ] `pi-extension/src/protocol/{types,codec,codec.test}.ts` implementados
- [ ] `pnpm test` rodando no pi-extension (script novo) e passando contra fixtures
- [ ] `app/lib/protocol/{protocol,codec}.dart` implementados, sealed switch exhaustive
- [ ] `app/test/protocol_test.dart` passa contra mesmas fixtures
- [ ] `relay/src/protocol/outer.rs` parseia outer envelope, rejeita > 1 MiB
- [ ] `cargo test` no relay passa (2+ tests)
- [ ] `cargo clippy -- -D warnings` zero no relay
- [ ] Commit: `protocol: outer + inner envelopes, JSONL framing, fixtures`

---

## Notas de execução

1. **Ordem sugerida**: passo 1 → 2 (overlay + contrato) → 5 (relay, mais isolado) → 3 e 4 em paralelo (TS e Dart consomem o mesmo `contracts/`)
2. **Modo orquestrado real**: este é o plano onde vale testar o gatilho `[ORCH:<id>]`. Tarefa típica:
   - Wave 0: orquestrador escreve `contracts/protocol.md` (humano + Claude raiz)
   - Wave 1: tasks paralelas `[ORCH:03-ts-codec]`, `[ORCH:03-dart-codec]`, `[ORCH:03-rust-outer]`
   - Cada worker lê `INSTRUCTIONS.md` + `contracts/protocol.md`, implementa, marca seu DoD
3. **Crypto fica de fora**: `ct` é base64 do JSON em claro neste plano. Quando o plano 04 ativar Noise/libsodium, só o "encrypt-then-base64" muda — schema permanece
4. **Não adicionar features de produto**: lista de sessões vazia, chat sem efeito, approval sem tool real. O objetivo é o **shape**, não comportamento end-to-end

---

## Próximos planos

- **`04-pairing.md`** — pareamento por QR. Noise XX ou libsodium direto, Curve25519, ChaCha20-Poly1305. Substitui o base64-em-claro do `ct` por cifra real. Define formato do QR (relay URL + token + pubkey efêmera + safety number)
- **`05-mvp-features.md`** — fluxo end-to-end real: pi-extension consome `AgentSession`, mensagens fluem, app exibe streaming, approval funciona
- **`06-relay-deploy.md`** — onde rodar o relay, TLS, custos, self-host instruções
- **`07-protocol-consistency-subagent.md`** — subagent na raiz que valida que TS, Dart e Rust ainda batem com `contracts/protocol.md` (gatilho do plano 02, passo 6, quando o protocolo estabilizar)
