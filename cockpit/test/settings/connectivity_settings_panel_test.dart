import 'dart:async';

import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/core/domain/entities/pair_event.dart';
import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/app_theme.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/settings/ui/categories/connectivity_settings_panel.dart';
import 'package:cockpit/app/settings/ui/connectivity_viewmodel.dart';
import 'package:cockpit/app/settings/ui/pairing_controller.dart';
import 'package:cockpit/app/settings/ui/revoke_controller.dart';
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

void main() {
  test('connectivity settings panel is importable outside settings_page', () {
    expect(const ConnectivitySettingsPanel(), isA<ConnectivitySettingsPanel>());
  });

  group('ConnectivityViewModel', () {
    test(
      'load fetches relay config and paired devices through RelayGateway',
      () async {
        final relay = _FakeRelayGateway(
          currentRelayResult: const Success('https://relay.example.test'),
          devicesResult: const Success([
            PairedDevice(shortId: 'ios-1', label: 'iPhone'),
          ]),
        );
        final vm = ConnectivityViewModel(
          relay,
          _FakePairingGatewayFactory(),
          _FakeRevokeGatewayFactory(),
        );
        addTearDown(vm.dispose);

        await vm.load();

        expect(relay.currentRelayCalls, 1);
        expect(relay.listDevicesCalls, 1);
        expect(vm.relayLoad, ConnLoad.ready);
        expect(vm.relayUrl, 'https://relay.example.test');
        expect(vm.devicesLoad, ConnLoad.ready);
        expect(vm.devices, const [
          PairedDevice(shortId: 'ios-1', label: 'iPhone'),
        ]);
      },
    );

    test(
      'setRelay trims/saves the relay URL and checkRelay verifies health',
      () async {
        final relay = _FakeRelayGateway(
          currentRelayResult: const Success(null),
        );
        final vm =
            ConnectivityViewModel(
                relay,
                _FakePairingGatewayFactory(),
                _FakeRevokeGatewayFactory(),
              )
              ..relayUrl = 'https://old.example.test'
              ..healthState = HealthState.healthy;
        addTearDown(vm.dispose);

        final saved = await vm.setRelay('  https://new.example.test  ');
        await vm.checkRelay('  https://new.example.test  ');

        expect(saved, isTrue);
        expect(relay.setRelayCalls, ['https://new.example.test']);
        expect(relay.checkHealthCalls, ['https://new.example.test']);
        expect(vm.relayUrl, 'https://new.example.test');
        expect(vm.savingRelay, isFalse);
        expect(vm.healthState, HealthState.healthy);
        expect(vm.healthMessage, isNull);
      },
    );

    test(
      'PairingController disposal cancels the ephemeral pairing gateway',
      () async {
        final pairingFactory = _FakePairingGatewayFactory();
        final vm = ConnectivityViewModel(
          _FakeRelayGateway(),
          pairingFactory,
          _FakeRevokeGatewayFactory(),
        );
        addTearDown(vm.dispose);

        final controller = vm.newPairingController();
        await controller.start();
        controller.dispose();

        expect(pairingFactory.gateways, hasLength(1));
        expect(pairingFactory.gateways.single.startTtls, [
          const Duration(seconds: 120),
        ]);
        expect(pairingFactory.gateways.single.cancelCalls, 1);
      },
    );

    test(
      'RevokeController disposal suppresses late notifications after revoke completes',
      () async {
        final revokeFactory = _FakeRevokeGatewayFactory();
        final vm = ConnectivityViewModel(
          _FakeRelayGateway(),
          _FakePairingGatewayFactory(),
          revokeFactory,
        );
        addTearDown(vm.dispose);
        final controller = vm.newRevokeController();
        var notifications = 0;
        controller.addListener(() => notifications++);

        final run = controller.run(
          const PairedDevice(shortId: 'ios-1', label: 'iPhone'),
        );
        expect(revokeFactory.gateways.single.revokeCalls, ['ios-1']);
        expect(notifications, 1); // running state before disposal.

        controller.dispose();
        revokeFactory.gateways.single.complete(const Success(null));
        await run;

        expect(controller.stage, RevokeStage.done);
        expect(notifications, 1);
      },
    );
  });

  group('ConnectivitySettingsPanel widget wiring', () {
    testWidgets(
      'post-frame load, relay save, and relay check call the view model',
      (tester) async {
        final vm = _PanelConnectivityViewModel()
          ..relayUrl = 'https://old.example.test'
          ..relayLoad = ConnLoad.ready
          ..devicesLoad = ConnLoad.ready;

        await _pumpPanel(tester, vm);
        expect(vm.loadCalls, 1);

        await tester.enterText(
          find.byType(shadcn.TextField),
          'https://new.example.test',
        );
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.tap(find.text('Check'));
        await tester.pump();

        expect(vm.clearHealthCalls, 1);
        expect(vm.setRelayCalls, ['https://new.example.test']);
        expect(vm.checkRelayCalls, ['https://new.example.test']);
      },
    );

    testWidgets(
      'pairing dialog controller is started and disposed by the panel',
      (tester) async {
        final vm = _PanelConnectivityViewModel()
          ..relayUrl = 'https://relay.example.test'
          ..relayLoad = ConnLoad.ready
          ..devicesLoad = ConnLoad.ready;
        await _pumpPanel(tester, vm);

        await tester.tap(find.text('Pair new device'));
        await tester.pump();
        final controller = vm.pairingControllers.single;
        expect(controller.startCalls, 1);
        expect(controller.disposed, isFalse);

        await tester.tap(find.byIcon(shadcn.Icons.close));
        await tester.pumpAndSettle();

        expect(controller.disposed, isTrue);
      },
    );

    testWidgets('revoke dialog controller is run and disposed by the panel', (
      tester,
    ) async {
      final device = const PairedDevice(shortId: 'ios-1', label: 'iPhone');
      final vm = _PanelConnectivityViewModel()
        ..relayUrl = 'https://relay.example.test'
        ..relayLoad = ConnLoad.ready
        ..devicesLoad = ConnLoad.ready
        ..devices = [device];
      await _pumpPanel(tester, vm);

      await tester.tap(find.byIcon(shadcn.Icons.link_off));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      final controller = vm.revokeControllers.single;
      expect(controller.runDevices, [device]);
      expect(controller.disposed, isFalse);

      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(controller.disposed, isTrue);
      expect(vm.loadDevicesCalls, 1);
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ConnectivityViewModel viewModel,
) async {
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      provide: (s) =>
          s..addChangeNotifier<ConnectivityViewModel>(() => viewModel),
      child: (context, state) => const ConnectivitySettingsPanel(),
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
  await tester.pumpAndSettle();
}

final class _FakeRelayGateway implements RelayGateway {
  _FakeRelayGateway({
    this.currentRelayResult = const Success(null),
    this.devicesResult = const Success([]),
  });

  final Result<String?, RelayError> currentRelayResult;
  final Result<List<PairedDevice>, RelayError> devicesResult;

  int currentRelayCalls = 0;
  int listDevicesCalls = 0;
  final List<String> setRelayCalls = <String>[];
  final List<String> checkHealthCalls = <String>[];

  @override
  Future<Result<String?, RelayError>> currentRelay() async {
    currentRelayCalls++;
    return currentRelayResult;
  }

  @override
  Future<Result<void, RelayError>> setRelay(String url) async {
    setRelayCalls.add(url);
    return const Success(null);
  }

  @override
  Future<Result<List<PairedDevice>, RelayError>> listDevices() async {
    listDevicesCalls++;
    return devicesResult;
  }

  @override
  Future<Result<void, RelayError>> checkHealth(String url) async {
    checkHealthCalls.add(url);
    return const Success(null);
  }
}

final class _FakePairingGatewayFactory implements PairingGatewayFactory {
  final List<_FakePairingGateway> gateways = <_FakePairingGateway>[];

  @override
  PairingGateway create() {
    final gateway = _FakePairingGateway();
    gateways.add(gateway);
    return gateway;
  }
}

final class _FakePairingGateway implements PairingGateway {
  final StreamController<PairEvent> _events =
      StreamController<PairEvent>.broadcast();
  final List<Duration> startTtls = <Duration>[];
  int cancelCalls = 0;

  @override
  Stream<PairEvent> get events => _events.stream;

  @override
  Future<void> start({Duration ttl = const Duration(seconds: 120)}) async {
    startTtls.add(ttl);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    await _events.close();
  }
}

final class _FakeRevokeGatewayFactory implements RevokeGatewayFactory {
  final List<_FakeRevokeGateway> gateways = <_FakeRevokeGateway>[];

  @override
  RevokeGateway create() {
    final gateway = _FakeRevokeGateway();
    gateways.add(gateway);
    return gateway;
  }
}

final class _FakeRevokeGateway implements RevokeGateway {
  final Completer<Result<void, RelayError>> _result =
      Completer<Result<void, RelayError>>();
  final List<String> revokeCalls = <String>[];

  @override
  Future<Result<void, RelayError>> revoke(
    String shortId, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    revokeCalls.add(shortId);
    return _result.future;
  }

  void complete(Result<void, RelayError> result) => _result.complete(result);
}

final class _PanelConnectivityViewModel extends ConnectivityViewModel {
  _PanelConnectivityViewModel()
    : super(
        _FakeRelayGateway(),
        _FakePairingGatewayFactory(),
        _FakeRevokeGatewayFactory(),
      );

  int loadCalls = 0;
  int loadDevicesCalls = 0;
  int clearHealthCalls = 0;
  final List<String> setRelayCalls = <String>[];
  final List<String> checkRelayCalls = <String>[];
  final List<_TrackingPairingController> pairingControllers =
      <_TrackingPairingController>[];
  final List<_TrackingRevokeController> revokeControllers =
      <_TrackingRevokeController>[];

  @override
  Future<void> load() async {
    loadCalls++;
  }

  @override
  Future<void> loadDevices() async {
    loadDevicesCalls++;
  }

  @override
  Future<bool> setRelay(String url) async {
    final trimmed = url.trim();
    setRelayCalls.add(trimmed);
    relayUrl = trimmed;
    savingRelay = false;
    notifyListeners();
    return true;
  }

  @override
  Future<void> checkRelay(String url) async {
    checkRelayCalls.add(url.trim());
    healthState = HealthState.healthy;
    healthMessage = null;
    notifyListeners();
  }

  @override
  void clearHealth() {
    clearHealthCalls++;
    healthState = HealthState.unknown;
    healthMessage = null;
    notifyListeners();
  }

  @override
  PairingController newPairingController() {
    final controller = _TrackingPairingController();
    pairingControllers.add(controller);
    return controller;
  }

  @override
  RevokeController newRevokeController() {
    final controller = _TrackingRevokeController();
    revokeControllers.add(controller);
    return controller;
  }
}

final class _TrackingPairingController extends PairingController {
  _TrackingPairingController() : super(() => _FakePairingGateway());

  int startCalls = 0;
  bool disposed = false;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

final class _TrackingRevokeController extends RevokeController {
  _TrackingRevokeController() : super(_FakeRevokeGateway());

  final List<PairedDevice> runDevices = <PairedDevice>[];
  bool disposed = false;

  @override
  Future<void> run(PairedDevice device) async {
    runDevices.add(device);
    deviceName = device.label.isEmpty ? device.shortId : device.label;
    stage = RevokeStage.done;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
