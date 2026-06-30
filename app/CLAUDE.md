# Remote Pi — App (Flutter)

Cliente mobile (iOS + Android) do Remote Pi. Pareia via QR, lista sessões do Pi,
chat com streaming, approval cards para tool calls.

Antes de editar ou revisar `app/`, leia também a referência agent-neutral
`../.agents/skills/flutter-mobile/SKILL.md`. Para mudanças de estado/reconnect que cruzem
app/extension/relay, leia `../.agents/skills/mobile-remote-coding/SKILL.md`.

## Stack

- Flutter 3.41+ / Dart 3.11+
- Plataformas: iOS, Android
- State management: `ChangeNotifier` + `provider` (ViewModels reativos)
- DI: `auto_injector` (registry em `lib/config/`)
- Roteamento: `go_router`
- Resultado tipado: `Result<T, E>` (sucesso/falha explícitos)
- Crypto: bindings para libsodium (pacote a confirmar — ver `plan/00-decisions.md`)
- WebSocket: `web_socket_channel` ou similar

> Decisões ainda abertas (state mgmt definitivo, pacote libsodium) vivem em
> `../plan/00-decisions.md`. A stack acima é a direção atual baseada na
> arquitetura herdada; mudanças estruturais exigem plano novo.

## Comandos

O SDK do Flutter e o pub cache vivem no repositório (não em `/opt` ou `/tmp`).
Defina `PUB_CACHE` e use o binário em `.tools/flutter`. `app/` não tem deps git,
então `pub get` online funciona (ou `--offline` se o cache já estiver povoado).

```bash
cd app
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter pub get
~/projects/remote_pi/.tools/flutter/bin/flutter analyze              # deve passar zero issues
~/projects/remote_pi/.tools/flutter/bin/flutter test
~/projects/remote_pi/.tools/flutter/bin/flutter build apk --debug    # ou --no-codesign ios
```

- `dart format .` — formata (ou `~/.tools/flutter/bin/cache/dart-sdk/bin/dart format .`)

Nota: `flutter analyze` em `app/` emite um `info` pré-existente e não relacionado:
`axisAlignment` deprecated em `lib/ui/chat/widgets/input_bar.dart:802`. Não falhar revisões por isso.

> Para o caminho completo de build de APK no dev VM (`codebox`) — toolchain JDK 21
> + Android SDK API 36, build `--release --split-per-abi` (~31 MB por ABI), e os
> dois gotchas de build (`.` vs `source` em jobs dash; wipe completo de
> `~/.gradle` em corrupção de workspace Kotlin-DSL) — veja a referência
> agent-neutral `../.agents/skills/flutter-mobile/SKILL.md` (seção "Android APK
> build on the dev VM").

## Arquitetura por camadas

O `lib/` é organizado em camadas com responsabilidades estritas. Cada pasta
tem seu próprio `CLAUDE.md` descrevendo a persona daquela camada — **leia o
CLAUDE.md da camada antes de editar qualquer arquivo dentro dela**.

```
lib/
├── main.dart
├── config/          # Bootstrap, DI, env, setup global  → config/CLAUDE.md
│   └── utils/       # Helpers horizontais
├── domain/          # Entidades, use cases, validators  → domain/CLAUDE.md
├── data/            # Repositórios, adapters, APIs      → data/CLAUDE.md
├── routing/         # GoRouter, paths, guards           → routing/CLAUDE.md
└── ui/              # Páginas + ViewModels por feature  → ui/CLAUDE.md
    └── <feature>/
        ├── states/
        ├── viewmodels/
        ├── widgets/
        └── <feature>_page.dart
```

Regra de ouro do fluxo de dependência:

```
ui ──► domain ◄── data
        ▲
        │
     config (injeta tudo)
     routing (compõe rotas + ViewModels)
```

- `domain/` **não** importa nada de `data/`, `ui/`, `routing/`, `config/`.
- `data/` importa contratos de `domain/`, nunca de `ui/`.
- `ui/` consome `domain/` (use cases) via ViewModels — nunca chama `data/` direto.
- `config/` é o único lugar que conhece todas as camadas (para registrar bindings).

## Convenções

- **Naming**: arquivos `snake_case.dart`, classes `PascalCase`, widgets `PascalCase`
- **Imports**: relativos dentro do mesmo feature; absolutos via `package:app/...`
  quando cruzando features ou camadas
- **Barrel files**: cada feature/módulo pode expor um `<nome>.dart` agregando
  os símbolos públicos; consumidores externos importam só o barrel
- **Async**: prefira `Future`/`Stream` tipados, evite `dynamic`
- **Erros**: `Result<T, E>` ou exceptions tipadas; nunca `catch (e)` genérico em produção
- **ViewModels**: registrados em `config/` e injetados em `routing/` via Provider;
  páginas nunca instanciam ViewModel diretamente — sempre `context.watch/read/select`

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após um `await` (ou dentro de `.then/.onSuccess/.flatMap/.whenComplete`)
pode crashar com `Null check operator used on a null value` se o widget já tiver sido
desmontado. O lint `use_build_context_synchronously` **não detecta** callbacks
encadeados — a prevenção é manual.

**Padrão obrigatório**:

```dart
// CORRETO — await + guard
final result = await viewModel.doSomething();
if (!mounted) return;          // em StatefulWidget
// if (!context.mounted) return; // em StatelessWidget
context.useContextSomehow();
```

```dart
// ERRADO — context dentro de callback assíncrono
await viewModel.doSomething().onSuccess((_) {
  context.useContextSomehow(); // CRASH se desmontado
});
```

> Nunca use `context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()` ou `.whenComplete()`. Sempre transforme para `await` + guard.

## NÃO fazer

- Editar arquivos fora de `app/`
- Implementar crypto manual — usar bindings libsodium
- Comitar `build/`, `.dart_tool/`, `ios/Pods/` (já no `.gitignore` raiz)
- Adicionar dependência sem registrar no plano correspondente
- Misturar responsabilidades entre camadas — quando bater dúvida, leia o
  CLAUDE.md da camada alvo

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
