import 'dart:async';

import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/app_theme.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/settings/ui/categories/daemon_settings_panel.dart';
import 'package:cockpit/app/settings/ui/daemons_viewmodel.dart';
import 'package:flutter/widgets.dart' show Brightness, SizedBox;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

void main() {
  test('daemon settings panel is importable outside settings_page', () {
    expect(const DaemonSettingsPanel(), isA<DaemonSettingsPanel>());
  });

  group('DaemonsViewModel', () {
    test('reload checks supervisor online and lists daemons', () async {
      final daemon = _daemon();
      final supervisor = _FakeDaemonSupervisor(listResult: Success([daemon]));
      final vm = DaemonsViewModel(supervisor);
      addTearDown(vm.dispose);

      await vm.reload();

      expect(supervisor.isOnlineCalls, 1);
      expect(supervisor.listCalls, 1);
      expect(vm.online, isTrue);
      expect(vm.load, DaemonsLoad.ready);
      expect(vm.daemons, [daemon]);
    });

    test('refreshQuiet skips reload while a daemon action is busy', () async {
      final supervisor = _FakeDaemonSupervisor();
      final vm = DaemonsViewModel(supervisor);
      addTearDown(vm.dispose);

      final start = vm.start('daemon-1');
      await vm.refreshQuiet();
      supervisor.completeStart('daemon-1', const Success(null));
      await start;

      expect(supervisor.startCalls, ['daemon-1']);
      // start() reloads once after the action. refreshQuiet did not add a
      // second concurrent list while the action was busy.
      expect(supervisor.listCalls, 1);
    });
  });

  group('DaemonSettingsPanel widget wiring', () {
    testWidgets(
      'post-frame reload, periodic refresh, and dispose cancellation',
      (tester) async {
        final vm = _PanelDaemonsViewModel()
          ..online = true
          ..load = DaemonsLoad.ready;

        await _pumpPanel(tester, vm);
        expect(vm.reloadCalls, 1);

        await tester.pump(const Duration(seconds: 10));
        expect(vm.refreshQuietCalls, 1);

        await _disposePanel(tester);
        await tester.pump(const Duration(seconds: 10));
        expect(vm.refreshQuietCalls, 1);
      },
    );

    testWidgets('daemon row actions call the matching view model methods', (
      tester,
    ) async {
      final daemon = _daemon(state: DaemonState.running, uptimeSeconds: 3661);
      final vm = _PanelDaemonsViewModel()
        ..online = true
        ..load = DaemonsLoad.ready
        ..daemons = [daemon];
      await _pumpPanel(tester, vm);

      await tester.tap(find.byIcon(shadcn.Icons.stop).last);
      await tester.pump();
      await tester.tap(find.byIcon(shadcn.Icons.restart_alt).last);
      await tester.pump();
      await tester.tap(find.byIcon(shadcn.Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      expect(vm.stopCalls, ['daemon-1']);
      expect(vm.restartCalls, ['daemon-1']);
      expect(vm.removeCalls, ['daemon-1']);
      expect(find.textContaining('1h1m'), findsOneWidget);

      await _disposePanel(tester);
    });

    testWidgets(
      'fleet and supervisor actions call the matching view model methods',
      (tester) async {
        final vm = _PanelDaemonsViewModel()
          ..online = true
          ..load = DaemonsLoad.ready
          ..daemons = [_daemon()];
        await _pumpPanel(tester, vm);

        await tester.tap(find.text('Start all'));
        await tester.pump();
        await tester.tap(find.text('Stop all'));
        await tester.pump();
        await tester.tap(find.text('Restart all'));
        await tester.pump();
        await tester.tap(find.text('Restart supervisor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restart').last);
        await tester.pumpAndSettle();

        expect(vm.startAllCalls, 1);
        expect(vm.stopAllCalls, 1);
        expect(vm.restartAllCalls, 1);
        expect(vm.restartSupervisorCalls, 1);

        await _disposePanel(tester);
      },
    );

    testWidgets(
      'edit dialog rename uses the selected daemon and guards cancel',
      (tester) async {
        final daemon = _daemon(name: 'Old name');
        final vm = _PanelDaemonsViewModel()
          ..online = true
          ..load = DaemonsLoad.ready
          ..daemons = [daemon];
        await _pumpPanel(tester, vm);

        await tester.tap(find.byIcon(shadcn.Icons.edit_outlined));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(shadcn.TextField), 'New name');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(vm.renameCalls, [(daemon, 'New name')]);

        await tester.tap(find.text('Create daemon'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(vm.createCalls, isEmpty);

        await _disposePanel(tester);
      },
    );
  });
}

Future<void> _pumpPanel(WidgetTester tester, DaemonsViewModel viewModel) async {
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      provide: (s) => s..addChangeNotifier<DaemonsViewModel>(() => viewModel),
      child: (context, state) => const DaemonSettingsPanel(),
    ),
  );
  final app = createModule(register: (c) => c.module(feature));
  final boot = bootstrapModule(app);

  await tester.pumpWidget(
    shadcn.ShadcnApp.router(
      theme: buildTheme(brightness: Brightness.dark),
      routerConfig: modularRouterConfig(
        boot.routes,
        injector: boot.injector,
        manager: boot.manager,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposePanel(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

DaemonInfo _daemon({
  String id = 'daemon-1',
  String cwd = '/tmp/daemon-1',
  String name = 'Daemon One',
  DaemonState state = DaemonState.stopped,
  int? uptimeSeconds,
}) => DaemonInfo(
  id: id,
  cwd: cwd,
  name: name,
  state: state,
  pid: state == DaemonState.running ? 1234 : null,
  uptimeSeconds: uptimeSeconds,
  restartCount: 2,
);

final class _FakeDaemonSupervisor implements DaemonSupervisor {
  _FakeDaemonSupervisor({this.listResult = const Success(<DaemonInfo>[])});

  final Result<List<DaemonInfo>, DaemonError> listResult;
  final Map<String, Completer<Result<void, DaemonError>>> _startCompleters =
      <String, Completer<Result<void, DaemonError>>>{};

  int isOnlineCalls = 0;
  int listCalls = 0;
  final List<String> startCalls = <String>[];
  final List<String> stopCalls = <String>[];
  final List<String> restartCalls = <String>[];
  final List<String> unregisterCalls = <String>[];
  final List<(String, String)> createCalls = <(String, String)>[];
  final List<(String, String)> setAgentNameCalls = <(String, String)>[];
  int startAllCalls = 0;
  int stopAllCalls = 0;
  int restartAllCalls = 0;
  int restartSupervisorCalls = 0;

  @override
  Future<bool> isOnline() async {
    isOnlineCalls++;
    return true;
  }

  @override
  Future<Result<List<DaemonInfo>, DaemonError>> list() async {
    listCalls++;
    return listResult;
  }

  @override
  Future<Result<void, DaemonError>> start(String id) {
    startCalls.add(id);
    final completer = Completer<Result<void, DaemonError>>();
    _startCompleters[id] = completer;
    return completer.future;
  }

  void completeStart(String id, Result<void, DaemonError> result) {
    _startCompleters.remove(id)!.complete(result);
  }

  @override
  Future<Result<void, DaemonError>> stop(String id) async {
    stopCalls.add(id);
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> restart(String id) async {
    restartCalls.add(id);
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> unregister(String id) async {
    unregisterCalls.add(id);
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> create(String cwd, {String? name}) async {
    createCalls.add((cwd, name ?? ''));
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> setAgentName(
    String cwd,
    String name,
  ) async {
    setAgentNameCalls.add((cwd, name));
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> startAll() async {
    startAllCalls++;
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> stopAll() async {
    stopAllCalls++;
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> restartAll() async {
    restartAllCalls++;
    return const Success(null);
  }

  @override
  Future<Result<void, DaemonError>> restartSupervisor() async {
    restartSupervisorCalls++;
    return const Success(null);
  }
}

final class _PanelDaemonsViewModel extends DaemonsViewModel {
  _PanelDaemonsViewModel() : super(_FakeDaemonSupervisor());

  int reloadCalls = 0;
  int refreshQuietCalls = 0;
  final List<String> startCalls = <String>[];
  final List<String> stopCalls = <String>[];
  final List<String> restartCalls = <String>[];
  final List<String> removeCalls = <String>[];
  final List<(DaemonInfo, String)> renameCalls = <(DaemonInfo, String)>[];
  final List<(String, String?)> createCalls = <(String, String?)>[];
  int startAllCalls = 0;
  int stopAllCalls = 0;
  int restartAllCalls = 0;
  int restartSupervisorCalls = 0;

  @override
  Future<void> reload() async {
    reloadCalls++;
  }

  @override
  Future<void> refreshQuiet() async {
    refreshQuietCalls++;
  }

  @override
  Future<void> start(String id) async {
    startCalls.add(id);
  }

  @override
  Future<void> stop(String id) async {
    stopCalls.add(id);
  }

  @override
  Future<void> restart(String id) async {
    restartCalls.add(id);
  }

  @override
  Future<void> remove(String id) async {
    removeCalls.add(id);
  }

  @override
  Future<void> startAll() async {
    startAllCalls++;
  }

  @override
  Future<void> stopAll() async {
    stopAllCalls++;
  }

  @override
  Future<void> restartAll() async {
    restartAllCalls++;
  }

  @override
  Future<void> restartSupervisor() async {
    restartSupervisorCalls++;
  }

  @override
  Future<bool> rename(DaemonInfo daemon, String name) async {
    renameCalls.add((daemon, name));
    return true;
  }

  @override
  Future<bool> create(String cwd, {String? name}) async {
    createCalls.add((cwd, name));
    return true;
  }
}
