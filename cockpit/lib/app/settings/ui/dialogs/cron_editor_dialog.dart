import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/domain/cron_schedule.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/dialogs/cron_formatting.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Future<bool?> showCronEditorDialog(
  BuildContext context, {
  required CronViewModel viewModel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => CronEditorDialog(viewModel: viewModel),
  );
}

/// Dialog for creating a recurring daemon prompt.
///
/// The dialog calls [CronViewModel.create] directly so server validation errors
/// can be shown without losing the user's typed expression/prompt.
class CronEditorDialog extends StatefulWidget {
  const CronEditorDialog({required this.viewModel, super.key});

  final CronViewModel viewModel;

  @override
  State<CronEditorDialog> createState() => _CronEditorDialogState();
}

class _CronEditorDialogState extends State<CronEditorDialog> {
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
    _daemonId = widget.viewModel.daemons.first.id;
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
    return 'Next: ${fmtDateTime(next)}';
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
    final ok = await widget.viewModel.create(
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
        _localError =
            widget.viewModel.actionError ?? 'Failed to create the schedule.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = widget.viewModel;

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
              // Builder provides the chip RenderBox as menu anchor, not the
              // AlertDialog render box.
              Builder(
                builder: (chipContext) => SettingsDropdownChip(
                  label: vm.daemonName(_daemonId),
                  icon: Icons.dns_outlined,
                  onTap: () async {
                    final picked = await showAppMenu<String>(
                      chipContext,
                      minWidth: 220,
                      items: [
                        for (final daemon in vm.daemons)
                          AppMenuItem(
                            value: daemon.id,
                            label: daemon.name.isEmpty
                                ? daemon.id
                                : daemon.name,
                            selected: daemon.id == _daemonId,
                          ),
                      ],
                    );
                    if (!mounted) return;
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
