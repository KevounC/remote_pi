# Plano 06 — Rollback do E2E (Noise XX → plaintext sobre TLS)

## Contexto

O MVP não conseguiu atravessar o handshake Noise XX em ambiente real. Após
dezenas de bugs (BLAKE2b vs SHA-256, prologue ausente, base64 standard vs
url, buffer sizes do AEAD, roteamento de `peer`, duplo handshake pós-pair,
auto-listener competindo com PeerChannel), a cripto E2E virou o gargalo do
projeto — gastamos mais tempo depurando handshake do que entregando features.

**Decisão (2026-05-19, fechada em conversa)**: remover o E2E (Noise XX)
do MVP. Confiança contra o relay é coberta por:

1. **Relay é open-source e self-hostável** — usuário paranoico roda o próprio em VPN/Tailscale/etc. Garantia documentada no README.
2. **TLS 1.3 obrigatório no transporte** — quando o relay público for hospedado, vai atrás de WSS. Não há regressão contra atacante de rede.
3. **Challenge-response Ed25519** continua autenticando peers (impede squatting de identidade).

O que se perde: relay (operador) vê conteúdo das mensagens. **Aceito no MVP**
porque (a) MVP é beta fechado, (b) usuário sério hospeda o próprio relay,
(c) re-ativar Noise depois é aditivo (shape do protocolo permanece igual).

> Revisão prevista quando MVP fechar e produto for validado: avaliar se vale
> o esforço de religar Noise XX (provavelmente sim, mas com tooling de debug
> existente — wire dump + loopback test). Ver `Próximos planos`.

---

## Princípio

> O shape do outer envelope NÃO muda. Só o conteúdo de `ct` deixa de ser
> ciphertext e passa a ser **base64 do JSON do inner envelope em claro**.

Isso preserva:

- Toda a fixture de testes do `contracts/protocol.md`
- Toda a lógica do relay (que nunca decifrou nada de qualquer jeito)
- A possibilidade de religar Noise no futuro trocando apenas
  `PlainPeerChannel` por `NoisePeerChannel` — sem mexer em transporte,
  routing, ou inner schema

---

## Estrutura esperada

### Outer envelope (inalterado)

```json
{"peer": "<base64 ed25519 pk>", "ct": "<base64 JSON do inner>"}
```

`ct` = `base64(JSON.stringify(inner))`. Sem cifra, sem MAC, sem nonce.
Limite de 1 MiB mantido.

### Inner envelope (inalterado)

Mantém os 11 tipos atuais (`user_message`, `agent_chunk`, `tool_request`,
etc). **Adição**: 2 novos tipos pra o handshake de pareamento de
aplicação (substituem o Noise XX):

| `type` | Direção | Campos | Descrição |
|---|---|---|---|
| `pair_request` | app → pi | `id`, `token`, `device_name` | App apresenta token do QR + nome legível do device |
| `pair_ok` | pi → app | `in_reply_to`, `session_name` | Pi confirmou; pareamento persistido nos dois lados |
| `pair_error` | pi → app | `in_reply_to`, `code`, `message` | Token inválido/consumido/expirado (códigos do `pairing.md`) |

Sem `safety number` — não há derivação criptográfica bilateral pra mostrar.

### QR payload (simplificado)

| Campo | Tipo | Mudança |
|---|---|---|
| `t` | base64url 16B token efêmero | **mantém** |
| `pk` | base64url 32B Curve25519 | **REMOVIDO** (era pra Noise XX) |
| `epk` | base64url 32B Ed25519 | **mantém** — vira o único peer ID |
| `r` | relay URL | **mantém** |
| `n` | session name | **mantém** |

### Storage (simplificado)

App Keychain por pareamento — **mantém só Ed25519 do Pi e nome**:

```json
{
  "remote_epk": "<base64>",
  "session_name": "...",
  "relay_url": "...",
  "paired_at": "..."
}
```

Singleton Ed25519 do device: **mantém** (pra auth no relay).

Pi `peers.json` — **mantém só Ed25519 do app, nome e timestamp**.

---

## O que SAI do código

