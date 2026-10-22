import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:tel_client/crypto/protocol.dart';
import 'package:tel_client/e2e/key_store.dart';

void main() {
  late SodiumSumo sodium;
  late Directory dir;

  setUpAll(() async => sodium = await SodiumSumoInit.init());
  setUp(() => dir = Directory.systemTemp.createTempSync('keys'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<KeyStore> open(SecureKey key) => KeyStore.open(
    sodium: sodium,
    file: File('${dir.path}/keys.bin'),
    storageKey: key,
    keyId: (pk) => pk.sublist(0, 8),
  );

  GroupKey groupKey(int id, DateTime at) => GroupKey(
    id: Uint8List.fromList(List.filled(8, id)),
    key: sodium.secureRandom(32),
    createdAt: at,
  );

  test('the newest group key is current whatever the order', () async {
    final store = await open(sodium.secureRandom(32));
    store.addGroupKey(-1, groupKey(2, DateTime(2026, 2)), own: false);
    store.addGroupKey(-1, groupKey(1, DateTime(2026, 1)), own: true);
    expect(store.currentGroupKey(-1)!.id.first, 2);
    expect(store.ownsGroupKey(-1), isFalse);
  });

  test('an older peer key does not replace the current one', () async {
    final store = await open(sodium.secureRandom(32));
    PeerKeys keys(int b, DateTime at) => PeerKeys(
      userId: 7,
      encPublic: Uint8List.fromList(List.filled(32, b)),
      signPublic: Uint8List.fromList(List.filled(32, b)),
      createdAt: at,
    );
    store.addPeer(keys(2, DateTime(2026, 2)));
    store.setVerified(7, true);
    store.addPeer(keys(1, DateTime(2026, 1)));
    expect(store.peer(7)!.encPublic.first, 2);
    expect(store.isVerified(7), isTrue);
    store.addPeer(keys(3, DateTime(2026, 3)));
    expect(store.isVerified(7), isFalse);
  });

  test('a damaged store is set aside instead of blocking start', () async {
    await File('${dir.path}/keys.bin').writeAsBytes(List.filled(100, 1));
    final store = await open(sodium.secureRandom(32));
    expect(store.currentGroupKey(-1), isNull);
    expect(File('${dir.path}/keys.bin.corrupt').existsSync(), isTrue);
  });

  test('keys survive a reload', () async {
    final key = sodium.secureRandom(32);
    final store = await open(key);
    store.addGroupKey(-1, groupKey(5, DateTime(2026, 5)), own: true);
    final reloaded = await open(key);
    expect(reloaded.currentGroupKey(-1)!.id.first, 5);
    expect(reloaded.ownsGroupKey(-1), isTrue);
  });
}
