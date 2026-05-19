# Camada `ui/`

## Propósito

Entregar a experiência visual e interativa do usuário, consumindo ViewModels e
use cases para refletir o estado da aplicação por feature.

## Deve fazer

1. **Organizar por feature** — cada pasta representa um fluxo completo
   (página, states, viewmodels, widgets).
2. **Delegar lógica de negócio** — ViewModels chamam use cases e apenas
   interpretam resultados para o estado da tela.
3. **Reagir via `ChangeNotifier` + `Consumer`** — manter o loop
   UI → ViewModel → UseCase → ViewModel → UI claro e unidirecional.
4. **Cultivar widgets pequenos** — preferir `StatelessWidget`, com
   `widgets.dart` exportando componentes da feature (barrel file).
5. **Aplicar linguagem visual consistente** — seguir temas definidos em
   `config/theme.dart`.
6. **Consumir ViewModels via Provider** — sempre via `context.watch<T>()`,
   `context.read<T>()` ou `context.select<T, R>()`. **Nunca** instancie
   ViewModels diretamente na página.
7. **Registrar ViewModels no `config/dependencies.dart`** — usando
   `_injector.addViewModel<T>(T.new)`.
8. **Adicionar `ViewmodelProvider<T>()` no `routing/router.dart`** na
   definição da rota correspondente.

## ViewModel — a classe base do estado

Todo ViewModel estende [`ViewModel<T>`](core/viewmodel/viewmodel.dart), que é
um `ChangeNotifier` com **um único campo de estado imutável** e um único
verbo para alterá-lo (`emit`). O estado vive em uma sealed class na pasta
`states/` da feature.

```dart
// ui/pairing/states/pairing_state.dart
sealed class PairingState {
  const PairingState();
}

final class PairingIdle extends PairingState {
  const PairingIdle();
}

final class PairingScanning extends PairingState {
  const PairingScanning();
}

final class PairingPaired extends PairingState {
  const PairingPaired(this.deviceId);
  final String deviceId;

  @override
  bool operator ==(Object other) =>
      other is PairingPaired && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

final class PairingError extends PairingState {
  const PairingError(this.message);
  final String message;
  // ... == / hashCode
}
```

```dart
// ui/pairing/viewmodels/pairing_viewmodel.dart
class PairingViewModel extends ViewModel<PairingState> {
  PairingViewModel(this._pairWithPi) : super(const PairingIdle());

  final PairWithPiUseCase _pairWithPi;

  Future<void> startScan() async {
    emit(const PairingScanning());
    final result = await _pairWithPi();
    result.fold(
      (device) => emit(PairingPaired(device.id)),
      (error) => emit(PairingError(error.message)),
    );
  }
}
```

`emit` só dispara `notifyListeners()` se o novo estado for `!=` do atual —
por isso states precisam de `==` / `hashCode` corretos (use `equatable` ou
escreva manualmente). Isso evita rebuilds desnecessários.

## Como a UI consome o ViewModel

Páginas **nunca** instanciam o ViewModel — o `ViewmodelProvider<T>` declarado
em `routing/router.dart` (ver `config/CLAUDE.md`) já injeta a instância na
árvore. A página acessa via `context`:

```dart
class PairingPage extends StatelessWidget {
  const PairingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Lê + escuta — rebuild quando state muda
    final state = context.watch<PairingViewModel>().state;

    // Lê sem escutar — para chamar métodos
    final viewModel = context.read<PairingViewModel>();

    return Scaffold(
      body: switch (state) {
        PairingIdle() => _IdleView(onScan: viewModel.startScan),
        PairingScanning() => const _ScanningView(),
        PairingPaired(:final deviceId) => _PairedView(deviceId: deviceId),
        PairingError(:final message) => _ErrorView(message: message),
      },
    );
  }
}
```

Para reagir a **apenas um pedaço** do state (otimização):

```dart
final isScanning = context.select<PairingViewModel, bool>(
  (vm) => vm.state is PairingScanning,
);
```

### Checklist ao criar uma feature

1. Criar `states/<feature>_state.dart` (sealed class com `==`/`hashCode`).
2. Criar `viewmodels/<feature>_viewmodel.dart` estendendo `ViewModel<TState>`.
3. Registrar em `config/dependencies.dart`:
   `_injector.addViewModel<FooViewModel>(FooViewModel.new);`
4. Bindar na rota em `routing/router.dart` dentro de `MultiProvider` com
   `ViewmodelProvider<FooViewModel>()`.
5. Página consome via `context.watch/read/select`.

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após uma operação assíncrona pode crashar
(`Null check operator used on a null value`) se o widget já tiver sido
desmontado. O lint `use_build_context_synchronously` **não detecta** uso de
`context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`, `.then()`
ou `.whenComplete()` — a prevenção é manual.

**Em `StatefulWidget`** — sempre `mounted` antes do `context`:

```dart
// CORRETO — await + mounted guard
final result = await viewModel.doSomething();
if (!mounted) return;
context.sendLog('done');

// CORRETO — evitar .onSuccess, preferir await
final result = await viewModel.doSomething();
final value = result.getOrNull();
if (mounted && value != null) {
  context.sendLog('done');
}
```

```dart
// ERRADO — context dentro de .onSuccess sem guard (lint NÃO detecta)
await viewModel.doSomething().onSuccess((_) {
  context.sendLog('done'); // CRASH se widget desmontado
});

// ERRADO — context dentro de .flatMap sem guard
await viewModel.doSomething().flatMap(
  (_) => context.sendLog('done'),
);
```

**Em `StatelessWidget`** — usar `context.mounted`:

```dart
final result = await viewModel.doSomething();
if (!context.mounted) return;
context.sendLog('done');
```

**Regra resumida**:

> Nunca use `context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()` ou `.whenComplete()`. Sempre transforme para `await` + guard
> (`mounted` / `context.mounted`) antes de tocar em `context`.

## Não deve fazer

1. **Duplicar regras de domínio** — sem validações de negócio ou formatações
   complexas aqui; delegue ao domínio.
2. **Instanciar ViewModels diretamente** — nunca `MyViewModel()` dentro de
   páginas; obtenha sempre via `context.watch/read/select`.
3. **Instanciar serviços diretamente** — use dependências já injetadas via
   ViewModels.
4. **Misturar responsabilidades** — sem lógica de rede ou persistência dentro
   de widgets.
5. **Quebrar isolamento de feature** — imports cruzados passam por barrel
   files ou contratos claros.
6. **Usar `context` em callbacks assíncronos** — ver "Regra crítica" acima.

## Estrutura de pastas por feature

```
feature/
├── states/              # sealed classes do estado da feature
│   └── feature_state.dart
├── viewmodels/          # ViewModels que orquestram o estado
│   └── feature_viewmodel.dart
├── widgets/             # widgets locais componentizados
│   ├── widgets.dart     # barrel
│   └── feature_widget.dart
└── feature_page.dart    # página principal (Entry Widget)
```

## Vocabulário

- **Feature Page** — ponto de entrada da experiência da funcionalidade.
- **ViewModel** — guardião do estado e dos comandos de UI (extends
  `ChangeNotifier`).
- **State** — modelagem do que a tela pode mostrar (sealed class com casos
  como `Loading`, `Ready`, `Error`).
- **Consumer / Selector** — listener que reconstrói a UI a cada mudança do
  ViewModel.
- **Widgets Barrel** — arquivo `widgets.dart` que expõe componentes locais da
  feature.
