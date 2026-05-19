import 'package:app/data/transport/connection_manager.dart';
import 'package:flutter/material.dart';

// Offline/retrying banner that slides in at the top of the chat.
// Collapses (height=0) when online.

class OfflineBanner extends StatelessWidget {
  final ConnectionStatus status;
  final VoidCallback? onRePair; // for permanent offline (fingerprint mismatch)

  const OfflineBanner({super.key, required this.status, this.onRePair});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: switch (status) {
        StatusOnline() || StatusNoPeer() || StatusConnecting() =>
          const SizedBox.shrink(),
        StatusRetrying(:final nextRetry, :final attempt) => _Banner(
          color: Colors.orange.shade900,
          icon: Icons.sync_rounded,
          label:
              'Reconnecting… retry ${attempt + 1} in ${nextRetry.inSeconds}s',
          trailing: const _SpinnerIcon(),
        ),
        StatusOffline(:final canRetry, :final reason) => _Banner(
          color: canRetry ? Colors.orange.shade900 : Colors.red.shade900,
          icon: Icons.wifi_off_rounded,
          label: canRetry ? 'Offline. Retrying…' : 'Offline: $reason',
          trailing: canRetry
              ? null
              : _TextButton(label: 'Re-pair', onTap: onRePair),
        ),
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _Banner({
    required this.color,
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SpinnerIcon extends StatelessWidget {
  const _SpinnerIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.white,
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _TextButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
