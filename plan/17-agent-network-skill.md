---
name: agent-network
description: Use quando você (agente Pi) for executado dentro de uma sessão de agentes locais — i.e., quando o footer do Pi mostrar "📡 <session-name>". Esta skill ensina como receber mensagens de outros agentes, como responder de forma correlacionável, como perguntar coisas a outros agentes sem perder o rastro, e como agir quando você ainda não tem o contexto necessário.
---

# Agent Network (skill — protocolo de mensagens entre agentes Pi)

Você está conectado a uma **sessão de agentes locais** via Unix Domain Socket.
Outros agentes Pi rodando na mesma máquina, na mesma sessão, podem te enviar
mensagens. Você também pode mandar mensagens pra eles.

Esta skill ensina como participar dessa rede de forma confiável. Leia até o
fim antes de agir — entender o protocolo evita silêncio e travas.

---

## A regra mais importante

**Você só recebe mensagens que foram explicitamente endereçadas a você.** O
broker da sessão filtra antes de entregar. Você nunca vai ver mensagens que
foram pra outros agentes ou pra "broadcast com `exclude_self`".

**Consequência prática**: se uma mensagem chegou em você, é porque alguém
queria sua atenção. Não ignore. Não assuma que era pra outro.

---

## Anatomia de uma mensagem (envelope)

Toda mensagem tem 5 campos:

```json
{
  "from": "orchestrator",
  "to": "backend",
  "id": "uuid-v7",
  "re": null,
  "body": <conteúdo da mensagem>
}
```

| Campo | Significado |
|---|---|
| `from` | Quem mandou. Use isso pra saber pra quem responder |
| `to` | Você (ou "broadcast", ou lista de nomes incluindo o seu) |
| `id` | Identificador único desta mensagem específica |
| `re` | Se a mensagem é RESPOSTA a outra, ecoa o `id` daquela. Senão, `null` |
| `body` | Conteúdo livre. String ou objeto JSON, depende do sender |

---

## Quando você recebe uma mensagem

Faça nesta ordem, sem pular passos:

1. **Olhe `body`** para entender o que está sendo pedido
2. **Olhe `from`** para saber pra quem responder
3. **Olhe `id`** — esse é o `correlation_id` que você vai precisar ecoar
4. **Execute o trabalho** descrito em `body`
5. **Responda** com uma mensagem nova:
   - `to`: o `from` da mensagem original
   - `id`: um UUID v7 novo (sua mensagem tem identidade própria)
   - `re`: o `id` da mensagem original (correlation)
   - `from`: seu nome
   - `body`: sua resposta

**Sempre responda.** Se o sender mandou uma mensagem que claramente espera
resposta (não é broadcast informativo), o silêncio quebra a coordenação dele.
Mesmo erros devem ser respondidos (com `body.status: "error"`).

### Exemplo concreto

Você (nome: `backend`) recebe:

```json
{
  "from": "orchestrator",
  "to": "backend",
  "id": "abc-uuid",
  "re": null,
  "body": {
    "task": "Implemente o endpoint POST /auth/login",
    "context_ref": "./contracts/auth.md"
  }
}
```

Você faz o trabalho. Responde:

```json
{
  "from": "backend",
  "to": "orchestrator",
  "id": "xyz-uuid",
  "re": "abc-uuid",
  "body": {
    "status": "done",
    "summary": "Endpoint implementado conforme contrato",
    "files_changed": ["src/auth/login.ts", "src/auth/jwt.ts"]
  }
}
```

O orquestrador correlaciona via `re === "abc-uuid"` e sabe que era a resposta
da task dele. Sem `re`, ele recebe a mensagem mas não consegue casar com a
pergunta — e fica esperando até timeout.

---

## Quando você precisa fazer pergunta pra outro agente

Antes de responder a uma task, você pode descobrir que precisa de info de
outro agente. Cenário típico: você é o `frontend`, recebeu uma task de
implementar tela de login, mas não sabe a shape exata do JWT que o `backend`
expõe.

**Fluxo correto** (síncrono via request/reply):

1. Pause sua task atual (não responda o orquestrador ainda)
2. Mande mensagem pro `backend`:
   ```json
   {
     "from": "frontend",
     "to": "backend",
     "id": "novo-uuid",
     "re": null,
     "body": {
       "question": "Qual a shape exata do payload do JWT retornado por POST /auth/login?",
       "context": "preciso implementar parsing no FE"
     }
   }
   ```
3. **Espere a resposta** com `re === "novo-uuid"`
4. Use a info recebida pra completar sua task original
5. Responda o orquestrador (com `re === "id da task original"`)

A camada de transporte (`peer.request()`) bloqueia até a resposta chegar
ou timeout. Use timeout razoável (30-60s pra perguntas simples).

### Limites

- **Faça perguntas focadas**, não delegações disfarçadas. "Qual o shape de X?"
  é OK. "Pode implementar Y pra mim?" não é — isso é o trabalho que o
  orquestrador deveria distribuir.
- **Máximo 1 hop**: se você perguntou a B, e B precisa perguntar a C pra
  responder você, B deveria **falhar** com `status: blocked` e o orquestrador
  re-planeja. Não encadeie A → B → C → ...
- **Timeout obrigatório**: nunca espere indefinidamente. Se não responder em
  60s, falhe com `status: blocked` na sua resposta ao orquestrador, citando
  qual peer não respondeu.

---

## Endereçamento avançado

### Broadcast

`to: "broadcast"` entrega pra todos exceto o sender. Use raramente:

- ✅ Anúncios: "wave 2 começou", "líder mudou pra X"
- ❌ Perguntas: ninguém responde broadcast porque ninguém sabe quem responde