### `pi-extension/`
- `src/pairing/noise-sha256.ts` — DELETE
- `src/pairing/handshake.ts` — DELETE (substituído por validador de token simples)
- `src/pairing/crypto.ts` — manter só helpers Ed25519; remover X25519, HKDF, emoji
- `src/transport/peer_channel.ts` → reescrever como `PlainPeerChannel` (sem ChaCha)
- `src/vendor.d.ts` — DELETE
- `tools/noise_xx_diag.ts` — DELETE
- `src/extension.test.ts` — remover testes de Noise/handshake; manter pair_request flow
- `package.json` — remover dep `noise-protocol`

### `app/`
- `lib/pairing/noise.dart` — DELETE
- `lib/pairing/handshake.dart` — substituir por `pair_request_flow.dart` enxuto
- `lib/pairing/crypto.dart` — manter Ed25519; remover X25519, HKDF, deriveSafetyBytes, emoji alphabet (256 const)
- `lib/data/transport/peer_channel.dart` → reescrever como `PlainPeerChannel`
- `lib/ui/pairing/widgets/safety_number_card.dart` (se existir) — DELETE
- `lib/ui/pairing/` — remover tela de confirmação de safety; ir direto pra paired
- `tools/noise_xx_diag.dart` — DELETE
- `pubspec.yaml` — manter `cryptography` (ainda usado pra Ed25519); reavaliar depois

### `relay/`
- **Nenhuma mudança.** Relay já só roteia `{peer, ct}` opaco e faz auth Ed25519. Continua funcionando idêntico.

### `.orchestration/contracts/`
- `pairing.md` — reescrever (Wave 0): remover Noise XX, safety number, X25519, dois-pubkeys; adicionar `pair_request`/`pair_ok` flow
- `protocol.md` — atualizar (Wave 0): semântica de `ct` vira "base64 do JSON inner em claro" sem nota de "futuro Noise"; adicionar 3 novos tipos (`pair_request`, `pair_ok`, `pair_error`)
- `emoji_alphabet_256.txt` — DELETE
- `fixtures/` — adicionar `pair_request.jsonl`, `pair_ok.jsonl`, `pair_error.jsonl`

---

## Passos com critério de aceite

### Wave 0 — Contratos (sequencial, prerequisito de tudo)

Atualizar os 3 arquivos de contrato. **Tudo orquestrador-only** (não despacha pra agente).

- [x] Reescrever `.orchestration/contracts/pairing.md` no shape novo (sem Noise)
- [x] Atualizar `.orchestration/contracts/protocol.md` adicionando 3 tipos
- [x] Apagar `.orchestration/contracts/emoji_alphabet_256.txt`
- [x] Adicionar 3 fixtures: `pair_request.jsonl`, `pair_ok.jsonl`, `pair_error.jsonl`

**Aceite Wave 0**: os 4 itens acima feitos, e os contratos lidos pelo usuário pra confirmar antes da Wave 1.

### Wave 1 — Subprojetos em paralelo (3 despachos)

Cada agente recebe o link pros contratos atualizados como única fonte de verdade.

#### W1.A — pi-extension
- [x] Deletar arquivos Noise listados acima
- [x] Reescrever `src/transport/peer_channel.ts` como `PlainPeerChannel`
- [x] Reescrever fluxo de pair em `src/index.ts`
- [x] Atualizar testes (`src/extension.test.ts`) — remover Noise/handshake suites; adicionar suite `pair_request flow`
- [x] Remover `noise-protocol` do `package.json` + `pnpm-lock.yaml`
- [x] `pnpm typecheck && pnpm build && pnpm test` → tudo verde (49 tests)

#### W1.B — app
- [x] Deletar arquivos Noise listados acima
- [x] Substituir `lib/pairing/handshake.dart` por `pair_request_flow.dart` enxuto
- [x] Reescrever `lib/data/transport/peer_channel.dart` como `PlainPeerChannel`
- [x] Remover `lib/ui/pairing/widgets/safety_number_card.dart` (não existia — equivalente em pairing_page.dart removido)
- [x] Atualizar `PairingViewModel`: pular state de safety; após `pair_ok`, adotar canal direto
- [x] Reduzir `lib/pairing/crypto.dart` — manter só Ed25519 (168 → 32 linhas)
- [x] `flutter analyze && flutter test` → tudo verde (65 tests)

