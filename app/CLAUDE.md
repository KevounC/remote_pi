# Remote Pi — App (Flutter)

Cliente mobile (iOS + Android) do Remote Pi. Pareia via QR, lista sessões do Pi,
chat com streaming, approval cards para tool calls.

## Stack

- Flutter 3.41+ / Dart 3.11+
- Plataformas: iOS, Android
- State management: a definir (provável: Riverpod)
- Crypto: bindings para libsodium (a escolher pacote)
- WebSocket: pacote `web_socket_channel` ou similar

## Comandos

- `flutter pub get` — instala deps
- `flutter analyze` — lint estático (deve passar zero issues)
- `flutter test` — testes
- `flutter run` — abre em simulador/device conectado
- `dart format .` — formata
- `flutter build ios --no-codesign` / `flutter build apk --debug` — build verificável

## Convenções

- **Naming**: arquivos `snake_case.dart`, classes `PascalCase`, widgets `PascalCase`
- **Imports**: relativos dentro do mesmo feature, absolutos via `package:app/...` cross-feature
- **Estrutura** (a evoluir): `lib/features/<feature>/`, `lib/core/`, `lib/shared/`
- **Async**: prefira `Future`/`Stream` tipados, evite `dynamic`
- **Erros**: `Result<T, E>` ou exceptions tipadas, nunca `catch (e)` genérico em produção

## NÃO fazer

- Não editar arquivos fora de `app/`
- Não rolar crypto manual — usar libsodium bindings
- Não comitar `build/`, `.dart_tool/`, `ios/Pods/` (já no .gitignore raiz)
- Não adicionar dependência sem registrar no plano correspondente

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
