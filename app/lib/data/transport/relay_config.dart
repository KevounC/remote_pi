// Relay endpoint resolution.
//
// The app always connects to a SINGLE relay at a time, regardless of
// how many peers it's paired with. The URL is resolved from:
//
//   1. `prefs.relayUrl` (user override, set via Settings or onboarding)
//   2. `kDefaultRelayUrl` (the public community relay)
//
// `peer.relayUrl` is kept on PeerRecord for legacy QR code payloads but
// is no longer consulted when opening a connection — the resolution is
// global, not per-peer.

import 'package:app/data/preferences/preferences.dart';

/// Public community relay. Hardcoded; not configurable at build time
/// to keep the onboarding flow deterministic.
const String kDefaultRelayUrl = 'wss://relay.remote-pi.dev';

/// Returns the effective relay URL the app should connect to.
/// Falls back to [kDefaultRelayUrl] when no user override is set.
String resolveRelayUrl(Preferences prefs) =>
    prefs.relayUrl ?? kDefaultRelayUrl;

/// Validates a candidate relay URL.
///
/// Rules:
/// - Non-empty.
/// - Scheme must be `ws://` or `wss://`.
/// - Must be parseable by `Uri.parse` AND yield a non-empty `host`.
///
/// Returns `true` if the URL is acceptable. Use this in the Settings
/// form and during onboarding step 2 before writing to [Preferences].
bool isValidRelayUrl(String url) {
  if (url.isEmpty) return false;
  if (!url.startsWith('ws://') && !url.startsWith('wss://')) return false;
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return false;
  }
  if (uri.host.isEmpty) return false;
  return true;
}
