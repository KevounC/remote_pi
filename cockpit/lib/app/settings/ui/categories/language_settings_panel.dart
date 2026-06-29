import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class LanguageSettingsPanel extends StatelessWidget {
  const LanguageSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SettingsController>();
    final settings = ctrl.settings;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSection(
            label: 'FORMATTING',
            child: SettingsCard(
              children: [
                SettingsRow(
                  title: 'Format on save',
                  description:
                      'Format the file automatically when you save (⌘S).',
                  trailing: Switch(
                    value: settings.formatOnSave,
                    onChanged: ctrl.setFormatOnSave,
                  ),
                ),
              ],
            ),
          ),
          SettingsSection(
            label: 'LANGUAGE SERVERS',
            child: SettingsCard(
              children: [
                for (final def in kLanguageDefs)
                  _LanguageRow(
                    key: ValueKey(def.id),
                    def: def,
                    overrideCommand: settings.lspCommands[def.id],
                    formatterCommand: settings.lspFormatters[def.id],
                    onChangedCommand: (v) => ctrl.setLspCommand(def.id, v),
                    onChangedFormatter: (v) => ctrl.setLspFormatter(def.id, v),
                  ),
              ],
            ),
          ),
          Text(
            'Errors and formatting use each language\'s language server. '
            'Cockpit does not install servers — it uses what is already on your '
            'machine. ● responds · ○ not found or invalid command (install the '
            'server or adjust the command).',
            style: context.typo.label.copyWith(color: context.colors.text3),
          ),
        ],
      ),
    );
  }
}

/// Linha de uma linguagem (tile expansível): nome + status (●/○) e, ao expandir,
/// o comando do language server + o comando do formatador externo (opcional). A
/// sonda do servidor roda ao montar e ao salvar.
class _LanguageRow extends StatefulWidget {
  const _LanguageRow({
    super.key,
    required this.def,
    required this.overrideCommand,
    required this.formatterCommand,
    required this.onChangedCommand,
    required this.onChangedFormatter,
  });

  final LanguageDef def;
  final String? overrideCommand;
  final String? formatterCommand;
  final ValueChanged<String?> onChangedCommand;
  final ValueChanged<String?> onChangedFormatter;

  @override
  State<_LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends State<_LanguageRow> {
  late final TextEditingController _serverCtrl;
  late final TextEditingController _formatterCtrl;
  bool? _available; // null = checando
  bool _expanded = false;
  bool _dirty = false;

  String get _default => <String>[
    widget.def.defaultExecutable,
    ...widget.def.defaultArgs,
  ].join(' ').trim();

  String get _savedServer => widget.overrideCommand ?? _default;
  String get _savedFormatter => widget.formatterCommand ?? '';

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: _savedServer)
      ..addListener(_onTextChanged);
    _formatterCtrl = TextEditingController(text: _savedFormatter)
      ..addListener(_onTextChanged);
    _detect();
  }

  @override
  void dispose() {
    _serverCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    _formatterCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final dirty =
        _serverCtrl.text.trim() != _savedServer.trim() ||
        _formatterCtrl.text.trim() != _savedFormatter.trim();
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  /// Sonda o comando do servidor salvo: spawna e verifica se fica vivo como um
  /// LSP de verdade (valida os argumentos, não só o binário no PATH).
  Future<void> _detect() async {
    setState(() => _available = null); // checando
    final ok = await probeLspCommand(_savedServer);
    if (mounted) setState(() => _available = ok);
  }

  /// Persiste comando do servidor + formatador (reinicia o LSP da linguagem via
  /// o listener do shell). Servidor igual ao default → limpa o override.
  void _save() {
    final server = _serverCtrl.text.trim();
    widget.onChangedCommand(
      server.isEmpty || server == _default ? null : server,
    );
    final formatter = _formatterCtrl.text.trim();
    widget.onChangedFormatter(formatter.isEmpty ? null : formatter);
    setState(() => _dirty = false);
    _detect();
  }

  /// Volta o servidor ao default e limpa o formatador (limpa ambos os overrides).
  void _reset() {
    _serverCtrl.text = _default;
    _formatterCtrl.text = '';
    widget.onChangedCommand(null);
    widget.onChangedFormatter(null);
    setState(() => _dirty = false);
    _detect();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho clicável: chevron + nome + extensões + status.
        HoverTap(
          onTap: () => setState(() => _expanded = !_expanded),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: colors.text3,
              ),
              const SizedBox(width: 8),
              Text(
                widget.def.label,
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '.${widget.def.extensions.join(' · .')}',
                style: context.typo.label.copyWith(color: colors.text4),
              ),
              const Spacer(),
              _StatusDot(available: _available),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel(context, 'Language server command'),
                const SizedBox(height: 6),
                _commandField(context, _serverCtrl, _default),
                const SizedBox(height: 14),
                _fieldLabel(context, 'Formatter command (optional)'),
                const SizedBox(height: 6),
                _commandField(
                  context,
                  _formatterCtrl,
                  'prettier --write %FILE%',
                ),
                const SizedBox(height: 4),
                Text(
                  'External formatter with %FILE% placeholder. Takes precedence '
                  'over the LSP formatter when set.',
                  style: context.typo.label.copyWith(color: colors.text4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    HoverTap(
                      borderRadius: BorderRadius.circular(7),
                      onTap: _reset,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        'Reset to default',
                        style: context.typo.body.copyWith(
                          fontSize: 12.5,
                          color: colors.text2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    HoverTap(
                      color: _dirty ? colors.accent : colors.panel3,
                      borderRadius: BorderRadius.circular(7),
                      onTap: _dirty ? _save : () {},
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      child: Text(
                        'Save & restart',
                        style: context.typo.body.copyWith(
                          fontSize: 12.5,
                          color: _dirty ? colors.accentText : colors.text4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) => Text(
    text,
    style: context.typo.label.copyWith(color: context.colors.text3),
  );

  Widget _commandField(
    BuildContext context,
    TextEditingController controller,
    String placeholder,
  ) => TextField(
    controller: controller,
    onSubmitted: (_) => _save(),
    style: context.typo.mono.copyWith(
      fontSize: 12.5,
      color: context.colors.text,
    ),
    placeholder: Text(placeholder),
    borderRadius: BorderRadius.circular(7),
  );
}

/// Bolinha de status do executável: verde (encontrado), cinza vazado (ausente),
/// cinza claro (checando).
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.available});
  final bool? available;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color color, String tip) = switch (available) {
      true => (const Color(0xFF22C55E), 'Server responds'),
      false => (colors.text4, 'Server not found or command invalid'),
      null => (colors.border, 'Checking…'),
    };
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tip)),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: available == false ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: available == false ? Border.all(color: color) : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conectividade
// ---------------------------------------------------------------------------
