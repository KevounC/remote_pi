// Ed25519 helpers — the only crypto remaining after the E2E rollback
// (plan/06-rollback-e2e.md). Ed25519 is still used for the relay
// challenge-response auth.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<SimpleKeyPair> generateEd25519KeyPair() => Ed25519().newKeyPair();

Future<SimpleKeyPair> ed25519FromSeed(Uint8List seed) =>
    Ed25519().newKeyPairFromSeed(seed);

Future<Uint8List> ed25519Sign(SimpleKeyPair kp, Uint8List message) async {
  final sig = await Ed25519().sign(message, keyPair: kp);
  return Uint8List.fromList(sig.bytes);
}

Future<bool> ed25519Verify({
  required Uint8List message,
  required Uint8List signature,
  required Uint8List publicKey,
}) {
  return Ed25519().verify(
    message,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
}
