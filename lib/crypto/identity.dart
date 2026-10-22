import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

// Part of protocol v1: changing these changes every user's keys.
const _pwhashOpsLimit = 3;
const _pwhashMemLimit = 256 * 1024 * 1024;
const _kdfContext = 'tcident1'; // crypto_kdf_CONTEXTBYTES = 8

/// User keys derived entirely from the password and the Telegram user id.
class Identity {
  Identity._({
    required this.userId,
    required this.encryption,
    required this.signing,
    required this.storageKey,
  });

  final int userId;

  /// X25519: direct messages and group key distribution.
  final KeyPair encryption;

  /// Ed25519: key announcements and group messages.
  final KeyPair signing;

  /// Encrypts the local key store.
  final SecureKey storageKey;

  /// Argon2id (~1 s, 256 MB), runs in a separate isolate.
  static Future<Uint8List> deriveSeed({
    required String password,
    required int userId,
  }) {
    return Isolate.run(() async {
      final sodium = await SodiumSumoInit.init();
      final salt = sodium.crypto.genericHash(
        message: utf8.encode('tc-identity-v1:$userId'),
        outLen: sodium.crypto.pwhash.saltBytes,
      );
      final seed = sodium.crypto.pwhash(
        outLen: 32,
        password: Int8List.fromList(utf8.encode(password)),
        salt: salt,
        opsLimit: _pwhashOpsLimit,
        memLimit: _pwhashMemLimit,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      final bytes = seed.extractBytes();
      seed.dispose();
      return bytes;
    });
  }

  static Identity fromSeed(SodiumSumo sodium, Uint8List seed, int userId) {
    final master = sodium.secureCopy(seed);
    SecureKey sub(int id) => sodium.crypto.kdf.deriveFromKey(
      masterKey: master,
      context: _kdfContext,
      subkeyId: BigInt.from(id),
      subkeyLen: 32,
    );

    final encSeed = sub(1);
    final signSeed = sub(2);
    final identity = Identity._(
      userId: userId,
      encryption: sodium.crypto.box.seedKeyPair(encSeed),
      signing: sodium.crypto.sign.seedKeyPair(signSeed),
      storageKey: sub(3),
    );
    encSeed.dispose();
    signSeed.dispose();
    master.dispose();
    return identity;
  }

  void dispose() {
    encryption.dispose();
    signing.dispose();
    storageKey.dispose();
  }
}
