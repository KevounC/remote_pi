import 'dart:io';

import 'package:cockpit/app/settings/ui/settings_category.dart';
import 'package:cockpit/app/settings/ui/settings_category_panel.dart';
import 'package:cockpit/app/settings/ui/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

void main() {
  test('settings route shell and category panel are importable', () {
    expect(const SettingsPage(), isA<SettingsPage>());
    expect(
      const SettingsCategoryPanel(category: SettingsCategory.appearance),
      isA<SettingsCategoryPanel>(),
    );
  });

  test('settings_page.dart is only the route shell', () {
    final source = File(
      'lib/app/settings/ui/settings_page.dart',
    ).readAsStringSync();

    expect(source, contains('class SettingsPage extends StatefulWidget'));
    expect(
      source,
      contains('class _SettingsPageState extends State<SettingsPage>'),
    );
    expect(source, contains('SettingsShell('));
    expect(source, contains('SettingsCategoryPanel(category: category)'));

    for (final forbidden in <String>[
      'AppearanceSettingsPanel',
      'LanguageSettingsPanel',
      'NotificationSettingsPanel',
      'ConnectivitySettingsPanel',
      'DaemonSettingsPanel',
      'ScheduleSettingsPanel',
      'AgendamentosPanel',
      'CronTile',
      'CronEditorDialog',
      'CronLogDialog',
      'DaemonTile',
      'PairingDialog',
      'switch (category)',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('SettingsCategoryPanel is the only category-to-panel switch', () {
    final page = File(
      'lib/app/settings/ui/settings_page.dart',
    ).readAsStringSync();
    final panel = File(
      'lib/app/settings/ui/settings_category_panel.dart',
    ).readAsStringSync();

    expect(page, isNot(contains('switch (category)')));
    expect(panel, contains('switch (category)'));
    expect(
      panel,
      contains(
        'SettingsCategory.appearance => const AppearanceSettingsPanel()',
      ),
    );
    expect(
      panel,
      contains('SettingsCategory.languages => const LanguageSettingsPanel()'),
    );
    expect(
      panel,
      contains(
        'SettingsCategory.notifications => const NotificationSettingsPanel()',
      ),
    );
    expect(
      panel,
      contains(
        'SettingsCategory.connectivity => const ConnectivitySettingsPanel()',
      ),
    );
    expect(
      panel,
      contains('SettingsCategory.daemons => const DaemonSettingsPanel()'),
    );
    expect(
      panel,
      contains('SettingsCategory.scheduling => const ScheduleSettingsPanel()'),
    );
  });

  test('nav metadata is derived from settings_category.dart registry', () {
    expect(SettingsCategory.values, hasLength(settingsCategoryMeta.length));
    for (final category in SettingsCategory.values) {
      final meta = settingsCategoryMeta[category];
      expect(meta, isNotNull, reason: category.name);
      expect(meta!.label, isNotEmpty);
      expect(meta.icon, isA<shadcn.IconData>());
    }

    expect(SettingsCategory.appearance.visibleWhen(false), isTrue);
    expect(SettingsCategory.languages.visibleWhen(false), isTrue);
    expect(SettingsCategory.notifications.visibleWhen(false), isTrue);
    expect(SettingsCategory.connectivity.visibleWhen(false), isFalse);
    expect(SettingsCategory.daemons.visibleWhen(false), isFalse);
    expect(SettingsCategory.scheduling.visibleWhen(false), isFalse);
    expect(SettingsCategory.scheduling.visibleWhen(true), isTrue);
  });

  test(
    'settings files do not import workspace document or session projection types',
    () {
      final settingsDir = Directory('lib/app/settings');
      final offenders = <String>[];
      for (final entity in settingsDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final source = entity.readAsStringSync();
        for (final forbidden in <String>[
          'WorkspaceDocument',
          'WorkspaceLayoutStore',
          'PaneNode',
          'CockpitSession',
        ]) {
          if (source.contains(forbidden)) {
            offenders.add('${entity.path}: $forbidden');
          }
        }
      }

      expect(offenders, isEmpty);
    },
  );
}
