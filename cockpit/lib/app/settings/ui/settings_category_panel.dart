import 'package:cockpit/app/settings/ui/categories/appearance_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/connectivity_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/daemon_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/language_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/notification_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/schedule_settings_panel.dart';
import 'package:cockpit/app/settings/ui/settings_category.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class SettingsCategoryPanel extends StatelessWidget {
  const SettingsCategoryPanel({required this.category, super.key});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) => switch (category) {
    SettingsCategory.appearance => const AppearanceSettingsPanel(),
    SettingsCategory.languages => const LanguageSettingsPanel(),
    SettingsCategory.notifications => const NotificationSettingsPanel(),
    SettingsCategory.connectivity => const ConnectivitySettingsPanel(),
    SettingsCategory.daemons => const DaemonSettingsPanel(),
    SettingsCategory.scheduling => const ScheduleSettingsPanel(),
  };
}
