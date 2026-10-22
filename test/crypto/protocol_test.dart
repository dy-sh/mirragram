import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:tel_client/crypto/identity.dart';
import 'package:tel_client/crypto/protocol.dart';

class _Keys implements KeyLookup {
  final peers = <PeerKeys>[];
  final groups = <int, List<GroupKey>>{};
  final E2eProtocol p;

  _Keys(this.p);

  bool _eq(Uint8List a, Uint8List b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

  @override
  PeerKeys? peerByEncKeyId(Uint8List id) =>
      peers.where((k) => _eq(p.keyId(k.encPublic), id)).firstOrNull;

  @override
  PeerKeys? peerBySignKeyId(Uint8List id) =>
      peers.where((k) => _eq(p.keyId(k.signPublic), id)).firstOrNull;

  @override
  GroupKey? groupKey(int chatId, Uint8List id) =>
      groups[chatId]?.where((k) => _eq(k.id, id)).firstOrNull;
}

void main() {
  late SodiumSumo sodium;
  late Uint8List aliceSeed, bobSeed, carolSeed;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
    aliceSeed = await Identity.deriveSeed(password: 'alice pass', userId: 1);
    bobSeed = await Identity.deriveSeed(password: 'bob pass', userId: 2);
    carolSeed = await Identity.deriveSeed(password: 'carol pass', userId: 3);
  });

  E2eProtocol proto(Uint8List seed, int userId) =>
      E2eProtocol(sodium, Identity.fromSeed(sodium, seed, userId));

  test('keys are deterministic for the same password and user id', () async {
    final again = await Identity.deriveSeed(password: 'alice pass', userId: 1);
    expect(again, aliceSeed);
    final otherUser = await Identity.deriveSeed(
      password: 'alice pass',
      userId: 99,
    );
    expect(otherUser, isNot(aliceSeed));
  });

  test('key announcement signature is verified and tampering breaks it', () {
    final alice = proto(aliceSeed, 1);
    final bob = proto(bobSeed, 2);
    final ann = alice.createAnnouncement();

    final keys = bob.openAnnouncement(ann);
    expect(keys.userId, 1);
    expect(keys.encPublic, alice.myKeys.encPublic);

    final forged = Uint8List.fromList(ann)..[5] ^= 1; // tamper with user_id
    expect(
      () => bob.openAnnouncement(forged),
      throwsA(isA<ProtocolException>()),
    );
  });

  test(
    'direct messages are readable by the recipient and the sender\'s other device',
    () {
      final alice = proto(aliceSeed, 1);
      final aliceLaptop = proto(aliceSeed, 1);
      final bob = proto(bobSeed, 2);
      final carol = proto(carolSeed, 3);

      final env = alice.encryptDirect(
        bob.myKeys,
        const TextPayload('Hi Bob! Ça va? 👋'),
      );
      final text = Protocol.encodeText(env);
      expect(text.length, lessThan(Protocol.maxTextLength));
      final decoded = Protocol.decodeText(text)!;

      final bobKeys = _Keys(bob)..peers.add(alice.myKeys);
      expect(
        (bob.decryptDirect(decoded, bobKeys) as TextPayload).text,
        'Hi Bob! Ça va? 👋',
      );

      final laptopKeys = _Keys(aliceLaptop)..peers.add(bob.myKeys);
      expect(
        (aliceLaptop.decryptDirect(decoded, laptopKeys) as TextPayload).text,
        'Hi Bob! Ça va? 👋',
      );

      final carolKeys = _Keys(carol)..peers.addAll([alice.myKeys, bob.myKeys]);
      expect(
        () => carol.decryptDirect(decoded, carolKeys),
        throwsA(isA<ProtocolException>()),
      );

      final tampered = Uint8List.fromList(decoded)..[decoded.length - 1] ^= 1;
      expect(
        () => bob.decryptDirect(tampered, bobKeys),
        throwsA(isA<ProtocolException>()),
      );
    },
  );

  test('group: key distribution, reading, sender signature, chat binding', () {
    const chatId = -100123;
    final alice = proto(aliceSeed, 1);
    final bob = proto(bobSeed, 2);
    final carol = proto(carolSeed, 3);

    final gk = alice.generateGroupKey();
    final bundles = alice.createGroupKeyBundles(chatId, gk, [bob.myKeys]);
    expect(bundles, hasLength(1));

    final bobKeys = _Keys(bob)..peers.add(alice.myKeys);
    final opened = bob.openGroupKeyBundle(chatId, bundles.single, bobKeys)!;
    expect(opened.distributor.userId, 1);
    bobKeys.groups[chatId] = [opened.key];

    // Carol was not a recipient.
    final carolKeys = _Keys(carol)..peers.addAll([alice.myKeys, bob.myKeys]);
    expect(carol.openGroupKeyBundle(chatId, bundles.single, carolKeys), isNull);

    final aliceKeys = _Keys(alice)..peers.add(bob.myKeys);
    aliceKeys.groups[chatId] = [gk];

    final env = bob.encryptGroup(
      chatId,
      opened.key,
      const TextPayload('hello everyone ✨'),
    );
    final msg = alice.decryptGroup(chatId, env, aliceKeys);
    expect((msg.payload as TextPayload).text, 'hello everyone ✨');
    expect(msg.sender.userId, 2);

    // The same message replayed in another chat is rejected.
    aliceKeys.groups[-100999] = [gk];
    expect(
      () => alice.decryptGroup(-100999, env, aliceKeys),
      throwsA(isA<ProtocolException>()),
    );
  });

  test('a large group key is split into several messages', () {
    final alice = proto(aliceSeed, 1);
    final bob = proto(bobSeed, 2);
    final members = List.generate(
      80,
      (i) => PeerKeys(
        userId: 1000 + i,
        encPublic: sodium.crypto.box.keyPair().publicKey,
        signPublic: sodium.crypto.sign.keyPair().publicKey,
        createdAt: DateTime.now(),
      ),
    )..add(bob.myKeys);

    final bundles = alice.createGroupKeyBundles(
      -1,
      alice.generateGroupKey(),
      members,
    );
    expect(bundles, hasLength(3)); // 82 recipients including us / 36
    for (final b in bundles) {
      expect(
        Protocol.encodeText(b).length,
        lessThanOrEqualTo(Protocol.maxTextLength),
      );
    }
    final bobKeys = _Keys(bob)..peers.add(alice.myKeys);
    final found = bundles
        .map((b) => bob.openGroupKeyBundle(-1, b, bobKeys))
        .nonNulls;
    expect(found, hasLength(1));
  });

  test('safety number is the same on both sides', () {
    final alice = proto(aliceSeed, 1);
    final bob = proto(bobSeed, 2);
    final n = alice.safetyNumber(bob.myKeys);
    expect(n, hasLength(60));
    expect(bob.safetyNumber(alice.myKeys), n);
  });

  test('plain text is not treated as encrypted', () {
    expect(Protocol.decodeText('hello'), isNull);
    expect(Protocol.decodeText('🔒 just a lock'), isNull);
  });
}
