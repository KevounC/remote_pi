import 'package:app/domain/contracts/contracts.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:auto_injector/auto_injector.dart';

/// Fachada sobre o [AutoInjector] que centraliza a configuração de serviços,
/// repositórios, casos de uso e view models, garantindo descarte correto.
///
/// Métodos tipados (`addService`, `addRepository`, `addUseCase`,
/// `addViewModel`) servem como documentação viva: ao registrar algo, você
/// declara qual camada ele pertence e qual contrato ele satisfaz.
///
/// Use `addInstance` para valores prontos (ex.: instâncias de SDK) e
/// `addOther` para tipos que não se encaixam nos contratos do domínio (ex.:
/// `Dio`, `Connectivity`).
class CustomInjector {
  final _injector = AutoInjector();

  /// Resolve uma instância registrada. Para `ViewModel`s, cada chamada
  /// devolve uma nova instância (registrada com `add`, não `addLazySingleton`).
  T get<T extends Object>() => _injector.get<T>();

  /// Registra um valor já construído (singleton de fato).
  void addInstance<T>(T instance) {
    _injector.addInstance<T>(instance);
  }

  /// Registra um singleton preguiçoso para tipos que não são `Service`,
  /// `Repository` ou `UseCase` — ex.: `Dio`, factories de SDKs.
  void addOther<T>(Function constructor) {
    _injector.addLazySingleton<T>(constructor);
  }

  /// Adiciona um [Service] como singleton preguiçoso, encadeando o
  /// `dispose()` no descarte do injector.
  void addService<T extends Service>(Function constructor) {
    _injector.addLazySingleton<T>(
      constructor,
      config: BindConfig(onDispose: (value) => value.dispose()),
    );
  }

  /// Adiciona um [Repository] como singleton preguiçoso, encadeando o
  /// `dispose()` no descarte do injector.
  void addRepository<T extends Repository>(Function constructor) {
    _injector.addLazySingleton<T>(
      constructor,
      config: BindConfig(onDispose: (value) => value.dispose()),
    );
  }

  /// Registra um [ViewModel]; cada `get` retorna uma nova instância. Estado
  /// não vaza entre telas distintas.
  void addViewModel<T extends ViewModel>(Function constructor) {
    _injector.add(constructor);
  }

  /// Registra um [UseCase] para ser resolvido sob demanda.
  void addUseCase<T extends UseCase>(Function constructor) {
    _injector.add(constructor);
  }

  /// Libera todas as dependências registradas e reseta o injector.
  void dispose() => _injector.dispose();

  /// Finaliza o cadastro de dependências e bloqueia novas inserções. Deve ser
  /// chamado ao fim de `setupDependencies()`.
  void commit() => _injector.commit();
}
