# Decisões já tomadas

Este arquivo é um **registro** (não um plano executável). Lista decisões fechadas em conversa exploratória antes/durante o bootstrap. **Não revisite sem evidência forte de que a decisão estava errada** — proponha re-discutir como tarefa explícita, não silenciosamente.

Numeração `00-` é proposital: este arquivo carrega antes dos planos numerados quando alguém faz `ls plan/`.

---

## Origin / posicionamento

- **Alvo do produto**: ataque o [Pi coding agent](https://github.com/earendil-works/pi). Não Claude Code (já tem Remote Control oficial), não OpenCode (já tem 5+ apps mobile community), não Goose/Aider (mercado pequeno).
  - **Razão**: Pi é o concorrente open-source mais relevante do Claude Code, tem RPC + SDK públicos, e **nenhum app mobile dedicado existe** (só `TelePi` via Telegram).
- **Não copiar MuxAgent**: ele já cobre multi-harness comercial. Brigamos pelo nicho **Pi-only, open source, qualidade**.

## Arquitetura

| Decisão | Razão / nota |
|---|---|
| **Sem daemon no MVP** | Só a extensão `/remote-pi` ativa enquanto Pi roda. Refutamos daemon residente: complexidade alta, ganho moderado. Quando Pi fecha → mobile vê offline |
| **Extensão > wrapper** | Pi tem extension API (TypeScript runtime extensions). Happy fez wrapper só porque Claude Code é closed-source — Pi não precisa repetir isso |
| **Auto-start opcional** | Config `pi-remote.autostart=true` conecta no relay automaticamente quando Pi abre. Sem precisar digitar `/remote-pi` toda vez |
| **Relay stateless** | Sem persistência. Encaminha ciphertext entre dois peers identificados por pubkey. ~200 linhas de Rust |
| **Relay open-source + self-hostável** | Compromisso de credibilidade. Usuário paranoico roda o próprio. Não vira ponto único de comprometimento |

## Pareamento

| Decisão | Razão / nota |
|---|---|
| **Persistente, não efêmero** | Peers salvos em `~/.pi/remote/peers.json` (Mac) + Keychain/Keystore (mobile). Refutamos efêmero por sessão e efêmero por pareamento — UX hostil. Pair-once, reconnect-forever |
| **Sem conta no MVP** | QR só pareamento. Conta opcional fica pra v2 se aparecer demanda real (multi-device sync, recuperação) |
| **QR efêmero (60s, rotaciona)** | Janela curta reduz risco de foto/screenshot vazar. Token single-use |
| **Safety number opcional** | 6 emojis bilateral (estilo Signal), pra confirmar visualmente que pareamento não foi MITM |
| **Forward secrecy** | ECDH efêmero a cada reconexão. Chave de longo prazo (Curve25519) só pra autenticar identidade |
| **Identidade = pubkey** | Sem username. Auth no relay via challenge-response (relay assina nonce, peer responde com assinatura da pubkey privada) |
| **Lifetime do pareamento** | Até alguém revogar. Comando `/remote-pi revoke <nome>` (não no MVP, mas previsto) |

## Escopo de visibilidade

| Decisão | Razão / nota |
|---|---|
| **Project scope via git root** | App pareado vê só sessões do projeto onde `/remote-pi` rodou. Detecção: subir a árvore procurando `.git`, `package.json`, `pyproject.toml`, `Cargo.toml`. Fallback: cwd exato |
| **Refutados**: cwd-exato (perde sessões da raiz quando entra `src/`) e Mac-inteiro (vaza projetos pessoais) | |
| **Pareamento global, vista por projeto** | Chave de longo prazo é por Mac (singleton). Lista de sessões filtra por project scope do Pi que tá rodando |

## Multi-instância (vários Pi)

| Cenário | Comportamento |
|---|---|
| 2 terminais Pi na mesma pasta | Cada um gera QR próprio → 2 pareamentos independentes. Zero conflito |
| Pi A pediu `switch_session X`, X está LIVE em Pi B | `AgentSessionRuntime.resume(X)` lança `SessionLockedError`. App mostra "em uso em outro terminal" |
| Pi numa subpasta (`projeto-a/src`) | Resolve project root = `projeto-a/` via marcador → mesmo conjunto de sessões |
| App listando sessões | Estado por sessão: `LIVE aqui` (verde), `em outro Pi` (meio cheio), `histórico` (cinza) |

## UI / produto

| Decisão | Razão / nota |
|---|---|
| **Hierarquia Peer → Projeto → Sessão** | Não árvore como home. Inbox de approvals + sessões ativas + recentes |
| **Sessão histórica = read-only** | Tap abre histórico completo. Botão "Continuar essa sessão" dispara `switch_session` → vira active no Pi → libera write |
| **Mobile pode ativar sessão histórica** | Não precisa o dev resumir no terminal. App envia `switch_session` e Pi process faz `AgentSessionRuntime.resume()` |
| **Rename em 3 níveis** | Peer no Keychain (local), Projeto em `~/.pi/remote/projects.json` (sincroniza p/ outros celulares pareados), Sessão no metadata JSONL (sincroniza bidirecionalmente com a CLI) |
| **Trabalho paralelo** | Emerge da arquitetura: N Pi processes = N AgentSessions LIVE. App mostra todas com swipe-rápido entre elas |
| **Switcher por gesto** | Recomendação UX: swipe da borda esquerda alterna entre últimas N sessões |

## Approval / segurança operacional

| Decisão | Razão / nota |
|---|---|
| **Sem push notification no MVP** | Cortado pra eliminar burocracia APNs ($99/ano cert), FCM SDK, push token mgmt. Reconexão = on-demand quando user abre app |
| **Auto-approve read-only** | `Read`, `Glob`, `Grep` rodam sem prompt. Fluxo do agente não trava em coisa segura |
| **Approval obrigatório** | `Bash`, `Edit`, `Write` sempre param. App mostra diff/comando antes de aprovar |
| **Timeout default 60s** | `on_timeout=abort`. Conservador: se user não respondeu, não execute |
| **Quando push entrar (v2)** | Aditivo. Schema atual não muda. Relay decora `tool_request` com push fire |

## Crypto / E2E (resumo — detalhe no plano 04)

| Decisão | Razão / nota |
|---|---|
| **libsodium / Noise** | Curve25519 + ChaCha20-Poly1305. Pode ser Noise XX/IK (padrão WireGuard/WhatsApp) ou libsodium direto. **Não inventar protocolo** |
| **Relay NUNCA decifra** | Vê só `{ peer, ct, tamanho, timestamp }`. Logs proibidos de conter payload (mesmo cifrado) |
| **TLS 1.3 obrigatório** | Camada 1 (transporte). E2E é camada 2. Defesa em profundidade |
| **Cert pinning no app** | Bloqueia MITM via CA comprometida |
| **Sem quantum-safe** | Curve25519 cai contra computador quântico estável. Trocar pra Kyber quando virar problema real (não 2026) |
| **`ct` no MVP do protocolo (plano 03)** | É base64 do JSON em claro até o plano 04 ativar cifra real. Permite testar shape sem bloquear em crypto |

## Modelo de ameaças — o que NÃO protegemos

Para ser honesto desde o início:

- **Mac comprometido** → atacante é o Pi. Fim de jogo
- **Celular comprometido** → atacante tem Keychain. Fim de jogo
- **Usuário aprovando comando malicioso** → sistema obedece. UI mostra diff, mas se você toca Aprovar sem ler, é problema seu
- **Análise de tráfego** → relay sabe tamanho/timing. Não vaza conteúdo, mas vaza padrões ("Jacob ativo às 22h")
- **Quantum** → ver linha acima

## Processo / meta

| Princípio | Aplicação |
|---|---|
| **Não criar subagent antes de existir conteúdo** | Reviewers locais foram negados pra agora — só stubs nos subprojetos |
| **Não criar abstração antes de precisar** | YAGNI agressivo. Aplicado em: sem versionamento de protocolo, sem `--persist` flag no `/remote-pi`, sem recovery de pareamento |
| **Subagent só vale com 3 critérios** | Prompt rico + saída estruturada + contexto isolado. Senão é overhead |
| **CLAUDE.md silencioso sobre irmãos** | Persona vive no projeto. Único acoplamento aceitável: gatilho `[ORCH:<id>]` → lê `.orchestration/INSTRUCTIONS.md` |
| **Plan/ é cockpit do orquestrador** | Subagentes não navegam planos altos. Recebem tasks decompostas |

---

## Em aberto — não decidir sem motivo

Estas decisões foram **propositalmente adiadas**. Quando alguém quiser fechar, abrir discussão explícita.

| Item | Quando decidir |
|---|---|
| State management Flutter (Riverpod / bloc / signals_flutter) | Quando 1ª feature do app exigir state compartilhado |
| Pacote libsodium pra Dart (`sodium_libs`, `cryptography`, outro) | Plano 04 (pareamento) |
| Onde hospedar o relay | Plano 06 |
| Versionamento de protocolo (`v` field) | Quando v2 do protocolo surgir e exigir migração |
| Conta de usuário opcional | Quando aparecer dor multi-device |
| Push notifications | v2, após MVP validado |
| Multi-relay / federação | Provavelmente nunca. Só se relay público virar gargalo |
| Apps nativos (Swift/Kotlin) em vez de Flutter | Provavelmente nunca. Reconsiderar só se Flutter limitar features críticas (ex: integração profunda iOS Keychain) |

---

## Como atualizar este arquivo

- **Decisão nova fechada em conversa** → adicione bullet na seção certa
- **Decisão revertida** → não apague o bullet original; **risque** (`~~texto~~`) e adicione a nova abaixo com data e razão
- **Decisão deixada em aberto** → vai pra "Em aberto"
- **Não** edite este arquivo em silêncio durante implementação. Decisões existem em conversa explícita
