import 'dart:async';

import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';

const _kTimeout = 60; // seconds

// Inline approval card that appears in the chat flow.
// Shows tool name + command/args + allow/deny buttons + 60s countdown.
// After decision (or timeout) the card dims and shows the outcome.

class ToolRequestCard extends StatefulWidget {
  final ToolEvent tool;
  final void Function(String toolCallId, ApproveDecision decision)? onDecide;

  const ToolRequestCard({super.key, required this.tool, this.onDecide});

  @override
  State<ToolRequestCard> createState() => _ToolRequestCardState();
}

class _ToolRequestCardState extends State<ToolRequestCard> {
  Timer? _timer;
  int _remaining = _kTimeout;

  @override
  void initState() {
    super.initState();
    if (widget.tool.status == ToolEventStatus.pending) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _remaining--;
          if (_remaining <= 0) {
            _timer?.cancel();
            widget.onDecide?.call(
              widget.tool.toolCallId,
              ApproveDecision.deny,
            );
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.tool.status == ToolEventStatus.pending;
    final opacity = isPending ? 1.0 : 0.55;

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kAccent, width: 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: kAccent.withValues(alpha: 0.13),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            _buildCodeBlock(),
            if (isPending) ...[
              const SizedBox(height: 12),
              _buildButtons(),
            ] else ...[
              const SizedBox(height: 8),
              _buildOutcome(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final statusLabel = switch (widget.tool.status) {
      ToolEventStatus.pending => 'AWAITING',
      ToolEventStatus.allowed => 'ALLOWED',
      ToolEventStatus.denied => 'DENIED',
      ToolEventStatus.expired => 'EXPIRED',
      ToolEventStatus.completed => 'DONE',
    };

    return Row(
      children: [
        // Terminal icon
        CustomPaint(
          size: const Size(14, 14),
          painter: _TerminalIconPainter(color: kAccent),
        ),
        const SizedBox(width: 8),
        Text(
          widget.tool.tool.toUpperCase(),
          style: TextStyle(
            fontFamily: kMono,
            fontSize: 11.5,
            color: kAccent,
            letterSpacing: 0.6,
          ),
        ),
        const Spacer(),
        Text(
          widget.tool.status == ToolEventStatus.pending
              ? 'AWAITING · ${_remaining}s'
              : statusLabel,
          style: TextStyle(
            fontFamily: kMono,
            fontSize: 10,
            color: widget.tool.status == ToolEventStatus.pending && _remaining < 10
                ? Colors.orangeAccent
                : kMuted,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildCodeBlock() {
    final commandText = _formatArgs(widget.tool.tool, widget.tool.args);
    return Container(
      decoration: BoxDecoration(
        color: kCodeBg,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r'$ ', style: kMonoStyle.copyWith(color: kMuted)),
          Expanded(
            child: Text(commandText, style: kMonoStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: () => widget.onDecide?.call(
                widget.tool.toolCallId,
                ApproveDecision.deny,
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kDenyBorder),
                foregroundColor: const Color(0xFFCFCFCF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Text('Deny'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 38,
            child: FilledButton(
              onPressed: () => widget.onDecide?.call(
                widget.tool.toolCallId,
                ApproveDecision.allow,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Text(
                'Allow',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOutcome() {
    return Text(
      widget.tool.status == ToolEventStatus.allowed
          ? '✓ Running…'
          : widget.tool.status == ToolEventStatus.completed
          ? '✓ Done'
          : '✗ ${widget.tool.error ?? "Denied"}',
      style: TextStyle(
        fontFamily: kMono,
        fontSize: 12,
        color: widget.tool.status == ToolEventStatus.denied ||
                widget.tool.status == ToolEventStatus.expired
            ? kMuted
            : kSuccess,
      ),
    );
  }

  static String _formatArgs(String tool, dynamic args) {
    if (args == null) return '';
    if (args is Map) {
      return switch (tool) {
        'Bash' => (args['command'] as String?) ?? '',
        'Edit' || 'Write' => (args['file_path'] as String?) ?? '',
        _ => args.entries
            .map((e) => '${e.key}=${e.value}')
            .join(' '),
      };
    }
    return args.toString();
  }
}

// Minimal terminal icon (rectangle + > and —)
class _TerminalIconPainter extends CustomPainter {
  final Color color;
  const _TerminalIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // Outer rect
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 1, size.width - 1, size.height - 2),
        const Radius.circular(1.6),
      ),
      paint,
    );
    // > chevron
    final path = Path()
      ..moveTo(3, 4.5)
      ..lineTo(5.5, 7)
      ..lineTo(3, 9.5);
    canvas.drawPath(path, paint);
    // — dash
    canvas.drawLine(
      Offset(6.5, size.height / 2),
      Offset(size.width - 2, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_TerminalIconPainter old) => old.color != color;
}
