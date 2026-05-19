import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kPeersService = 'dev.remotepi.peers';
const _kDeviceService = 'dev.remotepi.device';
const _kDeviceAccount = 'ed25519';

// ---------------------------------------------------------------------------
// PeerRecord — persisted per pairing
// ---------------------------------------------------------------------------

class PeerRecord {
  // base64 Ed25519 pubkey of the Pi — the only peer identifier post-rollback.
  final String remoteEpk;
  final String sessionName;
  final String relayUrl;
  final String pairedAt; // ISO-8601

  const PeerRecord({
    required this.remoteEpk,
    required this.sessionName,
    required this.relayUrl,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
    'remote_epk': remoteEpk,
    'session_name': sessionName,
    'relay_url': relayUrl,
    'paired_at': pairedAt,
  };

  factory PeerRecord.fromJson(Map<String, dynamic> j) => PeerRecord(
    remoteEpk: j['remote_epk'] as String,
    sessionName: j['session_name'] as String,
    relayUrl: j['relay_url'] as String,
    pairedAt: j['paired_at'] as String,
  );

  PeerRecord copyWith({String? sessionName}) => PeerRecord(
    remoteEpk: remoteEpk,
    sessionName: sessionName ?? this.sessionName,
    relayUrl: relayUrl,
    pairedAt: pairedAt,
  );
}

// ---------------------------------------------------------------------------
// DeviceIdentity — Ed25519 singleton per device
// ---------------------------------------------------------------------------

class DeviceIdentity {
  final String pk; // base64url Ed25519 pubkey
  final String sk; // base64url Ed25519 privkey

  const DeviceIdentity({required this.pk, required this.sk});
}

// ---------------------------------------------------------------------------
// PairingStorage
// ---------------------------------------------------------------------------

class PairingStorage {
  final FlutterSecureStorage _store;

  const PairingStorage([FlutterSecureStorage? store])
    : _store = store ?? const FlutterSecureStorage();

  // ---- Peer records --------------------------------------------------------

  String _peerKey(String remoteEpk) => '$_kPeersService:$remoteEpk';

  Future<void> savePeer(PeerRecord record) => _store.write(
    key: _peerKey(record.remoteEpk),
    value: jsonEncode(record.toJson()),
  );

  Future<PeerRecord?> loadPeer(String remoteEpk) async {
    final raw = await _store.read(key: _peerKey(remoteEpk));
    if (raw == null) return null;
    return PeerRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deletePeer(String remoteEpk) =>
      _store.delete(key: _peerKey(remoteEpk));

  Future<List<PeerRecord>> listPeers() async {
    final all = await _store.readAll();
    final prefix = '$_kPeersService:';
    return all.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => PeerRecord.fromJson(
          jsonDecode(e.value) as Map<String, dynamic>,
        ))
        .toList();
  }

  // ---- Device Ed25519 singleton -------------------------------------------

  /// Load the device-level Ed25519 identity. Generates and persists on first
  /// call. Used for relay challenge-response auth.
  Future<DeviceIdentity> loadOrCreateDeviceEd25519Key() async {
    final existing = await _store.read(
      key: '$_kDeviceService:$_kDeviceAccount',
    );
    if (existing != null) {
      final j = jsonDecode(existing) as Map<String, dynamic>;
      return DeviceIdentity(pk: j['pk'] as String, sk: j['sk'] as String);
    }
    return _generateAndSaveDeviceKey();
  }

  Future<DeviceIdentity> _generateAndSaveDeviceKey() async {
    final kp = await Ed25519().newKeyPair();
    final pub = await kp.extractPublicKey();
    final priv = await kp.extractPrivateKeyBytes();
    final identity = DeviceIdentity(
      pk: base64Url.encode(pub.bytes),
      sk: base64Url.encode(priv),
    );
    await _saveDeviceEd25519Key(identity);
    return identity;
  }

  Future<void> _saveDeviceEd25519Key(DeviceIdentity identity) =>
      _store.write(
        key: '$_kDeviceService:$_kDeviceAccount',
        value: jsonEncode({'pk': identity.pk, 'sk': identity.sk}),
      );
}
