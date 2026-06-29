import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/settings/ui/connectivity_viewmodel.dart';
import 'package:cockpit/app/settings/ui/pairing_dialog.dart';
import 'package:cockpit/app/settings/ui/revoke_dialog.dart';
import 'package:cockpit/app/settings/ui/widgets/settings_components.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ConnectivitySettingsPanel extends StatefulWidget {
  const ConnectivitySettingsPanel({super.key});

  @override
  State<ConnectivitySettingsPanel> createState() =>
      _ConnectivitySettingsPanelState();
}

class _ConnectivitySettingsPanelState extends State<ConnectivitySettingsPanel> {
  @override
  void initState() {
    super.initState();
    // Carrega relay + aparelhos quando a aba abre (lazy — não roda o shell-out
    // do `remote-pi` se o usuário só visita Aparência).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ConnectivityViewModel>().load();
    });
  }

  /// Abre o dialog de pareamento (sobe um `pi --mode rpc` efêmero). Quando um
  /// aparelho parear, o dialog fecha com `true` e a lista é recarregada.
  Future<void> _openPairing() async {
    final vm = context.read<ConnectivityViewModel>();
    // O controller é dono do `pi --mode rpc` efêmero; criado aqui e descartado
    // ao fechar (era o `ChangeNotifierProvider` que fazia esse dispose).
    final controller = vm.newPairingController()..start();
    final paired = await showDialog<bool>(
      context: context,
      builder: (_) => PairingDialog(controller: controller),
    );
    controller.dispose();
    if (!mounted) return;
    if (paired == true) await vm.loadDevices();
  }

  /// Revogar é destrutivo (o aparelho perde acesso) → confirma, depois roda o
  /// revoke (sobe um `pi --mode rpc` que liga o relay) num dialog de progresso,
  /// e recarrega a lista ao fim.
  Future<void> _confirmRevoke(PairedDevice device) async {
    final vm = context.read<ConnectivityViewModel>();
    final colors = context.colors;
    final name = device.label.isEmpty ? device.shortId : device.label;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Revoke device?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          '"$name" will lose access to your agents and will need to pair again.'
          '\n\nYou must be connected to the relay — the app will connect '
          'automatically to revoke.',
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
              'Revoke',
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

    // Dialog de progresso (não-dismissível): roda o revoke e mostra resultado.
    // O controller é dono do `pi --mode rpc` efêmero; descartado ao fechar.
    final controller = vm.newRevokeController()..run(device);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RevokeDialog(controller: controller),
    );
    controller.dispose();
    if (!mounted) return;
    await vm.loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectivityViewModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsSection(
                label: 'Relay',
                child: SettingsCard(children: [_RelayEditor()]),
              ),
              SettingsSection(
                label: 'Paired devices',
                trailing: SettingsReloadButton(
                  busy: vm.devicesLoad == ConnLoad.loading,
                  onTap: vm.loadDevices,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _devicesCard(context, vm),
                    const SizedBox(height: 12),
                    _PairButton(onTap: _openPairing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _devicesCard(BuildContext context, ConnectivityViewModel vm) {
    final colors = context.colors;

    // Primeira carga (ainda sem dados).
    if (vm.devicesLoad == ConnLoad.loading && vm.devices.isEmpty) {
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

    if (vm.devicesLoad == ConnLoad.error && vm.devices.isEmpty) {
      return SettingsMessageCard(
        child: Text(
          vm.devicesError ?? 'Failed to list devices.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.error,
          ),
        ),
      );
    }

    if (vm.devices.isEmpty) {
      return SettingsMessageCard(
        child: Text(
          'No paired devices.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }

    return SettingsCard(
      children: [
        for (final device in vm.devices)
          _DeviceTile(device: device, onRevoke: () => _confirmRevoke(device)),
      ],
    );
  }
}

/// Campo de URL do relay (mono) + botão Salvar. O valor carregado/salvo sincroniza
/// com o campo, mas só enquanto o usuário não estiver digitando.
class _RelayEditor extends StatefulWidget {
  const _RelayEditor();

  @override
  State<_RelayEditor> createState() => _RelayEditorState();
}

class _RelayEditorState extends State<_RelayEditor> {
  final TextEditingController _ctrl = TextEditingController();
  late final ConnectivityViewModel _vm;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<ConnectivityViewModel>();
    _ctrl.text = _vm.relayUrl ?? '';
    _vm.addListener(_syncFromVm);
  }

  void _syncFromVm() {
    if (_edited) return;
    final loaded = _vm.relayUrl ?? '';
    if (_ctrl.text != loaded) {
      _ctrl.text = loaded;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_syncFromVm);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await _vm.setRelay(_ctrl.text);
    if (!mounted) return;
    if (ok) setState(() => _edited = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectivityViewModel>();
    final colors = context.colors;
    final value = _ctrl.text.trim();
    final canSave =
        !vm.savingRelay && value.isNotEmpty && value != (vm.relayUrl ?? '');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Relay address',
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Server that connects your agents to the phone. Applies to every '
            'agent with the relay enabled.',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onChanged: (_) {
                    setState(() => _edited = true);
                    _vm.clearHealth(); // check anterior não vale mais
                  },
                  onSubmitted: (_) {
                    if (canSave) _save();
                  },
                  style: context.typo.mono.copyWith(
                    fontSize: 12.5,
                    color: colors.text,
                  ),
                  placeholder: const Text('https://relay.example.com'),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              const SizedBox(width: 8),
              PrimaryButton(
                onPressed: canSave ? () => _save() : null,
                child: Text(vm.savingRelay ? 'Saving…' : 'Save'),
              ),
            ],
          ),
          if (vm.relayError != null) ...[
            const SizedBox(height: 8),
            Text(
              vm.relayError!,
              style: context.typo.label.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              OutlineButton(
                onPressed: vm.healthState == HealthState.checking
                    ? null
                    : () => vm.checkRelay(_ctrl.text),
                leading: const Icon(Icons.wifi_tethering, size: 15),
                child: const Text('Check'),
              ),
              const SizedBox(width: 12),
              Expanded(child: _HealthIndicator(vm: vm)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resultado do "Verificar" do relay: ponto colorido + texto.
class _HealthIndicator extends StatelessWidget {
  const _HealthIndicator({required this.vm});
  final ConnectivityViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (vm.healthState == HealthState.checking) {
      return Row(
        children: [
          CircularProgressIndicator(
            size: 13,
            strokeWidth: 2,
            color: colors.text3,
          ),
          const SizedBox(width: 8),
          Text(
            'Checking…',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      );
    }

    final (Color dot, String label, Color text) = switch (vm.healthState) {
      HealthState.healthy => (colors.online, 'Online', colors.text2),
      HealthState.unhealthy => (
        colors.error,
        vm.healthMessage ?? 'No response',
        colors.error,
      ),
      _ => (colors.text4, 'Not checked', colors.text3),
    };

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.typo.label.copyWith(color: text),
          ),
        ),
      ],
    );
  }
}

/// Uma linha da lista de aparelhos pareados (rótulo + shortId + revogar).
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onRevoke});
  final PairedDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(_deviceIcon(device.label), size: 18, color: colors.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  device.label.isEmpty ? 'Device' : device.label,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  device.shortId,
                  style: context.typo.mono.copyWith(
                    fontSize: 11.5,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            tooltip: (context) => const TooltipContainer(child: Text('Revoke')),
            child: HoverTap(
              borderRadius: BorderRadius.circular(6),
              onTap: onRevoke,
              child: SizedBox(
                width: 30,
                height: 30,
                child: Icon(Icons.link_off, size: 16, color: colors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão de recarregar (à direita do rótulo da seção). Vira spinner enquanto carrega.
/// Container com a mesma moldura do `SettingsCard`, para mensagens de estado (vazio /
/// carregando / erro) no lugar da lista.
/// Botão de pareamento (abre o dialog com QR). Tonal accent pra diferenciar do
/// Salvar (primário) sem competir com ele.
class _PairButton extends StatelessWidget {
  const _PairButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.accentSoft,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 17, color: colors.accentText),
          const SizedBox(width: 8),
          Text(
            'Pair new device',
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _deviceIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('iphone') || l.contains('ipad') || l.contains('ios')) {
    return Icons.phone_iphone;
  }
  if (l.contains('android')) return Icons.phone_android;
  return Icons.devices_outlined;
}
