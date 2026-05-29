# Remote Pi — Protocol & Security

Documentação canônica do protocolo Remote Pi e do modelo de proteção.
Atualizada em 2026-05-24.

---

## Visão de 30 segundos

- **Mesh de agentes coding** rodando em múltiplos PCs do mesmo usuário
- **Cada PC** roda o `pi-extension` (Node.js daemon) com **uma Pi-key** Ed25519 no Keychain do sistema (macOS/Linux/Windows)
- **Celular** é o **autenticador inicial** (estilo WhatsApp Web QR) — depois do pareamento, PCs operam autonomamente entre si
- **Owner-key** Ed25519 vive no Keychain do celular (iOS Keychain / Android Block Store), sincroniza entre devices do mesmo Apple ID / Google Account
- **Relay** WebSocket roteia ciphertext + armazena `mesh_versions` assinadas pelo Owner — nunca decide membership, sempre verifica assinaturas
- **Cross-PC routing** via prefix `<pc>:<peer>` no envelope; broker UDS local em cada PC, relay forward Pi-to-Pi via WS

---

## Identidades

| Chave | Algoritmo | Onde mora | Quem cria | Quem usa |
|---|---|---|---|---|
| **Owner-key** | Ed25519 | iOS Keychain (sync iCloud) / Android Block Store (sync Google) | App mobile no 1º boot | Assina `mesh_versions`, prova autoridade pra parear/revogar PCs |
| **Pi-key** | Ed25519 | `@napi-rs/keyring` no PC (Keychain macOS / libsecret Linux / Credential Manager Windows). Fallback `~/.pi/remote/identity.json` (`0600`) com warning em sistemas headless | pi-extension no 1º boot | Autentica WS pro relay, assina envelopes cross-PC |
| **App-key** | Ed25519 efêmera | RAM do app mobile | App por sessão de pareamento | Establishment de canal autenticado durante pair |

**Constraint fixada**: "1 Pi-key por PC; troca de hardware = re-pareamento". Não há migração de Pi-key entre máquinas. Owner-key compensa (Owner sincroniza cross-device via Keychain do sistema).

---

## Camadas do protocolo

