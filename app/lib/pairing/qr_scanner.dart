import 'dart:convert';

// QR URI format: remotepi://pair?t=<base64url>&epk=<base64url>&n=<name>[&r=<url>]
//
// Fields:
//   t   — token efêmero (16 bytes, base64url), single-use, valid 60s
//   epk — Ed25519 pubkey do Pi (32 bytes) — único peer ID no relay
//   n   — session name (max 80 chars)
//   r   — relay WebSocket URL (OPTIONAL since plan 14: app uses its own
//         configured relay; legacy QR codes that carry `r` are tolerated
//         and trigger a "trocar relay?" modal if the value mismatches
//         the user's configured relay).

class QrPairPayload {
  final String token;
  final String epk; // base64url Ed25519 — relay peer ID
  /// Optional legacy relay URL embedded in the QR. `null` for new QRs.
  /// Use `pair_request_flow` to detect mismatch vs `Preferences.relayUrl`.
  final String? relayUrl;
  final String sessionName;

  const QrPairPayload({
    required this.token,
    required this.epk,
    required this.sessionName,
    this.relayUrl,
  });

  static QrPairPayload? tryParse(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme != 'remotepi' || uri.host != 'pair') return null;
      final t = uri.queryParameters['t'];
      final epk = uri.queryParameters['epk'];
      final r = uri.queryParameters['r']; // legacy/optional
      final n = uri.queryParameters['n'];
      // r is no longer required — plan 14 dropped it from the canonical
      // contract. Legacy QRs continue to include it; we capture it for
      // mismatch detection but don't reject when absent.
      if (t == null || epk == null || n == null) return null;
      if (base64Url.decode(_pad(t)).length != 16) return null;
      if (base64Url.decode(_pad(epk)).length != 32) return null;
      return QrPairPayload(
        token: t,
        epk: epk,
        sessionName: n,
        relayUrl: (r != null && r.isNotEmpty) ? r : null,
      );
    } catch (_) {
      return null;
    }
  }

  List<int> get epkBytes => base64Url.decode(_pad(epk));

  static String _pad(String s) {
    final p = (4 - s.length % 4) % 4;
    return s + '=' * p;
  }
}
