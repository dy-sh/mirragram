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
        (bob.decryptDirect(decoded, bobKeys).payload as TextPayload).text,
        'Hi Bob! Ça va? 👋',
      );

      final laptopKeys = _Keys(aliceLaptop)..peers.add(bob.myKeys);
      expect(
        (aliceLaptop.decryptDirect(decoded, laptopKeys).payload as TextPayload)
            .text,
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

    final gk = alice.generateGroupKey(chatId);
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
      alice.generateGroupKey(-1),
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

  group('malicious input', () {
    Uint8List announcement({
      required int userId,
      required int createdAt,
      required Uint8List enc,
      required KeyPair signing,
    }) {
      final body = BytesBuilder()
        ..add([Protocol.version, Protocol.typeAnnounce])
        ..add((ByteData(8)..setInt64(0, userId)).buffer.asUint8List())
        ..add((ByteData(8)..setInt64(0, createdAt)).buffer.asUint8List())
        ..add(enc)
        ..add(signing.publicKey);
      final bytes = body.toBytes();
      final sig = sodium.crypto.sign.detached(
        message: Uint8List.fromList([...'tc-announce-v1'.codeUnits, ...bytes]),
        secretKey: signing.secretKey,
      );
      return Uint8List.fromList([...bytes, ...sig]);
    }

    test('an absurd announcement time is rejected, not thrown', () {
      final bob = proto(bobSeed, 2);
      final ann = announcement(
        userId: 66,
        createdAt: 1 << 62,
        enc: sodium.crypto.box.keyPair().publicKey,
        signing: sodium.crypto.sign.keyPair(),
      );
      expect(
        () => bob.openAnnouncement(ann),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('a low-order encryption key is rejected', () {
      final bob = proto(bobSeed, 2);
      final ann = announcement(
        userId: 66,
        createdAt: 1700000000,
        enc: Uint8List(32),
        signing: sodium.crypto.sign.keyPair(),
      );
      expect(
        () => bob.openAnnouncement(ann),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('invalid UTF-8 in a payload is a protocol error', () {
      expect(
        () => E2eProtocol.decodePayload(
          Uint8List.fromList([Protocol.contentText, 0xFF, 0xFE]),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('direct messages carry the sender and recipient', () {
      final alice = proto(aliceSeed, 1);
      final bob = proto(bobSeed, 2);
      final env = alice.encryptDirect(bob.myKeys, const TextPayload('hi'));
      final opened = bob.decryptDirect(
        env,
        _Keys(bob)..peers.add(alice.myKeys),
      );
      expect(opened.senderUserId, 1);
      expect(opened.recipientUserId, 2);
    });

    test('a group key under someone else\'s key id is rejected', () {
      const chatId = -100123;
      final alice = proto(aliceSeed, 1);
      final mallory = proto(carolSeed, 3);
      final bob = proto(bobSeed, 2);
      final real = alice.generateGroupKey(chatId);
      final fake = GroupKey(
        id: real.id,
        key: sodium.secureRandom(Protocol.groupKeyBytes),
        createdAt: DateTime.now(),
      );
      final bundle = mallory.createGroupKeyBundles(chatId, fake, [
        bob.myKeys,
      ]).single;
      final bobKeys = _Keys(bob)..peers.add(mallory.myKeys);
      expect(
        () => bob.openGroupKeyBundle(chatId, bundle, bobKeys),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}
