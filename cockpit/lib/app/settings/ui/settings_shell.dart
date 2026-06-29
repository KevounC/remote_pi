import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/ui/widgets/window_controls.dart';
import 'package:cockpit/app/settings/ui/settings_category.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class SettingsShell extends StatelessWidget {
  const SettingsShell({
    required this.selected,
    required this.remoteReady,
    required this.onSelect,
    required this.child,
    super.key,
  });

  final SettingsCategory selected;
  final bool remoteReady;
  final ValueChanged<SettingsCategory> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      child: Column(
        children: [
          const SettingsHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsCategoryNav(
                  selected: selected,
                  remoteReady: remoteReady,
                  onSelect: onSelect,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WindowTitleBar(
      children: [
        const WindowControls(),
        const SizedBox(width: 14),
        Tooltip(
          tooltip: (context) => const TooltipContainer(child: Text('Back')),
          child: HoverTap(
            borderRadius: BorderRadius.circular(6),
            onTap: () => context.pop(),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(Icons.arrow_back, size: 18, color: colors.text2),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Settings',
          style: context.typo.title.copyWith(fontSize: 14, color: colors.text),
        ),
        const Spacer(),
        const WindowControlsTrailing(),
      ],
    );
  }
}

class SettingsCategoryNav extends StatelessWidget {
  const SettingsCategoryNav({
    required this.selected,
    required this.remoteReady,
    required this.onSelect,
    super.key,
  });

  final SettingsCategory selected;
  final bool remoteReady;
  final ValueChanged<SettingsCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visible = SettingsCategory.values
        .where((category) => category.visibleWhen(remoteReady))
        .toList(growable: false);
    final remoteStart = visible.indexWhere((category) => category.isRemote);
    final children = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      if (i == remoteStart) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Divider(height: 1, thickness: 1, color: colors.border),
          ),
        );
      }
      final category = visible[i];
      final meta = settingsCategoryMeta[category]!;
      children.add(
        _NavItem(
          icon: meta.icon,
          label: meta.label,
          selected: selected == category,
          onTap: () => onSelect(category),
        ),
      );
    }
    return Container(
      width: 210,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(children: children),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? colors.accentText : colors.text3,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: selected ? colors.text : colors.text2,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
