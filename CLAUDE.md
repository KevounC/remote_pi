# Remote Pi — Orquestrador

Você está na **raiz** do monorepo Remote Pi. Esta pasta é exclusivamente para **planejamento**.

## O que fazer aqui

- Ler e escrever em `plan/NN-<slug>.md` (ex: `plan/03-protocol.md`)
- Discutir arquitetura, decisões de produto, trade-offs
- Refinar planos existentes baseado em feedback
- Indicar qual subprojeto recebe a próxima implementação

## O que NÃO fazer aqui

- Não editar código em `app/`, `pi-extension/`, `relay/`, `site/`
- Não rodar comandos de build/test dos subprojetos a partir daqui
- Para implementar algo, oriente o usuário a abrir Claude no cwd correto:
  - `cd app && claude`
  - `cd pi-extension && claude`
  - `cd relay && claude`
  - `cd site && claude`

## Estrutura

Veja [README.md](./README.md) para visão geral e [plan/](./plan/) para os planos.

## Convenções de planos

- Numeração sequencial: `01-bootstrap.md`, `02-ai-orchestration.md`, ...
- Cada plano tem: Contexto, Estrutura esperada, Passos com critério de aceite, DoD, Próximos planos
- Planos descrevem **o que** + **como verificar**, não o código completo
- Pseudocódigo ou comandos exatos são bem-vindos; implementação real fica no subprojeto

## Quando promover um plano a implementação

Quando o plano tem aceite do usuário e os passos estão concretos o suficiente
para um agente executar, abra Claude no subprojeto alvo e passe o plano como
contexto. O agente daquele subprojeto seguirá sua própria persona.

## Scouts disponíveis

Para fotografar o estado de qualquer subprojeto antes de planejar, invoque os
subagents Scout em paralelo via `Task` — eles são read-only e reportam em
formato fixo:

- `scout-app` — Flutter (`app/`)
- `scout-pi-extension` — Node/TS (`pi-extension/`)
- `scout-relay` — Rust (`relay/`)
- `scout-site` — NextJS (`site/`)

Dispare múltiplos numa única mensagem para rodar em paralelo. Cada reporte
volta com Stack & versões, Dependências, Estrutura, Saúde (lint/build/testes)
e Smells detectados.

## Reportar progresso no cmux

O cmux aceita progresso visual no workspace via:

- `cmux set-progress <0.0-1.0> --label <texto>` — barra de progresso
- `cmux clear-progress` — limpa
- `cmux set-status <key> <value> [--icon <name>] [--color <#hex>]` — status nomeado

Como temos planejamento explícito em `plan/`, derive o progresso dos checkboxes
de **Definition of Done** de cada plano:

```bash
# rode da raiz do monorepo
done=$(grep -h "^- \[x\]" plan/*.md | wc -l | tr -d ' ')
total=$(grep -hE "^- \[(x| )\]" plan/*.md | wc -l | tr -d ' ')
pct=$(LC_NUMERIC=C awk "BEGIN { printf \"%.3f\", $done / $total }")  # LC_NUMERIC=C evita vírgula em locales BR
cmux set-progress "$pct" --label "Remote Pi · $done/$total tasks"
```

**Quando atualizar**:
- Após marcar um `[x]` num DoD
- Após adicionar um plano novo (total cresce, %% cai naturalmente)
- Após terminar um plano inteiro: `cmux set-status plan "0N concluído" --color "#22c55e"`

**Quando limpar**:
- Quando todos os planos do MVP fecharem: `cmux clear-progress`

Não fique chamando `set-progress` a cada turno — só quando o estado real mudou.

## Skill `claude-cmux`

Para qualquer coisa além do `set-progress` básico — dispatch entre panes, escuta de
`agent.hook.Stop`, notificações, padrão `.orchestration/` — use a skill
[`claude-cmux`](file:///Users/jacob/.claude/skills/claude-cmux/SKILL.md).

Ela cobre:
- CLI essentials (`send`, `send-key`, `events`, `notify`, `tree`, `list-panes`)
- Variáveis automáticas (`$CMUX_WORKSPACE_ID`, `$CMUX_SURFACE_ID`)
- Padrão de orquestração com `INSTRUCTIONS.md` / `plan.md` / `tasks/` / `results/`
- Como usar `claude-teams` para emitir hooks estruturados

A skill triga automaticamente em perguntas de cmux ou em pedidos de orquestração
paralela. Não duplique conteúdo dela aqui — invoque a skill.
