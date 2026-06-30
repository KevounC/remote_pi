import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/ui/daemons_viewmodel.dart';
import 'package:cockpit/app/settings/ui/dialogs/daemon_editor_dialog.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class DaemonSettingsPanel extends StatefulWidget {
  const DaemonSettingsPanel({super.key});

  @override
  State<DaemonSettingsPanel> createState() => _DaemonSettingsPanelState();
}

class _DaemonSettingsPanelState extends State<DaemonSettingsPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DaemonsViewModel>().reload();
    });
    // Reflect state changes made outside this UI (crash/restart/uptime).
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<DaemonsViewModel>().refreshQuiet();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openEditor([DaemonInfo? editing]) async {
    final vm = context.read<DaemonsViewModel>();
    final result = await showDaemonEditorDialog(
      context,
      editing: editing,
      daemons: vm.daemons,
    );
    if (result == null || !mounted) return;
    if (editing == null) {
      await vm.create(result.cwd, name: result.name);
    } else {
      await vm.rename(editing, result.name);
    }
  }

  /// Restarting the supervisor is heavy (it drops every daemon), so confirm it.
  Future<void> _confirmRestartSupervisor() async {
    final vm = context.read<DaemonsViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Restart the supervisor?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          'Restarts the supervisor process (reloads the code). All daemons '
          'restart with it and go offline for a few seconds.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Restart',
              style: ctx.typo.body.copyWith(
                fontSize: 13,
                color: colors.warn,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.restartSupervisor();
  }

  Future<void> _confirmRemove(DaemonInfo daemon) async {
    final vm = context.read<DaemonsViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove daemon?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          '"${daemon.name}" stops running and leaves the registry. The folder and '
          'its local config are kept — you can recreate it later.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: ctx.typo.body.copyWith(
                fontSize: 13,
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.remove(daemon.id);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DaemonsViewModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.actionError != null) ...[
                SettingsErrorBanner(message: vm.actionError!),
                const SizedBox(height: 12),
              ],
              if (vm.online) ...[
                _DaemonActionsBar(
                  vm: vm,
                  onCreate: () => _openEditor(),
                  onRestartSupervisor: _confirmRestartSupervisor,
                ),
                const SizedBox(height: 16),
              ],
              SettingsSection(
                label: 'Always-on agents',
                trailing: SettingsReloadButton(
                  busy: vm.load == DaemonsLoad.loading,
                  onTap: vm.reload,
                ),
                child: _body(context, vm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DaemonsViewModel vm) {
    final colors = context.colors;

    if (!vm.online && vm.load != DaemonsLoad.loading) {
      return SettingsMessageCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.power_off_outlined, size: 16, color: colors.text3),
                const SizedBox(width: 8),
                Text(
                  'Supervisor offline',
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'pi-supervisord is not running. Install it with '
              '`remote-pi install` to manage 24/7 agents.',
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
      );
    }

    if (vm.load == DaemonsLoad.loading && vm.daemons.isEmpty) {
      return SettingsMessageCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            ),
            const SizedBox(width: 10),
            Text(
              'Loading…',
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text3,
              ),
            ),
          ],
        ),
      );
    }

    if (vm.load == DaemonsLoad.error && vm.daemons.isEmpty) {
      return SettingsMessageCard(
        child: Text(
          vm.error ?? 'Failed to list daemons.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.error,
          ),
        ),
      );
    }

    if (vm.daemons.isEmpty) {
      return SettingsMessageCard(
        child: Text(
          'No registered agents. Create one from a folder.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }

    return SettingsCard(
      children: [
        for (final daemon in vm.daemons)
          _DaemonTile(
            daemon: daemon,
            busy: vm.isBusy(daemon.id),
            onStart: () => vm.start(daemon.id),
            onStop: () => vm.stop(daemon.id),
            onRestart: () => vm.restart(daemon.id),
            onEdit: () => _openEditor(daemon),
            onRemove: () => _confirmRemove(daemon),
          ),
      ],
    );
  }
}

/// Action bar: create daemon, fleet controls, and supervisor restart.
class _DaemonActionsBar extends StatelessWidget {
  const _DaemonActionsBar({
    required this.vm,
    required this.onCreate,
    required this.onRestartSupervisor,
  });

  final DaemonsViewModel vm;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRestartSupervisor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasDaemons = vm.daemons.isNotEmpty;
    final fleetEnabled = hasDaemons && !vm.busyAll;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PrimaryButton(
          onPressed: () => onCreate(),
          leading: const Icon(Icons.add, size: 16),
          child: const Text('Create daemon'),
        ),
        if (vm.busyAll)
          CircularProgressIndicator(
            size: 15,
            strokeWidth: 2,
            color: colors.text3,
          ),
        _FleetButton(
          label: 'Start all',
          icon: Icons.play_arrow,
          onTap: fleetEnabled ? vm.startAll : null,
        ),
        _FleetButton(
          label: 'Stop all',
          icon: Icons.stop,
          onTap: fleetEnabled ? vm.stopAll : null,
        ),
        _FleetButton(
          label: 'Restart all',
          icon: Icons.restart_alt,
          onTap: fleetEnabled ? vm.restartAll : null,
        ),
        _FleetButton(
          label: 'Restart supervisor',
          icon: Icons.sync,
          tint: colors.warn,
          onTap: vm.busyAll ? null : onRestartSupervisor,
        ),
      ],
    );
  }
}

