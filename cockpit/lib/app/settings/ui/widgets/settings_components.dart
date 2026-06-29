import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.label,
    required this.child,
    this.trailing,
    super.key,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: colors.border));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(children: rows),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    required this.trailing,
    this.description,
    super.key,
  });

  final String title;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}

class SettingsDropdownChip extends StatelessWidget {
  const SettingsDropdownChip({
    required this.label,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.text2),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: context.typo.body.copyWith(fontSize: 13, color: colors.text),
          ),
          const SizedBox(width: 6),
          Icon(Icons.keyboard_arrow_down, size: 16, color: colors.text3),
        ],
      ),
    );
  }
}

class SettingsReloadButton extends StatelessWidget {
  const SettingsReloadButton({required this.busy, required this.onTap, super.key});

  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: (context) => const TooltipContainer(child: Text('Reload')),
      child: HoverTap(
        borderRadius: BorderRadius.circular(6),
        onTap: busy ? null : () => onTap(),
        child: SizedBox(
          width: 26,
          height: 22,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(4),
                  child: CircularProgressIndicator(
                    size: 14,
                    strokeWidth: 2,
                    color: colors.text3,
                  ),
                )
              : Icon(Icons.refresh, size: 15, color: colors.text3),
        ),
      ),
    );
  }
}

class SettingsMessageCard extends StatelessWidget {
  const SettingsMessageCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class SettingsErrorBanner extends StatelessWidget {
  const SettingsErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 15, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.typo.label.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}
