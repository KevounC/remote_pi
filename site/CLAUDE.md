# Remote Pi — Site (NextJS)

Landing page institucional do Remote Pi. Apresenta projeto, links pro GitHub,
documentação do MVP. **Apenas apresentação — não tem lógica de produto.**

## Stack

- NextJS 16 (App Router)
- React 19
- TypeScript 5
- Tailwind 4 (via `@tailwindcss/postcss`)
- ESLint 9
- Package manager: **pnpm** (com `allowBuilds` para `sharp` e `unrs-resolver` em `pnpm-workspace.yaml`)

## Comandos

- `pnpm install` — instala deps
- `pnpm dev` — dev server em :3000
- `pnpm build` — build de produção
- `pnpm start` — serve build
- `pnpm lint` — ESLint

## Convenções

- **Server Components por padrão** — só usar `"use client"` quando necessário (state, events, hooks)
- **Pasta de rotas**: `src/app/` (App Router)
- **Estilos**: Tailwind utility-first. Sem CSS modules / styled-components
- **Imagens**: `next/image` com fallback estático onde possível
- **Tipagem**: props de componentes sempre tipadas, sem `any`

## NÃO fazer

- Não adicionar features de produto (chat, pareamento, etc) — isso vai no `app/`
- Não comitar `.next/`, `out/`, `node_modules/` (já no .gitignore raiz)
- Não desabilitar lint pra fazer passar — corrigir o erro
- Não introduzir backend (API routes) sem registrar plano

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
