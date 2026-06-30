import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/dialogs/cron_editor_dialog.dart';
import 'package:cockpit/app/settings/ui/dialogs/cron_formatting.dart';
import 'package:cockpit/app/settings/ui/dialogs/cron_log_dialog.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ScheduleSettingsPanel extends StatefulWidget {
  const ScheduleSettingsPanel({super.key});

  @override
  State<ScheduleSettingsPanel> createState() => _ScheduleSettingsPanelState();
}

class _ScheduleSettingsPanelState extends State<ScheduleSettingsPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CronViewModel>().reload();
    });
    // No supervisor push channel: poll so runs, next_run, and last_status made
    // outside this UI are reflected while the schedule panel is mounted.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<CronViewModel>().refreshQuiet();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openEditor() async {
    final vm = context.read<CronViewModel>();
    if (vm.daemons.isEmpty) return;
    final created = await showCronEditorDialog(context, viewModel: vm);
    if (created == true && mounted) await vm.reload();
  }

  Future<void> _openLog(CronJob job) async {
    final vm = context.read<CronViewModel>();
    await showCronLogDialog(context, viewModel: vm, job: job);
  }

  Future<void> _confirmRemove(CronJob job) async {
    final vm = context.read<CronViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove schedule?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          'The job "${job.schedule}" for ${vm.daemonName(job.daemonId)} is deleted. '
          'Its runs stop.',
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
    await vm.remove(job);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CronViewModel>();

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
                _cronActions(context, vm),
                const SizedBox(height: 16),
              ],
              SettingsSection(
                label: 'Scheduled prompts',
                trailing: SettingsReloadButton(
                  busy: vm.load == CronLoad.loading,
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

  Widget _cronActions(BuildContext context, CronViewModel vm) {
    final colors = context.colors;
    return Row(
      children: [
        PrimaryButton(
          onPressed: vm.hasDaemons ? () => _openEditor() : null,
          leading: const Icon(Icons.add, size: 16),
          child: const Text('Create schedule'),
        ),
        if (!vm.hasDaemons) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Create a Daemon Agent first.',
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context, CronViewModel vm) {
    final colors = context.colors;

    if (!vm.online && vm.load != CronLoad.loading) {
      return SettingsMessageCard(
        child: Text(
          'Supervisor offline. Schedules need pi-supervisord running '
          '(`remote-pi install`).',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }
    if (vm.load == CronLoad.loading && vm.jobs.isEmpty) {
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
    if (vm.load == CronLoad.error && vm.jobs.isEmpty) {
      return SettingsMessageCard(
        child: Text(
          vm.error ?? 'Failed to list schedules.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.error,
          ),
        ),
      );
    }
    if (vm.jobs.isEmpty) {
      return SettingsMessageCard(
        child: Text(
          'No schedules. Create a recurring prompt for a daemon.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }
    return SettingsCard(
      children: [
        for (final job in vm.jobs)
          _CronTile(
            job: job,
            daemonName: vm.daemonName(job.daemonId),
            busy: vm.isBusy(job.id),
            onToggle: (v) => vm.setEnabled(job, v),
            onRun: () => vm.run(job),
            onLog: () => _openLog(job),
            onRemove: () => _confirmRemove(job),
          ),
      ],
    );
  }
}

/// One schedule row: target daemon, cron expression, prompt, state, and actions.
class _CronTile extends StatelessWidget {
  const _CronTile({
    required this.job,
    required this.daemonName,
    required this.busy,
    required this.onToggle,
    required this.onRun,
    required this.onLog,
    required this.onRemove,
  });

  final CronJob job;
  final String daemonName;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final Future<void> Function() onRun;
  final Future<void> Function() onLog;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_outlined, size: 18, color: colors.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        daemonName,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.body.copyWith(
                          fontSize: 13.5,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      job.schedule,
                      style: context.typo.mono.copyWith(
                        fontSize: 11.5,
                        color: colors.accentText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  job.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 12.5,
                    color: colors.text2,
                  ),
                ),
                const SizedBox(height: 3),
                _CronMeta(job: job),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            )
          else ...[
            Switch(value: job.enabled, onChanged: onToggle),
            _cronAct(context, Icons.play_arrow, 'Run now', onRun),
            _cronAct(context, Icons.history, 'View log', onLog),
            _cronAct(context, Icons.delete_outline, 'Remove', onRemove),
          ],
        ],
      ),
    );
  }

  Widget _cronAct(
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

/// Job metadata line: next run and last result.
class _CronMeta extends StatelessWidget {
  const _CronMeta({required this.job});

  final CronJob job;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[];

    if (!job.enabled) {
      children.add(
        Text(
          'disabled',
          style: context.typo.label.copyWith(color: colors.text4),
        ),
      );
    } else if (job.nextRun != null) {
      children.add(
        Text(
          'next ${fmtIso(job.nextRun)}',
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      );
    }

    if (job.lastStatus != null) {
      final (color, label) = cronResultView(
        context,
        cronResultFromWire(job.lastStatus),
      );
      if (children.isNotEmpty) {
        children.add(
          Text(
            '  ·  ',
            style: context.typo.label.copyWith(color: colors.text4),
          ),
        );
      }
      children.add(
        Text('last: $label', style: context.typo.label.copyWith(color: color)),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
