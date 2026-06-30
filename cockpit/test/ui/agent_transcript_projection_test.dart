import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_transcript.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('renders projected tool completion and error states', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await _pumpTranscript(
      tester,
      AgentTranscript(
        entries: <Object>[
          ProjectedToolMessage(
            callId: 'tool-1',
            name: 'read_file',
            args: const <String, dynamic>{'path': 'README.md'},
            status: ToolProjectionStatus.completed,
            resultText: 'ok',
          ),
          ProjectedToolMessage(
            callId: 'tool-2',
            name: 'write_file',
            args: const <String, dynamic>{'path': 'BROKEN.md'},
            status: ToolProjectionStatus.error,
            resultText: 'failed',
          ),
        ],
        controller: scroll,
      ),
    );

    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('write_file'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.text('read_file'));
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsOneWidget);

    await tester.tap(find.text('write_file'));
    await tester.pumpAndSettle();
    expect(find.text('failed'), findsOneWidget);
  });
}

Future<void> _pumpTranscript(WidgetTester tester, Widget child) async {
  final settings = SettingsController(_MemorySettingsStore());
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      provide: (s) => s..addChangeNotifier<SettingsController>(() => settings),
      child: (context, state) => child,
    ),
  );
  final app = createModule(register: (c) => c.module(feature));
  final boot = bootstrapModule(app);

  await tester.pumpWidget(
    ShadcnApp.router(
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

final class _MemorySettingsStore implements SettingsStore {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}