### Multicast

`to: ["backend", "frontend"]` entrega pros listados. Útil pra notificações
direcionadas, ex: "ambos: parem de mexer em `contracts/` enquanto eu atualizo".

Cada destinatário recebe a mesma mensagem (mesmo `id`). Se você responder,
o `re` correlaciona normalmente.

### Self

Você nunca recebe sua própria mensagem (mesmo em broadcast). Não precisa
filtrar; o broker faz isso.

---

## Auto-descoberta de quem está na sessão

Você pode receber, em algum momento após entrar, eventos `system` do broker:

```json
{
  "from": "broker",
  "to": "backend",
  "id": "uuid",
  "re": null,
  "body": {
    "type": "peer_joined",
    "name": "frontend",
    "capabilities": ["typescript", "react"]
  }
}
```

```json
{
  "from": "broker",
  "to": "backend",
  "id": "uuid",
  "re": null,
  "body": {
    "type": "peer_left",
    "name": "frontend"
  }
}
```

Use esses eventos pra saber quem está online. Mantenha uma lista mental
(ou em estado de sessão) dos peers ativos. Não pergunte pra peer que você
sabe que está offline.

Se quiser listar peers ativos sob demanda, pergunte ao broker:

```json
{
  "from": "backend",
  "to": "broker",
  "id": "uuid",
  "re": null,
  "body": { "type": "list_peers" }
}
```

Broker responderá com `body: { peers: [...] }`.

---

## Situações em que você fica em dúvida

### "Recebi uma mensagem que não entendo"

Responda com `status: "error"` e diga o que não compreendeu. Não silencie.

```json
{
  "from": "backend",
  "to": "<from da msg original>",
  "id": "...",
  "re": "<id da msg original>",
  "body": {
    "status": "error",
    "summary": "Não entendi o pedido. O campo 'task' não está claro."
  }
}
```

### "Recebi uma mensagem com `re` setado mas eu não mandei pergunta nenhuma"

Provavelmente é uma resposta atrasada de uma request que já timeoutou ou foi
cancelada. Ignore silenciosamente. Não responda.

### "Recebi mensagem sem `re`, mas claramente é uma resposta"

Trate como mensagem nova (task). Sender não seguiu o protocolo — você não
consegue correlacionar com sua request original mesmo que tenha enviado uma.
Se for genuinamente confuso, responda perguntando: "Esta mensagem é resposta
a alguma coisa? Não vi `re`."

### "Estou em uma sessão mas nenhuma mensagem chega"

Normal. Você só recebe quando alguém te endereçar. Continue trabalhando no
modo solo até alguém te chamar. Não pollar o broker periodicamente.

### "O líder caiu (peer_left event do `broker`)"

A camada de transporte vai automaticamente promover outro peer a líder.
Você (cliente) reconectará transparentemente em ~500ms. Durante esse
tempo, suas chamadas `send/request` podem falhar — re-tente uma vez depois
de 1s antes de propagar erro.

---

## Resumo em uma página

1. Você só recebe o que é endereçado a você. Não filtre. Confie no broker.
2. Toda resposta carrega `re` = `id` da mensagem original. Sem isso, sender
   não correlaciona.
3. `to` da resposta = `from` da pergunta.
4. Sempre responda — sucesso ou erro — quando recebe algo que parece task.
5. Pode perguntar pra outros agentes mid-task (request/reply síncrono), mas:
   - Máximo 1 hop
   - Sempre com timeout
   - Pergunta read-only ("qual é X?"), não delegação ("faça Y")
6. Broadcast é pra anúncios, não pra perguntas.
7. Quando confuso, responda com `status: "error"` em vez de silenciar.

Essa skill é tudo que você precisa pra participar da sessão sem quebrar o
fluxo dos outros agentes. Releia em caso de dúvida.

---

## Mini-FAQ

**P: Posso mandar mensagem pra mim mesmo?**
R: Tecnicamente sim (`to: <seu próprio nome>`), broker entrega de volta.
Mas inútil — apenas faça o que você ia fazer sem mensagem.

**P: O que acontece com mensagens que mandei antes do destinatário entrar?**
R: Broker descarta com log de warning. Não há fila de mensagens persistente.
Se você precisa garantir entrega, espere pelo `peer_joined` event antes de
enviar.

**P: Posso ter o mesmo nome de outro agente?**
R: Não. O broker te suffixa automaticamente (ex: você pediu `backend`, recebe
`backend#2` no register_ack). Use o nome que o broker te deu (`name_assigned`)
em todas as suas mensagens.

**P: O `body` pode ser binário?**
R: Não diretamente. Use base64 dentro de string se precisar. Mas
provavelmente você está usando isso pra texto/JSON — não vire o caso de uso.

**P: Existe priorização de mensagens?**
R: Não no MVP. Ordem é FIFO de chegada no broker. Se precisar prioridade,
abra issue.

**P: Como descobrir capabilities de outros peers (qual stack, qual papel)?**
R: Eventos `peer_joined` carregam `capabilities` no `body`. Salve quando
peers entram. Ou pergunte ao broker via `list_peers`.

**P: Posso desconectar a qualquer momento?**
R: Sim. A camada de transporte manda `peer_left` automaticamente quando
você fecha. Outros agentes verão você sumir.

---

## Veja também

- [`plan/17-agent-network-rfc.md`](../plan/17-agent-network-rfc.md) — motivação e contexto
- [`plan/17-agent-network.md`](../plan/17-agent-network.md) — plano de implementação
- `~/.pi/remote-pi/sessions/<nome>/audit.jsonl` — log de tudo que passou pelo broker (read-only audit)
