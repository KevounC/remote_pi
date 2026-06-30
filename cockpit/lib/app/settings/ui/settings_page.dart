import 'package:cockpit/app/settings/ui/settings_category.dart';
import 'package:cockpit/app/settings/ui/settings_category_panel.dart';
import 'package:cockpit/app/settings/ui/settings_env_gate.dart';
import 'package:cockpit/app/settings/ui/settings_shell.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Full-screen settings route shell.
///
/// Category navigation and environment gating stay here; each category's UI,
/// stateful timers, and dialogs live in category-specific widgets.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsCategory _category = SettingsCategory.appearance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsEnvGate>().check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final remoteReady = context.watch<SettingsEnvGate>().remoteReady;
    final category = _category.visibleWhen(remoteReady)
        ? _category
        : SettingsCategory.appearance;

    return SettingsShell(
      selected: category,
      remoteReady: remoteReady,
      onSelect: (next) => setState(() => _category = next),
      child: SettingsCategoryPanel(category: category),
    );
  }
}
