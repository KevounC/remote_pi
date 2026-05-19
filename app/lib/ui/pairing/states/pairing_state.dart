import 'package:app/pairing/storage.dart';

sealed class PairingState {
  const PairingState();
}

/// Initial state — UI not yet showing the scanner.
class PairingIdle extends PairingState {
  const PairingIdle();
}

/// Camera viewfinder visible; waiting for a valid QR scan.
class PairingScanning extends PairingState {
  const PairingScanning();
}

/// QR scanned; opening transport + sending pair_request.
class PairingConnecting extends PairingState {
  final String sessionName;
  const PairingConnecting({required this.sessionName});
}

/// Pi confirmed; channel adopted. UI navigates straight to chat.
class PairingPaired extends PairingState {
  final PeerRecord peer;
  const PairingPaired({required this.peer});

  @override
  bool operator ==(Object other) =>
      other is PairingPaired && other.peer.remoteEpk == peer.remoteEpk;

  @override
  int get hashCode => peer.remoteEpk.hashCode;
}

/// QR parse, transport, or pair_request failed.
class PairingError extends PairingState {
  final String message;
  final bool canRetry;
  const PairingError({required this.message, this.canRetry = true});
}
