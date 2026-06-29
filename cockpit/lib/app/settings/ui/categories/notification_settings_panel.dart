import 'dart:io';

import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/macos_notification_instructions_dialog.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class NotificationSettingsPanel extends StatelessWidget {
  const NotificationSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSection(
                label: 'Notifications',
                child: SettingsCard(
                  children: [
                    SettingsRow(
                      title: 'Enable notifications',
                      description:
                          'Alert me when an agent finishes a turn and the window '
                          'is not focused.',
                      trailing: Switch(
                        value: s.notificationsEnabled,
                        onChanged: controller.setNotificationsEnabled,
                      ),
                    ),
                    if (Platform.isMacOS && s.notificationsEnabled)
                      const _NotificationPermissionRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado da permissão de notificação do macOS + botão para solicitá-la. Sonda
/// ao montar; ao pedir, dispara uma notificação de teste e, se ainda negada,
/// abre as instruções do System Settings.
class _NotificationPermissionRow extends StatefulWidget {
  const _NotificationPermissionRow();

  @override
  State<_NotificationPermissionRow> createState() =>
      _NotificationPermissionRowState();
}

class _NotificationPermissionRowState
    extends State<_NotificationPermissionRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsViewModel>().check();
    });
  }

  Future<void> _request() async {
    final status = await context.read<NotificationsViewModel>().request();
    if (!mounted) return;
    if (status == CheckStatus.missing) {
      MacosNotificationInstructionsDialog.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final granted =
        context.watch<NotificationsViewModel>().status == CheckStatus.ok;
    return SettingsRow(
      title: 'System permission',
      description: granted
          ? 'Cockpit is allowed to send notifications.'
          : 'macOS has not granted notification access yet.',
      trailing: granted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 18, color: colors.online),
                const SizedBox(width: 6),
                Text(
                  'Granted',
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              ],
            )
          : SecondaryButton(
              onPressed: _request,
              child: const Text('Request permission'),
            ),
    );
  }
}

/// Amostra de código realçada com o tema de syntax atual (atualiza ao trocar o
/// dropdown). Usa o `context.syntax` (fundo + cores) e o `buildCodeSpan`.