#### W1.C — relay
- [x] Confirmar que `relay/` não precisa de nenhuma mudança (smoke test passou)
- [x] Atualizar comentários ou docstrings que mencionem "ciphertext Noise" → "payload base64 opaco"
- [x] `cargo build && cargo test` → verde (10 tests)

### Wave 2 — Roundtrip manual

- [x] Build + start dos 3 lados
- [x] Pareamento via QR funciona end-to-end → estado `paired` no Pi e tela de chat no app
- [x] `user_message` do app aparece no Pi (já em modo `pi.sendUserMessage`)
- [x] `agent_chunk` streaming chega no app
- [x] `tool_request` (Bash) → approval card no app → `tool_result`
- [x] Pi fecha (`/remote-pi stop`) → app vê offline em <5s
- [x] App fecha → Pi continua em `started`; app reabre e reconecta sem novo QR (auto-listener no Pi aceita peer conhecido)

### Wave 3 — Limpeza final

- [ ] Atualizar `plan/03-protocol.md` DoD adicionando os 3 novos tipos
- [ ] Atualizar `plan/04-pairing.md` marcando como "rollback executado pelo plano 06"
- [ ] Atualizar `plan/05-mvp-features.md` DoD pendente (roundtrip)
- [ ] Atualizar `README.md` raiz: parágrafo "Modelo de confiança" — mencionar que relay vê conteúdo no MVP e que produção self-hosta
- [ ] Commit único cobrindo o rollback (segregado por subprojeto se for grande)

---

## Definition of Done

- [x] Wave 0 — 3 contratos atualizados + 3 fixtures novas
- [x] Wave 1.A — pi-ext sem Noise, todos testes passando (49 ✓)
- [x] Wave 1.B — app sem Noise, todos testes passando (65 ✓)
- [x] Wave 1.C — relay confirmado intacto (10 ✓)
- [x] Wave 2 — roundtrip manual 100% verde (pareamento + chat + approval + reconnect)
- [ ] Wave 3 — planos antigos sinalizados + README atualizado
- [x] Tasks #46, #47, #48, #49 marcadas como obsoletas (substituídas por este plano)

---

## Próximos planos

- **`plan/07-relay-deploy.md`** — onde hospedar o relay público (decisão "Em aberto" no 00-decisions). Inclui TLS 1.3 + cert pinning no app — agora ÚNICA camada de proteção contra MITM externo.
- **`plan/08-revoke-multi-session.md`** — revoke + suporte a múltiplos pareamentos por device.
- **`plan/09-e2e-restore.md`** *(opcional)* — religar Noise XX **com** ferramental adequado (loopback test + wire dump replay + lockstep log). Pré-requisito: MVP estável por 2+ semanas em uso real. Não bloquear MVP nele.

---

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Bug B do app (duplo-disparo pós-pair) persistir | Sem Noise o sintoma muda: app pode mandar `pair_request` duas vezes — Pi deve idempotentemente ignorar a segunda (token já consumido → `pair_error{code: token_consumed}`). Validar no test manual da Wave 2 |
| Relay público (futuro) leakar conteúdo via logs | README explícito + linter no código do relay rejeitando `tracing::info!` que inclua `ct` |
| Usuário sério achar "MVP sem E2E" inaceitável e abandonar | Mitigação dupla: (a) README destaca self-host trivial, (b) plano 09 documentado como roadmap claro pra ativar E2E |
| Bug 49 (investigação do app) virar lixo | Reaproveitar diagnóstico pra ajustar `ConnectionManager.adopt` mesmo sem Noise — investigação não foi desperdício |

---

## Por que este plano NÃO é redundante com o 04

O plano 04 *implementou* o E2E e parou no Wave 2 (roundtrip integrado).
O plano 06 *reverte* aquele Wave 2 + Wave 1 do 04, redesenhando o
contrato de pareamento sem cripto. **Não apaga** os arquivos do plano 04
do `plan/` — eles continuam como registro histórico. Marcação textual
("rollback executado pelo plano 06") preserva o histórico de decisões.
