import 'dart:async';

import 'package:cockpit/app/settings/domain/cron_schedule.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/settings/ui/categories/appearance_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/connectivity_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/daemon_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/language_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/notification_settings_panel.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/settings_category.dart';
import 'package:cockpit/app/settings/ui/settings_env_gate.dart';
import 'package:cockpit/app/settings/ui/settings_shell.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tela cheia de Configurações (push). Categorias à esquerda (Aparência ·
/// Conectividade) e o conteúdo à direita. Por ora só **Aparência** está
/// implementada; Conectividade chega na próxima fase.
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
    // Sonda o ambiente para decidir se as abas remotas aparecem.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsEnvGate>().check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final remoteReady = context.watch<SettingsEnvGate>().remoteReady;
    // Categoria selecionada caiu (ambiente sumiu) → volta pra Aparência.
    final category = _category.visibleWhen(remoteReady)
        ? _category
        : SettingsCategory.appearance;

    return SettingsShell(
      selected: category,
      remoteReady: remoteReady,
      onSelect: (c) => setState(() => _category = c),
      child: switch (category) {
        SettingsCategory.appearance => const AppearanceSettingsPanel(),
        SettingsCategory.languages => const LanguageSettingsPanel(),
        SettingsCategory.notifications => const NotificationSettingsPanel(),
        SettingsCategory.connectivity => const ConnectivitySettingsPanel(),
        SettingsCategory.daemons => const DaemonSettingsPanel(),
        SettingsCategory.scheduling => const _AgendamentosPanel(),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Agendamentos (cron — plan/39)
// ---------------------------------------------------------------------------
class _AgendamentosPanel extends StatefulWidget {
  const _AgendamentosPanel();

  @override
  State<_AgendamentosPanel> createState() => _AgendamentosPanelState();
}

class _AgendamentosPanelState extends State<_AgendamentosPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CronViewModel>().reload();
    });
    // Sem push do supervisor: refaz o list a cada 10s pra refletir disparos
    // agendados, next_run e last_status que mudam fora da UI.
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
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CronEditorDialog(vm: vm),
    );
    if (created == true && mounted) await vm.reload();
  }

  Future<void> _openLog(CronJob job) async {
    final vm = context.read<CronViewModel>();
    await showDialog<void>(
      context: context,
      builder: (_) => _CronLogDialog(vm: vm, job: job),
    );
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

/// Uma linha de agendamento: alvo + schedule + prompt + estado + ações.
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

/// Linha de metadados do job: próximo disparo + último status.
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
          'next ${_fmtIso(job.nextRun)}',
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      );
    }

    if (job.lastStatus != null) {
      final (color, label) = _cronResultView(
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

/// Dialog de criar agendamento: daemon + cron-expr (com preview) + prompt +
/// opções. Chama `vm.create` direto pra mostrar erro do servidor sem perder o
/// que foi digitado.
class _CronEditorDialog extends StatefulWidget {
  const _CronEditorDialog({required this.vm});
  final CronViewModel vm;

  @override
  State<_CronEditorDialog> createState() => _CronEditorDialogState();
}

class _CronEditorDialogState extends State<_CronEditorDialog> {
  final TextEditingController _expr = TextEditingController();
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _tz = TextEditingController();
  late String _daemonId;
  bool _skipIfBusy = true;
  bool _wake = false;
  bool _catchup = false;
  bool _saving = false;
  String? _localError;

  static const _examples = <(String, String)>[
    ('0 9 * * *', 'every day 9am'),
    ('0 * * * *', 'hourly'),
    ('*/15 * * * *', 'every 15 min'),
    ('0 18 * * 1-5', 'weekdays 6pm'),
  ];

  @override
  void initState() {
    super.initState();
    _daemonId = widget.vm.daemons.first.id;
    _expr.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _expr.dispose();
    _prompt.dispose();
    _tz.dispose();
    super.dispose();
  }

  String get _previewText {
    final expr = _expr.text.trim();
    if (expr.isEmpty) return 'Next run shows up here';
    final next = nextCronRun(expr, DateTime.now());
    if (next == null) return 'Next: computed on save';
    return 'Next: ${_fmtDateTime(next)}';
  }

  Future<void> _submit() async {
    final expr = _expr.text.trim();
    final prompt = _prompt.text.trim();
    if (expr.isEmpty || prompt.isEmpty) {
      setState(() => _localError = 'Fill in the expression and the prompt.');
      return;
    }
    setState(() {
      _saving = true;
      _localError = null;
    });
    final tz = _tz.text.trim();
    final ok = await widget.vm.create(
      daemonId: _daemonId,
      schedule: expr,
      prompt: prompt,
      tz: tz.isEmpty ? null : tz,
      skipIfBusy: _skipIfBusy,
      wake: _wake,
      catchup: _catchup,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _localError = widget.vm.actionError ?? 'Failed to create the schedule.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = widget.vm;

    return AlertDialog(
      title: Text(
        'New schedule',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(context, 'Daemon'),
              const SizedBox(height: 6),
              // Builder garante um BuildContext cujo RenderBox é o próprio chip,
              // não o do AlertDialog — senão o menu ancora fora do dialog.
              Builder(
                builder: (chipContext) => SettingsDropdownChip(
                  label: vm.daemonName(_daemonId),
                  icon: Icons.dns_outlined,
                  onTap: () async {
                    final picked = await showAppMenu<String>(
                      chipContext,
                      minWidth: 220,
                      items: [
                        for (final d in vm.daemons)
                          AppMenuItem(
                            value: d.id,
                            label: d.name.isEmpty ? d.id : d.name,
                            selected: d.id == _daemonId,
                          ),
                      ],
                    );
                    if (picked != null) setState(() => _daemonId = picked);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, 'When (cron expression)'),
              const SizedBox(height: 6),
              _dialogField(context, _expr, 'e.g. 0 9 * * *', mono: true),
              const SizedBox(height: 6),
              Text(
                _previewText,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (expr, label) in _examples)
                    _ExampleChip(
                      expr: expr,
                      label: label,
                      onTap: () {
                        _expr.text = expr;
                        _expr.selection = TextSelection.collapsed(
                          offset: expr.length,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, 'Prompt'),
              const SizedBox(height: 6),
              _dialogField(
                context,
                _prompt,
                'e.g. Summarize the new PRs',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, 'Timezone (optional)'),
              const SizedBox(height: 6),
              _dialogField(
                context,
                _tz,
                'e.g. America/Sao_Paulo (empty = system)',
                mono: true,
              ),
              const SizedBox(height: 12),
              _CronOptionSwitch(
                label: 'Skip if the agent is busy',
                value: _skipIfBusy,
                onChanged: (v) => setState(() => _skipIfBusy = v),
              ),
              _CronOptionSwitch(
                label: 'Wake the daemon if stopped',
                value: _wake,
                onChanged: (v) => setState(() => _wake = v),
              ),
              _CronOptionSwitch(
                label: 'Recover 1 missed run (catchup)',
                value: _catchup,
                onChanged: (v) => setState(() => _catchup = v),
              ),
              if (_localError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _localError!,
                  style: context.typo.label.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
        GhostButton(
          onPressed: _saving ? null : _submit,
          child: Text(
            _saving ? 'Creating…' : 'Create',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) => Text(
    text,
    style: context.typo.label.copyWith(color: context.colors.text3),
  );

  Widget _dialogField(
    BuildContext context,
    TextEditingController controller,
    String hint, {
    bool mono = false,
    int maxLines = 1,
  }) {
    final colors = context.colors;
    final style = mono
        ? context.typo.mono.copyWith(fontSize: 12.5, color: colors.text)
        : context.typo.body.copyWith(fontSize: 13.5, color: colors.text);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: style,
      placeholder: Text(hint),
      borderRadius: BorderRadius.circular(7),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({
    required this.expr,
    required this.label,
    required this.onTap,
  });
  final String expr;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: context.typo.label.copyWith(color: colors.text2),
      ),
    );
  }
}

class _CronOptionSwitch extends StatelessWidget {
  const _CronOptionSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text2,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Dialog de histórico de um job (lê `cron.jsonl` via `cron_log`).
class _CronLogDialog extends StatefulWidget {
  const _CronLogDialog({required this.vm, required this.job});
  final CronViewModel vm;
  final CronJob job;

  @override
  State<_CronLogDialog> createState() => _CronLogDialogState();
}

class _CronLogDialogState extends State<_CronLogDialog> {
  List<CronLogEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.vm.fetchLog(jobId: widget.job.id);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _error = entries == null
          ? (widget.vm.actionError ?? 'Failed to read the log.')
          : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        'History — ${widget.job.schedule}',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(width: 460, child: _content(context)),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            size: 22,
            strokeWidth: 2,
            color: colors.text3,
          ),
        ),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: context.typo.body.copyWith(fontSize: 13.5, color: colors.error),
      );
    }
    final entries = _entries ?? const <CronLogEntry>[];
    if (entries.isEmpty) {
      return Text(
        'No records yet.',
        style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text3),
      );
    }
    // Mais recentes primeiro.
    final ordered = entries.reversed.toList(growable: false);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
        itemBuilder: (context, i) {
          final e = ordered[i];
          final (color, label) = _cronResultView(context, e.result);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: context.typo.body.copyWith(
                              fontSize: 12.5,
                              color: color,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _fmtTs(e.tsMs),
                            style: context.typo.mono.copyWith(
                              fontSize: 11,
                              color: colors.text3,
                            ),
                          ),
                        ],
                      ),
                      if (e.promptPreview.isNotEmpty)
                        Text(
                          e.promptPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.label.copyWith(
                            color: colors.text3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---- cron helpers ----------------------------------------------------------

(Color, String) _cronResultView(BuildContext context, CronResult r) {
  final colors = context.colors;
  return switch (r) {
    CronResult.delivered => (colors.online, 'delivered'),
    CronResult.wokeAndDelivered => (colors.online, 'woke + delivered'),
    CronResult.deliverFailed => (colors.error, 'failed'),
    CronResult.skippedBusy => (colors.warn, 'skipped (busy)'),
    CronResult.skippedDown => (colors.text4, 'skipped (stopped)'),
    CronResult.skippedDisabled => (colors.text4, 'skipped (disabled)'),
    CronResult.unknown => (colors.text4, '—'),
  };
}

String _fmt2(int n) => n.toString().padLeft(2, '0');

String _fmtDateTime(DateTime dt) {
  final l = dt.toLocal();
  return '${_fmt2(l.day)}/${_fmt2(l.month)} ${_fmt2(l.hour)}:${_fmt2(l.minute)}';
}

String _fmtIso(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  return dt == null ? iso : _fmtDateTime(dt);
}

String _fmtTs(int ms) => _fmtDateTime(DateTime.fromMillisecondsSinceEpoch(ms));
