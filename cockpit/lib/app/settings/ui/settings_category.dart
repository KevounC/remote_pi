import 'package:shadcn_flutter/shadcn_flutter.dart';

enum SettingsCategory {
  appearance,
  languages,
  notifications,
  connectivity,
  daemons,
  scheduling,
}

final class SettingsCategoryMeta {
  const SettingsCategoryMeta({
    required this.label,
    required this.icon,
    this.remote = false,
  });

  final String label;
  final IconData icon;
  final bool remote;
}

const settingsCategoryMeta = <SettingsCategory, SettingsCategoryMeta>{
  SettingsCategory.appearance: SettingsCategoryMeta(
    label: 'Appearance',
    icon: Icons.palette_outlined,
  ),
  SettingsCategory.languages: SettingsCategoryMeta(
    label: 'Language',
    icon: Icons.code,
  ),
  SettingsCategory.notifications: SettingsCategoryMeta(
    label: 'Notifications',
    icon: Icons.notifications_outlined,
  ),
  SettingsCategory.connectivity: SettingsCategoryMeta(
    label: 'Connectivity',
    icon: Icons.wifi_tethering,
    remote: true,
  ),
  SettingsCategory.daemons: SettingsCategoryMeta(
    label: 'Daemon Agents',
    icon: Icons.dns_outlined,
    remote: true,
  ),
  SettingsCategory.scheduling: SettingsCategoryMeta(
    label: 'Schedules',
    icon: Icons.schedule_outlined,
    remote: true,
  ),
};

extension SettingsCategoryVisibility on SettingsCategory {
  bool get isRemote => settingsCategoryMeta[this]!.remote;

  bool visibleWhen(bool remoteReady) => remoteReady || !isRemote;
}
