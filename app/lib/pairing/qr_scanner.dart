import 'dart:convert';

// QR URI format: remotepi://pair?t=<base64url>&epk=<base64url>&r=<url>&n=<name>
//
// Fields:
//   t   — token efêmero (16 bytes, base64url), single-use, valid 60s
//   epk — Ed25519 pubkey do Mac (32 bytes) — único peer ID no relay
//   r   — relay WebSocket URL
//   n   — session name (max 80 chars)

class QrPairPayload {
  final String token;
  final String epk; // base64url Ed25519 — relay peer ID
  final String relayUrl;
  final String sessionName;

  const QrPairPayload({
    required this.token,
    required this.epk,
    required this.relayUrl,
    required this.sessionName,
  });

  static QrPairPayload? tryParse(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme != 'remotepi' || uri.host != 'pair') return null;
      final t = uri.queryParameters['t'];
      final epk = uri.queryParameters['epk'];
      final r = uri.queryParameters['r'];
      final n = uri.queryParameters['n'];
      if (t == null || epk == null || r == null || n == null) return null;
      if (base64Url.decode(_pad(t)).length != 16) return null;
      if (base64Url.decode(_pad(epk)).length != 32) return null;
      return QrPairPayload(
        token: t,
        epk: epk,
        relayUrl: r,
        sessionName: n,
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
