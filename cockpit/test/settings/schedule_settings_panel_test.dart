import 'dart:async';

import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/app_theme.dart';
import 'package:cockpit/app/settings/domain/contracts/cron_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/settings/ui/categories/schedule_settings_panel.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:flutter/widgets.dart' show Brightness, Size, SizedBox;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

void main() {
  test('schedule settings panel is importable outside settings_page', () {
    expect(const ScheduleSettingsPanel(), isA<ScheduleSettingsPanel>());
  });

  group('CronViewModel', () {
    test(
      'reload checks supervisor online and lists daemons and schedules',
      () async {
        final daemon = _daemon();
        final job = _job();
        final supervisor = _FakeDaemonSupervisor(listResult: Success([daemon]));
        final cron = _FakeCronGateway(listResult: Success([job]));
        final vm = CronViewModel(cron, supervisor);
        addTearDown(vm.dispose);

        await vm.reload();

        expect(supervisor.isOnlineCalls, 1);
        expect(supervisor.listCalls, 1);
        expect(cron.listCronCalls, 1);
        expect(vm.online, isTrue);
        expect(vm.load, CronLoad.ready);
        expect(vm.daemons, [daemon]);
        expect(vm.jobs, [job]);
      },
    );

    test('refreshQuiet skips reload while a cron action is busy', () async {
      final cron = _FakeCronGateway();
      final vm = CronViewModel(cron, _FakeDaemonSupervisor());
      addTearDown(vm.dispose);
      final job = _job();

      final run = vm.run(job);
      await vm.refreshQuiet();
      cron.completeRun(job.id, const Success('delivered'));
      await run;

      expect(cron.runCronCalls, [job.id]);
      // run() reloads once after the action. refreshQuiet did not add a second
      // concurrent list while the job was busy.
      expect(cron.listCronCalls, 1);
    });
  });

  group('ScheduleSettingsPanel widget wiring', () {
    testWidgets(
      'post-frame reload, periodic refresh, and dispose cancellation',
      (tester) async {
        final vm = _PanelCronViewModel()
          ..online = true
          ..load = CronLoad.ready;

        await _pumpPanel(tester, vm);
        expect(vm.reloadCalls, 1);

        await tester.pump(const Duration(seconds: 10));
        expect(vm.refreshQuietCalls, 1);

        await _disposePanel(tester);
        await tester.pump(const Duration(seconds: 10));
        expect(vm.refreshQuietCalls, 1);
      },
    );

    testWidgets(
      'empty, loading, error, and offline states keep existing copy',
      (tester) async {
        final vm = _PanelCronViewModel()
          ..online = true
          ..load = CronLoad.ready;
        await _pumpPanel(tester, vm);
        expect(
          find.text('No schedules. Create a recurring prompt for a daemon.'),
          findsOneWidget,
        );
        expect(find.text('Create a Daemon Agent first.'), findsOneWidget);

        vm
          ..load = CronLoad.loading
          ..jobs = const <CronJob>[];
        vm.notifyListeners();
        await tester.pump();
        expect(find.text('Loading…'), findsOneWidget);

        vm
          ..load = CronLoad.error
          ..error = 'Failed remotely';
        vm.notifyListeners();
        await tester.pump();
        expect(find.text('Failed remotely'), findsOneWidget);

        vm
          ..online = false
          ..load = CronLoad.ready;
        vm.notifyListeners();
        await tester.pump();
        expect(
          find.textContaining('Supervisor offline. Schedules need'),
          findsOneWidget,
        );

        await _disposePanel(tester);
      },
    );

    testWidgets(
      'create dialog submits cron options and reloads after success',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1000, 900);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final daemon = _daemon();
        final vm = _PanelCronViewModel()
          ..online = true
          ..load = CronLoad.ready
          ..daemons = [daemon];
        await _pumpPanel(tester, vm);

        await tester.tap(find.text('Create schedule'));
        await tester.pumpAndSettle();
        expect(find.text('New schedule'), findsOneWidget);
        expect(find.text('Next run shows up here'), findsOneWidget);

        final fields = find.byType(shadcn.TextField);
        await tester.enterText(fields.at(0), '0 9 * * *');
        await tester.enterText(fields.at(1), 'Summarize the new PRs');
        await tester.enterText(fields.at(2), 'America/Sao_Paulo');
        final switches = find.byType(shadcn.Switch);
        await tester.ensureVisible(switches.at(1));
        await tester.tap(switches.at(1));
        await tester.pump();
        await tester.ensureVisible(switches.at(2));
        await tester.tap(switches.at(2));
        await tester.pump();
        await tester.ensureVisible(find.text('Create'));
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(vm.createCalls, [
          (
            daemon.id,
            '0 9 * * *',
            'Summarize the new PRs',
            'America/Sao_Paulo',
            true,
            true,
            true,
          ),
        ]);
        // Initial post-frame load + panel reload after a created dialog result.
        expect(vm.reloadCalls, 2);

        await _disposePanel(tester);
      },
    );

    testWidgets(
      'create dialog validates local fields and preserves server error',
      (tester) async {
        final vm = _PanelCronViewModel()
          ..online = true
          ..load = CronLoad.ready
          ..daemons = [_daemon()]
          ..createResult = false;
        await _pumpPanel(tester, vm);

        await tester.tap(find.text('Create schedule'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create'));
        await tester.pump();
        expect(
          find.text('Fill in the expression and the prompt.'),
          findsOneWidget,
        );

        final fields = find.byType(shadcn.TextField);
        await tester.enterText(fields.at(0), 'bad');
        await tester.enterText(fields.at(1), 'Prompt');
        await tester.tap(find.text('Create'));
        await tester.pump();
        expect(find.text('Bad cron expression'), findsOneWidget);
        expect(find.text('Creating…'), findsNothing);

        await _disposePanel(tester);
      },
    );

    testWidgets('row actions call toggle, run, log, and remove paths', (
      tester,
    ) async {
      final job = _job(
        lastStatus: 'delivered',
        nextRun: '2026-06-30T09:00:00Z',
      );
      final vm = _PanelCronViewModel()
        ..online = true
        ..load = CronLoad.ready
        ..daemons = [_daemon()]
        ..jobs = [job]
        ..logEntries = [
          CronLogEntry(
            tsMs: DateTime(2026, 6, 30, 9).millisecondsSinceEpoch,
            jobId: job.id,
            daemonId: job.daemonId,
            schedule: job.schedule,
            fired: true,
            result: CronResult.delivered,
            promptPreview: 'Summarize',
          ),
        ];
      await _pumpPanel(tester, vm);

      await tester.tap(find.byType(shadcn.Switch).last);
      await tester.pump();
      await tester.tap(find.byIcon(shadcn.Icons.play_arrow));
      await tester.pump();
      await tester.tap(find.byIcon(shadcn.Icons.history));
      await tester.pumpAndSettle();
      expect(find.text('History — 0 9 * * *'), findsOneWidget);
      expect(find.text('delivered'), findsWidgets);
      expect(vm.fetchLogCalls, [job.id]);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(shadcn.Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      expect(vm.setEnabledCalls, [(job, false)]);
      expect(vm.runCalls, [job]);
      expect(vm.removeCalls, [job]);
      expect(find.textContaining('last: delivered'), findsOneWidget);

      await _disposePanel(tester);
    });

    testWidgets('cron editor guards late create completion after unmount', (
      tester,
    ) async {
      final vm = _PanelCronViewModel()
        ..online = true
        ..load = CronLoad.ready
        ..daemons = [_daemon()]
        ..createCompleter = Completer<bool>();
      await _pumpPanel(tester, vm);

      await tester.tap(find.text('Create schedule'));
      await tester.pumpAndSettle();
      final fields = find.byType(shadcn.TextField);
      await tester.enterText(fields.at(0), '0 9 * * *');
      await tester.enterText(fields.at(1), 'Prompt');
      await tester.tap(find.text('Create'));
      await tester.pump();
      await _disposePanel(tester);
      vm.createCompleter!.complete(true);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('cron log dialog guards late log load after unmount', (
      tester,
    ) async {
      final job = _job();
      final vm = _PanelCronViewModel()
        ..online = true
        ..load = CronLoad.ready
        ..daemons = [_daemon()]
        ..jobs = [job]
        ..fetchLogCompleter = Completer<List<CronLogEntry>?>();
      await _pumpPanel(tester, vm);

      await tester.tap(find.byIcon(shadcn.Icons.history));
      await tester.pump();
      await _disposePanel(tester);
      vm.fetchLogCompleter!.complete(const <CronLogEntry>[]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpPanel(WidgetTester tester, CronViewModel viewModel) async {
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      provide: (s) => s..addChangeNotifier<CronViewModel>(() => viewModel),
      child: (context, state) => const ScheduleSettingsPanel(),
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
}) => DaemonInfo(id: id, cwd: cwd, name: name, state: DaemonState.running);

CronJob _job({String? lastStatus, String? nextRun}) => CronJob(
  id: 'job-1',
  daemonId: 'daemon-1',
  schedule: '0 9 * * *',
  prompt: 'Summarize the new PRs',
  enabled: true,
  skipIfBusy: true,
  wake: false,
  catchup: false,
  lastStatus: lastStatus,
  nextRun: nextRun,
);

final class _FakeCronGateway implements CronGateway {
  _FakeCronGateway({this.listResult = const Success(<CronJob>[])});

  final Result<List<CronJob>, DaemonError> listResult;
  final Map<String, Completer<Result<String, DaemonError>>> _runCompleters =
      <String, Completer<Result<String, DaemonError>>>{};

  int listCronCalls = 0;
  final List<String> runCronCalls = <String>[];

  @override
  Future<Result<List<CronJob>, DaemonError>> listCron() async {
    listCronCalls++;
    return listResult;
  }

  @override
  Future<Result<void, DaemonError>> addCron({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  }) async => const Success(null);

  @override
  Future<Result<void, DaemonError>> removeCron(String jobId) async =>
      const Success(null);

  @override
  Future<Result<void, DaemonError>> setCronEnabled(
    String jobId,
    bool enabled,
  ) async => const Success(null);

  @override
  Future<Result<String, DaemonError>> runCron(String jobId) {
    runCronCalls.add(jobId);
    final completer = Completer<Result<String, DaemonError>>();
    _runCompleters[jobId] = completer;
    return completer.future;
  }

  void completeRun(String jobId, Result<String, DaemonError> result) {
    _runCompleters.remove(jobId)!.complete(result);
  }

  @override
  Future<Result<List<CronLogEntry>, DaemonError>> cronLog({
    String? jobId,
    int? tail,
  }) async => const Success(<CronLogEntry>[]);
}

final class _FakeDaemonSupervisor implements DaemonSupervisor {
  _FakeDaemonSupervisor({this.listResult = const Success(<DaemonInfo>[])});

  final Result<List<DaemonInfo>, DaemonError> listResult;
  int isOnlineCalls = 0;
  int listCalls = 0;

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
  Future<Result<void, DaemonError>> create(String cwd, {String? name}) async =>
      const Success(null);

  @override
  Future<Result<void, DaemonError>> restart(String id) async =>
      const Success(null);

  @override
  Future<Result<void, DaemonError>> restartAll() async => const Success(null);

  @override
  Future<Result<void, DaemonError>> restartSupervisor() async =>
      const Success(null);

  @override
  Future<Result<void, DaemonError>> setAgentName(
    String cwd,
    String name,
  ) async => const Success(null);

  @override
  Future<Result<void, DaemonError>> start(String id) async =>
      const Success(null);

  @override
  Future<Result<void, DaemonError>> startAll() async => const Success(null);

  @override
  Future<Result<void, DaemonError>> stop(String id) async =>
      const Success(null);

  @override
  Future<Result<void, DaemonError>> stopAll() async => const Success(null);

  @override
  Future<Result<void, DaemonError>> unregister(String id) async =>
      const Success(null);
}

final class _PanelCronViewModel extends CronViewModel {
  _PanelCronViewModel() : super(_FakeCronGateway(), _FakeDaemonSupervisor());

  int reloadCalls = 0;
  int refreshQuietCalls = 0;
  bool createResult = true;
  Completer<bool>? createCompleter;
  Completer<List<CronLogEntry>?>? fetchLogCompleter;
  List<CronLogEntry> logEntries = const <CronLogEntry>[];
  final List<(String, String, String, String?, bool, bool, bool)> createCalls =
      <(String, String, String, String?, bool, bool, bool)>[];
  final List<(CronJob, bool)> setEnabledCalls = <(CronJob, bool)>[];
  final List<CronJob> runCalls = <CronJob>[];
  final List<CronJob> removeCalls = <CronJob>[];
  final List<String?> fetchLogCalls = <String?>[];

  @override
  Future<void> reload() async {
    reloadCalls++;
  }

  @override
  Future<void> refreshQuiet() async {
    refreshQuietCalls++;
  }

  @override
  Future<bool> create({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  }) async {
    createCalls.add((
      daemonId,
      schedule,
      prompt,
      tz,
      skipIfBusy,
      wake,
      catchup,
    ));
    if (createCompleter != null) return createCompleter!.future;
    if (!createResult) actionError = 'Bad cron expression';
    return createResult;
  }

  @override
  Future<void> setEnabled(CronJob job, bool enabled) async {
    setEnabledCalls.add((job, enabled));
  }

  @override
  Future<void> run(CronJob job) async {
    runCalls.add(job);
  }

  @override
  Future<void> remove(CronJob job) async {
    removeCalls.add(job);
  }

  @override
  Future<List<CronLogEntry>?> fetchLog({String? jobId}) async {
    fetchLogCalls.add(jobId);
    if (fetchLogCompleter != null) return fetchLogCompleter!.future;
    return logEntries;
  }
}
