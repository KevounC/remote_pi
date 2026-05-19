# Camada `config/`

## Propósito

Custodiar todas as decisões de orquestração do aplicativo: bootstrapping,
configuração de dependências (`auto_injector`), ambientes, chaves, integrações
globais. Esta camada conhece todas as outras — é o único lugar com essa
permissão.

## Deve fazer

1. **Declarar bindings**: toda dependência compartilhada nasce aqui via
   `injector.add...`. Repositórios, serviços, ViewModels — tudo passa pelo
   registry.
2. **Usar injeção automática**: prefira passar a referência do construtor
   (`MyClass.new`) em vez de instanciar manualmente. O `AutoInjector` resolve
   parâmetros sozinho.
3. **Isolar setup**: inicializações de SDKs, logs, rotas, temas globais
   acontecem em funções claramente nomeadas (`setupDependencies`,
   `disposeDependencies`, `bootstrap`).
4. **Confiar em contratos**: use apenas interfaces expostas por `domain/`,
   `data/` (services) e `ui/` (ViewModels) — não crie lógica de negócio.
5. **Documentar switches**: variáveis de ambiente e feature flags precisam de
   descrição neste arquivo ou em `.env.example`.

## Não deve fazer

1. **Codificar regras de domínio** — nenhum cálculo, validação ou regra de
   negócio mora aqui.
2. **Criar singletons manuais** — sempre use o `AutoInjector` para controlar
   ciclo de vida.
3. **Importar widgets ou páginas** — manter-se independente da camada `ui/`
   (exceto declarações de tipos para registrar ViewModels).
4. **Executar chamadas de rede** — configure clientes, mas não consuma
   serviços diretamente.

## Estrutura sugerida

```
config/
├── dependencies.dart    # setupDependencies / disposeDependencies / ViewmodelProvider
├── env.dart             # leitura de --dart-define e feature flags
├── theme.dart           # ThemeData global
└── utils/
    └── injector.dart    # CustomInjector — fachada tipada sobre auto_injector
```

## Sistema de DI — como usar

A fachada [`CustomInjector`](utils/injector.dart) embrulha o `auto_injector`
com métodos tipados por camada. Cada método declara intenção e amarra o tipo
a um contrato do domínio (`Service`, `Repository`, `UseCase`, `ViewModel`).

### Registrar dependências

Tudo é registrado em `setupDependencies()` em
[`config/dependencies.dart`](dependencies.dart), nesta ordem:

```dart
Future<void> setupDependencies() async {
  // 1. Instâncias prontas (SDKs)
  _injector.addInstance<SharedPreferences>(await SharedPreferences.getInstance());

  // 2. Serviços de infra (singleton preguiçoso + dispose automático)
  _injector.addService<NetworkService>(NetworkServiceImpl.new);

  // 3. Factories utilitárias (sem contrato do domínio)
  _injector.addOther<Dio>(dioFactory);

  // 4. Repositórios (impl em data/, contrato em domain/)
  _injector.addRepository<PairingRepository>(PairingRepositoryImpl.new);

  // 5. Use cases (instância nova por chamada)
  _injector.addUseCase<PairWithPiUseCase>(PairWithPiUseCase.new);

  // 6. ViewModels (instância nova por tela)
  _injector.addViewModel<HomeViewModel>(HomeViewModel.new);

  _injector.commit(); // bloqueia novas inserções
}
```

### Ciclo de vida

- `addService` / `addRepository` → singleton preguiçoso; `dispose()` é
  chamado quando `disposeDependencies()` roda.
- `addUseCase` / `addViewModel` → `_injector.add(...)` puro: cada `get`
  devolve **uma nova instância**. Estado de tela nunca vaza entre rotas.
- `addInstance` → exatamente o objeto passado, para sempre.
- `addOther` → singleton preguiçoso, **sem** dispose hook.

### Como o ViewModel chega na UI

`config/dependencies.dart` exporta `ViewmodelProvider<T>` — um
`ChangeNotifierProvider` que pede ao injector uma nova instância do
ViewModel quando a rota é montada. A composição em `routing/router.dart` é
o **único** lugar onde ViewmodelProviders são declarados:

```dart
GoRoute(
  path: routePaths.home,
  builder: (_, __) => MultiProvider(
    providers: [
      ViewmodelProvider<HomeViewModel>(),
      ViewmodelProvider<HomeFilterViewModel>(),
    ],
    child: const HomePage(),
  ),
)
```

Detalhes do consumo em `ui/CLAUDE.md`.

## Vocabulário

- **Injector** — fonte única de verdade para dependências.
- **Binding** — contrato que associa um tipo concreto ao seu provedor dentro
  do injector.
- **Bootstrap** — sequência de inicialização do app antes do `runApp`.
