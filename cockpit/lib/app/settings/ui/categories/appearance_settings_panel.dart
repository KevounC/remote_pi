import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class AppearanceSettingsPanel extends StatelessWidget {
  const AppearanceSettingsPanel({super.key});

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
                label: 'Theme',
                child: SettingsCard(
                  children: [
                    SettingsRow(
                      title: 'Theme',
                      trailing: _ThemeDropdown(
                        value: s.themeMode,
                        onChanged: controller.setThemeMode,
                      ),
                    ),
                  ],
                ),
              ),
              SettingsSection(
                label: 'Fonts',
                child: SettingsCard(
                  children: [
                    SettingsRow(
                      title: 'Interface font',
                      description:
                          'Used across the whole app. Empty = system default.',
                      trailing: _FontField(
                        value: s.interfaceFont,
                        hint: 'Space Grotesk · Hanken',
                        onChanged: controller.setInterfaceFont,
                      ),
                    ),
                    SettingsRow(
                      title: 'Interface size',
                      trailing: _SizeStepper(
                        value: s.interfaceSize,
                        min: 11,
                        max: 22,
                        onChanged: controller.setInterfaceSize,
                      ),
                    ),
                    SettingsRow(
                      title: 'Code font',
                      description: 'Code and diffs. Empty = system default.',
                      trailing: _FontField(
                        value: s.codeFont,
                        hint: 'JetBrains Mono',
                        onChanged: controller.setCodeFont,
                      ),
                    ),
                    SettingsRow(
                      title: 'Code size',
                      trailing: _SizeStepper(
                        value: s.codeSize,
                        min: 9,
                        max: 20,
                        onChanged: controller.setCodeSize,
                      ),
                    ),
                    SettingsRow(
                      title: 'Terminal font',
                      description:
                          'Uses the code size. Empty = system default.',
                      trailing: _FontField(
                        value: s.terminalFont,
                        hint: 'Menlo · monospace',
                        onChanged: controller.setTerminalFont,
                      ),
                    ),
                  ],
                ),
              ),
              SettingsSection(
                label: 'Syntax',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsCard(
                      children: [
                        SettingsRow(
                          title: 'Highlight theme',
                          description:
                              'Code colors, independent of the app theme.',
                          trailing: _SyntaxDropdown(
                            value: s.syntaxTheme,
                            onChanged: controller.setSyntaxTheme,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const _SyntaxPreview(),
                  ],
                ),
              ),
              SettingsSection(
                label: 'Conversation',
                child: SettingsCard(
                  children: [
                    SettingsRow(
                      title: 'Pin user message',
                      description:
                          'The question stays fixed at the top while the answer '
                          'scrolls.',
                      trailing: Switch(
                        value: s.pinUserMessage,
                        onChanged: controller.setPinUserMessage,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// Aba **Notifications** (sempre visível). Liga/desliga as notificações de fim
/// de turno (persistido em `AppSettings`) e, no macOS, mostra o estado da
/// permissão do SO + botão pra pedi-la.
class _SyntaxPreview extends StatelessWidget {
  const _SyntaxPreview();

  static const String _sample =
      '{\n'
      '  "name": "cockpit",\n'
      '  "version": 2,\n'
      '  "active": true,\n'
      '  "tags": ["dev", "ui"]\n'
      '}';

  @override
  Widget build(BuildContext context) {
    final syntax = context.syntax;
    final base = context.typo.mono.copyWith(
      fontSize: 12.5,
      height: 1.5,
      color: syntax.base,
    );
    final span = buildCodeSpan(
      context,
      source: _sample,
      language: 'json',
      baseStyle: base,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: syntax.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: span == null ? Text(_sample, style: base) : Text.rich(span),
    );
  }
}

/// Gatilho de dropdown (rótulo + chevron) que abre o `showAppMenu`.
class _ThemeDropdown extends StatelessWidget {
  const _ThemeDropdown({required this.value, required this.onChanged});
  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const _meta = <AppThemeMode, ({String label, IconData icon})>{
    AppThemeMode.system: (
      label: 'System',
      icon: Icons.desktop_windows_outlined,
    ),
    AppThemeMode.light: (label: 'Light', icon: Icons.light_mode_outlined),
    AppThemeMode.dark: (label: 'Dark', icon: Icons.dark_mode_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final current = _meta[value]!;
    return SettingsDropdownChip(
      icon: current.icon,
      label: current.label,
      onTap: () async {
        final picked = await showAppMenu<AppThemeMode>(
          context,
          minWidth: 180,
          items: [
            for (final e in _meta.entries)
              AppMenuItem(
                value: e.key,
                label: e.value.label,
                icon: e.value.icon,
                selected: e.key == value,
              ),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _SyntaxDropdown extends StatelessWidget {
  const _SyntaxDropdown({required this.value, required this.onChanged});
  final SyntaxThemeId value;
  final ValueChanged<SyntaxThemeId> onChanged;

  static const _labels = <SyntaxThemeId, String>{
    SyntaxThemeId.one: 'One',
    SyntaxThemeId.dracula: 'Dracula',
    SyntaxThemeId.github: 'GitHub',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsDropdownChip(
      label: _labels[value]!,
      onTap: () async {
        final picked = await showAppMenu<SyntaxThemeId>(
          context,
          minWidth: 180,
          items: [
            for (final e in _labels.entries)
              AppMenuItem(
                value: e.key,
                label: e.value,
                selected: e.key == value,
              ),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Campo de família de fonte (texto livre; vazio = padrão).
class _FontField extends StatefulWidget {
  const _FontField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });
  final String? value;
  final String hint;
  final ValueChanged<String?> onChanged;

  @override
  State<_FontField> createState() => _FontFieldState();
}

class _FontFieldState extends State<_FontField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 240,
      child: TextField(
        controller: _ctrl,
        onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v.trim()),
        style: context.typo.body.copyWith(fontSize: 13, color: colors.text),
        placeholder: Text(widget.hint),
        borderRadius: BorderRadius.circular(7),
      ),
    );
  }
}

/// Stepper de tamanho ( − valor + ) com sufixo "px".
class _SizeStepper extends StatelessWidget {
  const _SizeStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(context, Icons.remove, () {
            if (value > min) onChanged((value - 1).clamp(min, max));
          }),
          SizedBox(
            width: 44,
            child: Text(
              '${value.round()} px',
              textAlign: TextAlign.center,
              style: context.typo.mono.copyWith(
                fontSize: 12.5,
                color: colors.text,
              ),
            ),
          ),
          _btn(context, Icons.add, () {
            if (value < max) onChanged((value + 1).clamp(min, max));
          }),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, IconData icon, VoidCallback onTap) {
    return HoverTap(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 32,
        child: Icon(icon, size: 15, color: context.colors.text2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language (LSP)
// ---------------------------------------------------------------------------

/// Configura o comando do language server (LSP) de cada linguagem. Vem
/// pré-preenchido com o default do catálogo; o usuário pode sobrescrever (ex.:
/// caminho custom do binário). Um indicador mostra se o executável está no PATH
/// — comunica por que uma linguagem mostra erros e outra não, sem prometer
/// mágica (Cockpit não instala servidores; só usa o que está na máquina).