class _FleetButton extends StatelessWidget {
  const _FleetButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
  });

  final String label;
  final IconData icon;
  final Future<void> Function()? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final fg = enabled ? (tint ?? colors.text2) : colors.text4;
    return OutlineButton(
      onPressed: onTap == null ? null : () => onTap!(),
      leading: Icon(icon, size: 14, color: fg),
      child: Text(label, style: TextStyle(fontSize: 12.5, color: fg)),
    );
  }
}

/// One daemon row: state badge, name, metrics, and actions.
class _DaemonTile extends StatelessWidget {
  const _DaemonTile({
    required this.daemon,
    required this.busy,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onEdit,
    required this.onRemove,
  });

  final DaemonInfo daemon;
  final bool busy;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onRestart;
  final Future<void> Function() onEdit;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final running = daemon.state == DaemonState.running;
    final (Color dotColor, String stateLabel) = _stateView(
      context,
      daemon.state,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  daemon.name.isEmpty ? daemon.id : daemon.name,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(stateLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.mono.copyWith(
                    fontSize: 11,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _act(
                  context,
                  running ? Icons.stop : Icons.play_arrow,
                  running ? 'Stop' : 'Start',
                  running ? onStop : onStart,
                ),
                if (running)
                  _act(context, Icons.restart_alt, 'Restart', onRestart),
                _act(context, Icons.edit_outlined, 'Edit', onEdit),
                _act(context, Icons.delete_outline, 'Remove', onRemove),
              ],
            ),
        ],
      ),
    );
  }

  String _subtitle(String stateLabel) {
    final parts = <String>[stateLabel];
    if (daemon.pid != null) parts.add('pid ${daemon.pid}');
    if (daemon.uptimeSeconds != null) {
      parts.add(_fmtUptime(daemon.uptimeSeconds!));
    }
    if ((daemon.restartCount ?? 0) > 0) parts.add('↻${daemon.restartCount}');
    parts.add(daemon.cwd);
    return parts.join('  ·  ');
  }

  (Color, String) _stateView(BuildContext context, DaemonState state) {
    final colors = context.colors;
    return switch (state) {
      DaemonState.running => (colors.online, 'running'),
      DaemonState.starting => (colors.warn, 'starting'),
      DaemonState.stopped => (colors.text4, 'stopped'),
      DaemonState.crashed => (colors.error, 'failed'),
      DaemonState.unknown => (colors.text4, '—'),
    };
  }

  Widget _act(
    BuildContext context,
    IconData icon,
    String tip,
    Future<void> Function() onTap,
  ) {
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onTap(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

String _fmtUptime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h${minutes % 60}m';
  final days = hours ~/ 24;
  return '${days}d${hours % 24}h';
}
