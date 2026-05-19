import 'package:app/ui/app_theme.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// PairingPage — QR scanner + pair_request in one screen
// ---------------------------------------------------------------------------

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _scanner = MobileScannerController();
  bool _scannerActive = true;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scannerActive) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() => _scannerActive = false);
    _scanner.stop();

    context.read<PairingViewModel>().onQrScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PairingViewModel>().state;
    final vm = context.read<PairingViewModel>();

    if (state is PairingPaired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/chat');
      });
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Pair device'),
      ),
      body: _buildBody(state, vm),
    );
  }

  Widget _buildBody(PairingState state, PairingViewModel vm) {
    return switch (state) {
      PairingIdle() ||
      PairingScanning() ||
      PairingConnecting() => _buildScannerBody(state),
      PairingPaired() => const Center(
        child: CircularProgressIndicator(color: kAccent),
      ),
      PairingError(:final message, :final canRetry) => _ErrorView(
        message: message,
        canRetry: canRetry,
        onRetry: () {
          vm.retry();
          setState(() => _scannerActive = true);
          _scanner.start();
        },
      ),
    };
  }

  Widget _buildScannerBody(PairingState state) {
    final isConnecting = state is PairingConnecting;
    final sessionName = isConnecting ? state.sessionName : null;

    return Stack(
      children: [
        if (!isConnecting)
          MobileScanner(controller: _scanner, onDetect: _onDetect),
        Center(
          child: Container(
            width: 268,
            height: 268,
            decoration: BoxDecoration(
              color: isConnecting ? Colors.black54 : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kBorder),
            ),
            child: isConnecting
                ? const Center(
                    child: CircularProgressIndicator(color: kAccent),
                  )
                : _CornerBrackets(),
          ),
        ),
        if (!isConnecting) ..._cornerBrackets(),
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Text(
            isConnecting
                ? 'Connecting to $sessionName…'
                : 'Point camera at the QR shown in your Mac terminal',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ],
    );
  }

  List<Widget> _cornerBrackets() {
    return [
      Align(
        alignment: const Alignment(-0.7, -0.4),
        child: _Bracket(rotate: 0),
      ),
      Align(
        alignment: const Alignment(0.7, -0.4),
        child: _Bracket(rotate: 90),
      ),
      Align(
        alignment: const Alignment(0.7, 0.4),
        child: _Bracket(rotate: 180),
      ),
      Align(
        alignment: const Alignment(-0.7, 0.4),
        child: _Bracket(rotate: 270),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------

class _CornerBrackets extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Bracket extends StatelessWidget {
  final double rotate;
  const _Bracket({required this.rotate});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate * 3.14159 / 180,
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(painter: _BracketPainter(color: kAccent)),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  const _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(18, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, 18), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted2, fontSize: 14),
            ),
            if (canRetry) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