```
┌─────────────────────────────────────────────────────────────────────┐
│  Agent layer       Pi coding agent (futuro: Claude Code, OpenCode)  │
├─────────────────────────────────────────────────────────────────────┤
│  Envelope          {from, to, id, re, body}  — JSONL 5 campos       │
├─────────────────────────────────────────────────────────────────────┤
│  Routing           Local UDS broker  /  Cross-PC via relay forward  │
│                    Prefix <pc>:<peer> distingue local vs remoto     │
├─────────────────────────────────────────────────────────────────────┤
│  ACK protocol      received | busy | denied | timeout               │
│                    Wrapper TS responde sem custar token              │
├─────────────────────────────────────────────────────────────────────┤
│  Transport         UDS (local)  /  WebSocket sobre TLS (relay)      │
├─────────────────────────────────────────────────────────────────────┤
│  Trust             Ed25519 challenge-response                       │
│                    Owner-sig em mesh_versions                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Envelope

Formato único pra todo o sistema. Funciona local (UDS) e cross-PC (relay forward).

```json
{
  "from": "<sender-name>",
  "to": "<recipient-name>" | ["<r1>", "<r2>"] | "broadcast",
  "id": "<UUID v7>",
  "re": "<id-of-message-being-replied-to>" | null,
  "body": <any JSON>
}
```

Naming:
- **Local**: nome simples (`sess-3`, `agent-2`, `broker`)
- **Cross-PC**: prefixado com `pc_label` do destino (`casa:sess-3`, `trab:agent-1`)
- Quando entra no broker local destino, o prefix é stripped (sessão local não sabe seu próprio pc_label)

UUID v7 garante ordenação temporal sem coordenação.

---

## ACK protocol

Toda chamada de `agent_send` aguarda um ACK rápido (default 5s) gerado pelo **wrapper TypeScript** do peer destino — não pelo LLM. Custo: microsegundos local, milissegundos cross-PC.

| Status | Significado |
|---|---|
| `received` | Peer está livre e vai processar; mensagem enfileirada |
| `busy` | Peer está em meio a um turn; mensagem **descartada**, sender retry |
| `denied` | Peer recusou (futuro: blacklist); abandona |
| `timeout` | ACK não chegou em 5s; trata como transport error |
| `transport_error` | Cross-PC apenas: relay reportou `offline`, `not_authorized`, ou `bad_envelope` |

**Reply de conteúdo** é assíncrona: peer responde com **outro send normal** carregando `re: <send-id-original>`. Sender vê a reply na inbox no próximo turn. Sem `agent_wait`, sem `agent_request` — padrão event-driven puro.

Detalhes em `plan/25-pc-mesh-bootstrap.md` seção "ACK protocol".

---

## Cross-PC routing

Hoje cross-PC é mediado pelo relay (não P2P direto — fica pra futuro).

### Frame wire WS (Pi-A → Relay)

```json
{
  "type": "pi_envelope",
  "to_pc": "<pi-b-pubkey-base64>",
  "envelope": { "from": "casa:sess-3", "to": "trab:agent-1", ... }
}
```

### Frame entregue pelo relay (Relay → Pi-B)

```json
{
  "type": "pi_envelope_in",
  "from_pc": "<pi-a-pubkey-base64>",
  "envelope": { ... }
}
```

### Autorização (relay-side)

Antes de forwardar, relay consulta `mesh_versions`:
- Pi-A e Pi-B estão na lista do **mesmo Owner**? Forward
- Em Owners diferentes? `transport_error: not_authorized`
- Pi-B sem WS ativa? `transport_error: offline`

Cache TTL 60s indexado por Pi-pubkey → set de irmãos.

### Anti-spoof (broker-side)

Quando Pi-B recebe `pi_envelope_in`:
- `from_pc` é ground truth técnico (pubkey verificada pelo relay)
- `envelope.from` é address legível
- Anti-spoof: `envelope.from` deve começar com prefix matching o `pc_label` correspondente a `from_pc` (lookup via siblings cache). Se não bate → drop + log

### Transport errors como envelope

Erros não são frames WS custom — são envelopes normais com `from: "_relay"` + `body.type: "transport_error"`. Sender correlaciona via `re: <envelope-id>`. Mesma máquina ACK trata.

---

## Mesh membership

`mesh_versions` é o "cartório" assinado pelo Owner.

### Estrutura

```json
{
  "version": 7,
  "owner_pk": "<base64 standard, 32B>",
  "members": [
    { "pc_pubkey": "<base64>", "nickname": "casa", "paired_at": "2026-05-22T..." },
    { "pc_pubkey": "<base64>", "nickname": "trab", "paired_at": "2026-05-23T..." }
  ],
  "sig": "<Ed25519(canonical_json) by owner_sk>"
}
```

### Storage

Relay armazena o blob inteiro em SQLite, indexado por `owner_pk_hash = SHA256(owner_pk)`.

- **POST /mesh/<hash>**: cliente publica nova versão (relay verifica assinatura + version monotônica)
- **GET /mesh/<hash>**: cliente lê última versão; valida assinatura localmente

LWW (last-write-wins) em conflito concorrente. Anti-rollback via version monotônica.

### Self-revoke

Pi-extension faz polling periódico. Se sua Pi-pubkey saiu de `members`, faz self-revoke (sai do mesh) graciosamente.

Detalhes em `plan/24-mesh-membership.md`.

---

## Slash commands

Camada acima do envelope. O app expõe um picker de slash commands (`/compact`, `/model`, comandos `/remote-pi …`, etc.) que listam o catálogo do Pi pareado e invocam comandos curados como se o usuário tivesse digitado no TUI.

### Request — `list_commands`

```json
{ "type": "list_commands", "id": "<uuid>" }
```

### Reply — `commands_list`

```json
{
  "type": "commands_list",
  "in_reply_to": "<uuid>",
  "commands": [
    { "name": "compact", "description": "Manually compact context", "source": "builtin",   "invokable": true,  "takes_args": false },
    { "name": "model",   "description": "Select model",             "source": "builtin",   "invokable": true,  "takes_args": true  },
    { "name": "fork",    "description": "Fork from previous user message", "source": "builtin", "invokable": false, "takes_args": false },
    { "name": "remote-pi", "description": "Mesh control",           "source": "extension", "invokable": true,  "takes_args": true  }
  ]
}
```

`source ∈ {builtin, extension, prompt, skill}`. `invokable: false` marca comandos que existem no Pi mas só funcionam na TUI hoje — o app os mostra como hint informativo (grayed). Razão da limitação: o SDK do Pi `@mariozechner/pi-coding-agent` não expõe API programática genérica de invocação de builtins; só alguns têm equivalente em `ExtensionContextActions` (`compact`, `shutdown`, `setModel`).

### Invocação — `command_invoke`

```json
{ "type": "command_invoke", "id": "<uuid>", "name": "compact", "args": "" }
```

### Resultado — `command_result`

```json
{ "type": "command_result", "in_reply_to": "<uuid>", "ok": true }
```

Reply diz apenas se o dispatch funcionou. Efeitos visíveis (chat output, troca de modelo, aviso de compactação) chegam pelos canais normais (`agent_chunk`, `agent_done`, `model_select`, etc.). Erros vêm como `{ ok: false, error: "<motivo>" }` — ex: `"not_invokable"` se o app tentar invocar um comando marcado `invokable: false`.

### Limitações conhecidas

- **Mirror manual de builtins**: SDK do Pi não exporta `BUILTIN_SLASH_COMMANDS` publicamente. Pi-extension carrega a lista espelhada de `pi-coding-agent` 0.73.1. Updates do SDK exigem update manual do mirror até PR upstream aterrissar.
- **Subset invocável**: apenas comandos com equivalente programático (`compact`, `quit`, `model`, comandos extension-registered como `/remote-pi *`). Demais marcados `invokable: false`.
- **Cross-PC**: app lista comandos só do Pi diretamente pareado. Listar comandos de Pis irmãos via mesh fica pra plano futuro.

Detalhes em `plan/28-pi-commands.md`.

---

## Pareamento

QR code mostra Pi-pubkey + room hint + token de uso único.

1. App escaneia QR, conecta no relay como peer efêmero
2. App envia `pair_request` assinado com **Owner-sk** (prova autoridade)
3. Pi-extension valida assinatura, adiciona App-key na sua `peers.json` local
4. App adiciona Pi-pubkey no seu `mesh_versions` local + publica versão nova no relay
5. Pi-extension passa a aceitar mensagens daquele Owner

Múltiplos Owners podem parear o mesmo PC (concomitância — `peers.json` aceita N entries).

Detalhes em `plan/04-pairing.md`.

---

## Modelo de proteção (Trust Model)

### O que está protegido

- **Pareamento autenticado**: pair_request assinado pela Owner-sk; spoofing requer Owner-sk
- **WS pro relay sobre TLS**: ninguém na rota (ISP, NAT, MITM clássico) vê o tráfego em claro
- **Cross-PC autorização cripto**: relay só forwarda entre Pis-irmãos do mesmo Owner (verificado via Owner-sig em mesh_versions)
- **Anti-spoof entre Pis**: broker rejeita envelopes onde `envelope.from` prefix não bate com `from_pc` autenticado
- **Anti-rollback de membership**: version monotônica + assinatura impede relay/atacante de regredir mesh
- **Pi-secret protegida**: Keychain do sistema (macOS Keychain / libsecret Linux desktop / Credential Manager Windows). Atacante precisa contexto do user logado E unlock do Keychain
- **Owner-secret protegida**: iOS Keychain / Android Block Store, sincroniza via iCloud/Google account; recuperável trocando de device

### O que NÃO está protegido (declarado honestamente)

- **Relay vê plaintext do conteúdo dos envelopes**. TLS protege em trânsito; relay armazena/encaminha em claro. Operador do relay vê quem manda pra quem + o conteúdo. Mitigação: **self-hosting** do relay (open source)
- **Não há E2E** entre app e pi-extension nem entre Pis cross-PC. **Não afirmamos E2E em copy nenhuma do produto**
- **Headless Linux** (Docker, VPS sem D-Bus session): Pi-key cai pra arquivo `0600` em disco com warning loud. Atacante com acesso ao user pode ler. Recomenda-se GNOME Keyring / KWallet pra hardening real
- **Backup encriptado completo** (Time Machine, iCloud Drive criptografado etc) pode carregar a Keychain. Atacante precisa do user passphrase do backup
- **Clone detection ainda não implementado**: 2 PCs com mesma Pi-key (via cópia de arquivo headless ou comprometimento) podem coexistir no relay sem alerta. Em roadmap (plan/27 Wave E3)

### Threat model resumido

| Adversário | Capacidade | Protegido? |
|---|---|---|
| Network passive | Sniff TLS | ✅ Sim (cipher TLS) |
| Network active (MITM) | Sniff + inject | ✅ Sim (TLS + Ed25519 pairing) |
| Operador do relay público | Lê tudo que passa, persiste | ⚠️ Parcial (mitigação: self-host) |
| Outro user no PC do alvo | Lê filesystem do alvo | ✅ Sim (Keychain user-bound) |
| Atacante com root no PC do alvo | Memory dump, processo injection | ❌ Não (modelo de threat aceitável: root = jogo perdido) |
| Atacante com backup do disco | Restaura disco em outro Mac | ✅ Sim em macOS com FileVault on (recomendado) |
| Atacante que rouba só `peers.json` | Vê metadata pública (Owner-pubkeys + nicks) | Privacy issue, não impersonation |

---

## Failure modes

| Falha | Comportamento |
|---|---|
| Relay desconecta | pi-extension reconnect com backoff; agentes locais continuam falando entre si via UDS broker |
| Pi-B offline durante envio cross-PC | Sender recebe `transport_error: offline` imediatamente. Sem queue offline no relay |
| Pi-B em outro Owner | Sender recebe `transport_error: not_authorized` |
| Owner revoga Pi-A da mesh | Pi-A detecta na próxima poll de mesh_versions, faz self-revoke, sai gracefully |
| WS Pi reconecta frequente (NAT timeout) | Relay dedupa peer_online emit (transição offline→online apenas); cliente dedupa snapshots idênticos |
| Relay crash | Tudo cross-PC para; agentes locais continuam funcionando (UDS) |

---

## Roadmap arquitetural (público)

Curto prazo:
- Wave E2: `chmod 0o600` em `peers.json` + atomic write
- Wave E3: detecção de clone server-side (alerta quando 2 WS mesma Pi-pubkey de IPs diferentes)

Médio prazo:
- **Wrappers de harness** (`remote-pi claude`, `remote-pi opencode`): outros agentes coding plugam no broker UDS local via wrapper, ganham mesh sem reimplementar protocolo
- E2E cifragem do payload (Curve25519 + ChaCha20-Poly1305 entre App ↔ Pi; opcional cross-PC)

Longo prazo:
- PC-to-PC direto via WebRTC/QUIC (relay vira fallback)
- HW-bound Pi-key opcional via Secure Enclave (Apple Silicon) / TPM (Linux/Windows)

---

## Implementações de referência

- **Relay** (Rust, axum): [`relay/src/`](relay/src/)
- **Pi-extension** (Node/TS): [`pi-extension/src/`](pi-extension/src/)
- **App mobile** (Flutter): [`app/lib/`](app/lib/)
- **Planos arquiteturais**: [`plan/`](plan/) (especialmente `plan/03-protocol.md`, `plan/23-owner-key-sync.md`, `plan/24-mesh-membership.md`, `plan/25-pc-mesh-bootstrap.md`)

---

## Reportar problemas de segurança

[Definir canal] — por enquanto, abra issue marcando como `security` ou contate maintainers diretamente.
