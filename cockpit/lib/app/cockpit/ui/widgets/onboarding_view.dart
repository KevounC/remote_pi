import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/install_result.dart';
import 'package:cockpit/app/cockpit/domain/entities/setup_check.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/macos_notification_instructions_dialog.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tela inicial (sem workspace): passo-a-passo de preparação do ambiente. Só
/// quando os 5 passos estão satisfeitos o botão "Criar Workspace" habilita.
///
/// Re-checa as permissões quando a janela volta a ter foco (o usuário sai pros
/// Ajustes do Sistema e volta) e oferece re-checagem manual por passo.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key, required this.onCreateWorkspace});

  /// Dispara o fluxo de criação (escolher pasta → dialog → criar).
  final Future<void> Function() onCreateWorkspace;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SetupViewModel>().recheckAll();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou o foco → permissões podem ter mudado nos Ajustes do Sistema.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SetupViewModel>().recheckPermissions();
    }
  }

  /// Abre o dialog de instalação (spinner → resultado). A re-checagem do passo
  /// acontece dentro do [runner] (no ViewModel), então ao fechar o card já
  /// reflete o novo status.
  Future<void> _install(
    BuildContext context, {
    required String title,
    required Future<InstallResult> Function() runner,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x99000000),
      builder: (_) => _InstallDialog(title: title, runner: runner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = context.watch<SetupViewModel>();

    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.rocket_launch_outlined,
                      color: colors.accentText,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Welcome to Cockpit',
                      style: context.typo.title.copyWith(
                        fontSize: 20,
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Before creating a workspace, let\'s prepare the environment. '
                  'Complete the steps below.',
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text2,
                  ),
                ),
                const SizedBox(height: 22),
                _StepCard(
                  index: 1,
                  title: 'Pi Code installed',
                  description: 'The `pi` binary must be accessible.',
                  status: vm.pi,
                  onRecheck: vm.recheckPi,
                ),
                _StepCard(
                  index: 2,
                  title: 'remote-pi extension on Pi',
                  description: 'Registered in ~/.pi/agent/settings.json.',
                  status: vm.extension,
                  onRecheck: vm.recheckExtension,
                  action: _StepAction(
                    label: 'Install',
                    onTap: () => _install(
                      context,
                      title: 'Install remote-pi extension',
                      runner: vm.installExtension,
                    ),
                  ),
                ),
                _StepCard(
                  index: 3,
                  title: 'Supervisor installed',
                  description: 'pi-supervisord service (remote-pi install).',
                  status: vm.supervisor,
                  onRecheck: vm.recheckSupervisor,
                  // Sem a extensão não há index.js pra rodar o instalador.
                  action: vm.extension == CheckStatus.ok
                      ? _StepAction(
                          label: 'Install',
                          onTap: () => _install(
                            context,
                            title: 'Install supervisor',
                            runner: vm.installSupervisor,
                          ),
                        )
                      : null,
                ),
                _StepCard(
                  index: 4,
                  title: 'Notifications',
                  description: 'Alerts when an agent finishes a turn.',
                  status: vm.notifications,
                  onRecheck: vm.recheckNotifications,
                  action: _StepAction(
                    label: 'Test',
                    onTap: () async {
                      await vm.requestNotifications();
                      if (Platform.isMacOS &&
                          vm.notifications == CheckStatus.missing) {
                        if (context.mounted) {
                          MacosNotificationInstructionsDialog.show(context);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 22),
                _CreateButton(
                  enabled: vm.canCreate,
                  onTap: widget.onCreateWorkspace,
                ),
                if (!vm.canCreate) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Complete the steps above to enable creation.',
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ação secundária de um passo (ex.: "Testar", "Abrir Ajustes").
class _StepAction {
  const _StepAction({required this.label, required this.onTap});
  final String label;
  final Future<void> Function() onTap;
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.description,
    required this.status,
    required this.onRecheck,
    this.action,
  });

  final int index;
  final String title;
  final String description;
  final CheckStatus status;
  final Future<void> Function() onRecheck;
  final _StepAction? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Exibe a ação quando:
    // - missing: precisa instalar/conceder
    // - checking: pode pular a espera e já pedir ação diretamente
    final showAction =
        action != null &&
        (status == CheckStatus.missing || status == CheckStatus.checking);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _StatusDot(status: status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$index. $title',
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ),
          ),
          if (showAction) ...[
            _PillButton(label: action!.label, onTap: action!.onTap),
            const SizedBox(width: 4),
          ],
          if (status != CheckStatus.notApplicable)
            Tooltip(
              tooltip: (context) =>
                  const TooltipContainer(child: Text('Check again')),
              child: HoverTap(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onRecheck(),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.refresh, size: 16, color: colors.text3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Indicador de estado: spinner / check verde / x vermelho-claro / dispensado.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final CheckStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    switch (status) {
      case CheckStatus.checking:
        return const SizedBox(
          width: 18,
          height: 18,
          child: Center(child: CircularProgressIndicator(size: 14)),
        );
      case CheckStatus.ok:
        return Icon(Icons.check_circle, size: 20, color: colors.online);
      case CheckStatus.missing:
        return Icon(
          Icons.cancel,
          size: 20,
          color: colors.error.withValues(alpha: 0.85),
        );
      case CheckStatus.notApplicable:
        return Tooltip(
          tooltip: (context) =>
              const TooltipContainer(child: Text('Not required in this setup')),
          child: Icon(
            Icons.remove_circle_outline,
            size: 20,
            color: colors.text4,
          ),
        );
    }
  }
}

/// Botão-pílula matte pras ações de passo (Testar / Abrir Ajustes).
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      onTap: () => onTap(),
      child: Text(
        label,
        style: context.typo.label.copyWith(
          color: colors.text2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.enabled, required this.onTap});
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        onPressed: enabled ? () => onTap() : null,
        leading: const Icon(Icons.add, size: 16),
        child: const Text('Create Workspace'),
      ),
    );
  }
}

/// Dialog simples de instalação: dispara o [runner] ao montar, mostra spinner
/// enquanto roda e, ao terminar, o resultado (sucesso/erro). Botão "Fechar" só
/// habilita no fim.
class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.title, required this.runner});

  final String title;
  final Future<InstallResult> Function() runner;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  InstallResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result = await widget.runner();
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = _result;

    return AlertDialog(
      title: Text(
        widget.title,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 380,
        child: result == null
            ? Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(child: CircularProgressIndicator(size: 14)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Installing…',
                    style: context.typo.body.copyWith(
                      fontSize: 13.5,
                      color: colors.text2,
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    result.ok ? Icons.check_circle : Icons.error,
                    size: 20,
                    color: result.ok ? colors.online : colors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result.ok ? 'Installed successfully.' : result.detail,
                      style: context.typo.body.copyWith(
                        fontSize: 13.5,
                        color: colors.text2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        GhostButton(
          onPressed: result == null ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: result == null ? colors.text4 : colors.text2,
            ),
          ),
        ),
      ],
    );
  }
}
