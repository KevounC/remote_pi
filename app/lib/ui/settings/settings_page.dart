import 'package:app/pairing/storage.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsViewModel>().state;
    final vm = context.read<SettingsViewModel>();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: kText),
          onPressed: () => context.pop(),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: kBorder, height: 1),
        ),
      ),
      body: switch (state) {
        SettingsLoading() => const Center(
          child: CircularProgressIndicator(color: kAccent),
        ),
        SettingsNoPeer() => const Center(
          child: Text('No device paired', style: TextStyle(color: kMuted)),
        ),
        SettingsReady(:final peer) => _PeerCard(
          peer: peer,
          onRename: (name) => vm.rename(name),
          onRevoke: () => _confirmRevoke(context, vm),
        ),
      },
    );
  }

  static Future<void> _confirmRevoke(
    BuildContext context,
    SettingsViewModel vm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Forget pairing?', style: TextStyle(color: kText)),
        content: const Text(
          'This device will no longer be able to reconnect without scanning a new QR.',
          style: TextStyle(color: kMuted2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kMuted2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Forget',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await vm.revoke();
      if (context.mounted) context.go('/pair');
    }
  }
}

// ---------------------------------------------------------------------------

class _PeerCard extends StatelessWidget {
  final PeerRecord peer;
  final void Function(String) onRename;
  final VoidCallback onRevoke;

  const _PeerCard({
    required this.peer,
    required this.onRename,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Session name
        _SectionLabel('Paired device'),
        _EditableField(
          label: 'Name',
          value: peer.sessionName,
          onSave: onRename,
        ),

        const SizedBox(height: 20),

        // Technical details
        _SectionLabel('Details'),
        _DetailRow('Relay', peer.relayUrl),
        _DetailRow(
          'Peer key',
          '${peer.remoteEpk.substring(0, 8)}…',
          onCopy: peer.remoteEpk,
        ),
        _DetailRow('Paired at', peer.pairedAt.substring(0, 10)),

        const SizedBox(height: 32),

        // Revoke button
        OutlinedButton.icon(
          onPressed: onRevoke,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Forget pairing'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: kMuted,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? onCopy;

  const _DetailRow(this.label, this.value, {this.onCopy});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCopy != null
          ? () {
              Clipboard.setData(ClipboardData(text: onCopy!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontFamily: kMono,
                fontSize: 12,
                color: kMuted2,
              ),
            ),
            if (onCopy != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.copy_outlined, size: 12, color: kMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditableField extends StatefulWidget {
  final String label;
  final String value;
  final void Function(String) onSave;

  const _EditableField({
    required this.label,
    required this.value,
    required this.onSave,
  });

  @override
  State<_EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<_EditableField> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: kText, fontSize: 14),
              cursorColor: kAccent,
              decoration: const InputDecoration(
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: kAccent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kAccent, width: 1.5),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (v) {
                widget.onSave(v);
                setState(() => _editing = false);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, color: kAccent, size: 18),
            onPressed: () {
              widget.onSave(_ctrl.text);
              setState(() => _editing = false);
            },
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _editing = true),
      child: Row(
        children: [
          Text(widget.value, style: const TextStyle(color: kText, fontSize: 14)),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined, color: kMuted, size: 14),
        ],
      ),
    );
  }
}
