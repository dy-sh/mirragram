import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sodium/sodium_sumo.dart';

import 'identity.dart';

/// Protocol v1. Every message is a binary envelope
///   [version u8][type u8][...type fields...]
/// sent as text: `🔒` + unpadded base64url.
///
/// Types:
///   announce  user's public keys, signed with their Ed25519 key.
///   direct    XChaCha20-Poly1305 with the pairwise key (X25519 of both),
///             bound to the sender and recipient user ids.
///   group     XChaCha20-Poly1305 with the group key + sender's signature.
///   groupKey  new group key wrapped for each member, signed by the sender.
///             The key id is a hash of the key, so ids can't be reused.
abstract final class Protocol {
  static const version = 1;
  static const textPrefix = '🔒';

  static const typeAnnounce = 1;
  static const typeDirect = 2;
  static const typeGroup = 3;
  static const typeGroupKey = 4;

  static const contentText = 1;

  static const keyIdBytes = 8;
  static const nonceBytes = 24;
  static const macBytes = 16;
  static const signatureBytes = 64;
  static const groupKeyBytes = 32;

  /// Telegram's limit for a text message, in UTF-16 code units.
  static const maxTextLength = 4096;

  static const maxGroupKeyRecipients = 36;

  static String encodeText(Uint8List envelope) =>
      textPrefix + base64Url.encode(envelope).replaceAll('=', '');

  /// Returns null for ordinary (non-protocol) text.
  static Uint8List? decodeText(String text) {
    if (!text.startsWith(textPrefix)) return null;
    var b64 = text.substring(textPrefix.length).trim();
    b64 = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
    try {
      final bytes = base64Url.decode(b64);
      return bytes.length >= 2 && bytes[0] == version ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  static int? envelopeType(Uint8List envelope) =>
      envelope.length >= 2 ? envelope[1] : null;
}

class ProtocolException implements Exception {
  ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

class PeerKeys {
  PeerKeys({
    required this.userId,
    required this.encPublic,
    required this.signPublic,
    required this.createdAt,
  });

  final int userId;
  final Uint8List encPublic;
  final Uint8List signPublic;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'enc': base64.encode(encPublic),
    'sign': base64.encode(signPublic),
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory PeerKeys.fromJson(Map<String, dynamic> json) => PeerKeys(
    userId: json['userId'] as int,
    encPublic: base64.decode(json['enc'] as String),
    signPublic: base64.decode(json['sign'] as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
  );
}

class GroupKey {
  GroupKey({required this.id, required this.key, required this.createdAt});

  final Uint8List id;
  final SecureKey key;
  final DateTime createdAt;
}

sealed class Payload {
  const Payload();
}

class TextPayload extends Payload {
  const TextPayload(this.text);

  final String text;
}

class UnknownPayload extends Payload {
  const UnknownPayload(this.contentType);

  final int contentType;
}

abstract interface class KeyLookup {
  PeerKeys? peerByEncKeyId(Uint8List keyId);
  PeerKeys? peerBySignKeyId(Uint8List keyId);
  GroupKey? groupKey(int chatId, Uint8List keyId);
}

class OpenedGroupKey {
  OpenedGroupKey({required this.key, required this.distributor});

  final GroupKey key;
  final PeerKeys distributor;
}

class OpenedDirectMessage {
  OpenedDirectMessage({
    required this.payload,
    required this.senderUserId,
    required this.recipientUserId,
  });

  final Payload payload;
  final int senderUserId;
  final int recipientUserId;
}

class OpenedGroupMessage {
  OpenedGroupMessage({required this.payload, required this.sender});

  final Payload payload;
  final PeerKeys sender;
}

class E2eProtocol {
  E2eProtocol(this._sodium, this._me);

  final SodiumSumo _sodium;
  final Identity _me;
  final _pairKeys = <String, SecureKey>{};

  late final Uint8List myEncKeyId = keyId(_me.encryption.publicKey);
  late final Uint8List mySignKeyId = keyId(_me.signing.publicKey);

  PeerKeys get myKeys => PeerKeys(
    userId: _me.userId,
    encPublic: _me.encryption.publicKey,
    signPublic: _me.signing.publicKey,
    createdAt: DateTime.now(),
  );

  /// First 8 bytes of BLAKE2b-128 (generichash can't output less than 16).
  Uint8List keyId(Uint8List publicKey) => Uint8List.fromList(
    _sodium.crypto
        .genericHash(message: publicKey, outLen: 16)
        .sublist(0, Protocol.keyIdBytes),
  );

  // ---------------------------------------------------------------- announce

  Uint8List createAnnouncement() {
    final body =
        (_Writer()
              ..u8(Protocol.version)
              ..u8(Protocol.typeAnnounce)
              ..i64(_me.userId)
              ..i64(DateTime.now().millisecondsSinceEpoch ~/ 1000)
              ..bytes(_me.encryption.publicKey)
              ..bytes(_me.signing.publicKey))
            .take();
    final sig = _sign(_domain('tc-announce-v1', body));
    return _concat([body, sig]);
  }

  /// The caller must check [PeerKeys.userId] against the Telegram sender.
  PeerKeys openAnnouncement(Uint8List envelope) {
    final r = _Reader(envelope)..header(Protocol.typeAnnounce);
    final userId = r.i64();
    final createdAt = r.i64();
    final enc = r.bytes(32);
    final sign = r.bytes(32);
    final bodyLen = r.offset;
    final sig = r.bytes(Protocol.signatureBytes);
    r.end();

    final body = Uint8List.sublistView(envelope, 0, bodyLen);
    if (!_verify(_domain('tc-announce-v1', body), sig, sign)) {
      throw ProtocolException('bad announcement signature');
    }
    if (createdAt <= 0 || createdAt > _maxTimestamp) {
      throw ProtocolException('bad announcement time');
    }
    _pairKey(enc); // rejects low-order keys
    return PeerKeys(
      userId: userId,
      encPublic: enc,
      signPublic: sign,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
    );
  }

  // ------------------------------------------------------------------ direct

  Uint8List encryptDirect(PeerKeys peer, Payload payload) {
    final plain = _encodePayload(payload);
    final header =
        (_Writer()
              ..u8(Protocol.version)
              ..u8(Protocol.typeDirect)
              ..bytes(myEncKeyId)
              ..bytes(keyId(peer.encPublic))
              ..bytes(_nonce()))
            .take();
    final ct = _aead.encrypt(
      message: plain,
      nonce: Uint8List.sublistView(header, header.length - Protocol.nonceBytes),
      key: _pairKey(peer.encPublic),
      additionalData: _directAd(header, _me.userId, peer.userId),
    );
    plain.fillRange(0, plain.length, 0);
    return _concat([header, ct]);
  }

  static Uint8List _directAd(Uint8List header, int sender, int recipient) =>
      _concat([header, _int64(sender), _int64(recipient)]);

  /// Decrypts both incoming and our own outgoing messages. The caller must
  /// check the sender against the Telegram sender and the chat.
  OpenedDirectMessage decryptDirect(Uint8List envelope, KeyLookup keys) {
    final r = _Reader(envelope)..header(Protocol.typeDirect);
    final senderId = r.bytes(Protocol.keyIdBytes);
    final recipientId = r.bytes(Protocol.keyIdBytes);
    final nonce = r.bytes(Protocol.nonceBytes);
    final header = Uint8List.sublistView(envelope, 0, r.offset);
    final ct = r.rest();

    final bool outgoing;
    if (_eq(senderId, myEncKeyId)) {
      outgoing = true;
    } else if (_eq(recipientId, myEncKeyId)) {
      outgoing = false;
    } else {
      throw ProtocolException('message is not for this key');
    }
    final peerKeyId = outgoing ? recipientId : senderId;
    final peer = _eq(peerKeyId, myEncKeyId)
        ? myKeys
        : keys.peerByEncKeyId(peerKeyId);
    if (peer == null) throw ProtocolException('unknown peer key');

    final sender = outgoing ? _me.userId : peer.userId;
    final recipient = outgoing ? peer.userId : _me.userId;
    final plain = _decrypt(
      ct,
      nonce,
      _pairKey(peer.encPublic),
      _directAd(header, sender, recipient),
    );
    return OpenedDirectMessage(
      payload: _decodePayload(plain),
      senderUserId: sender,
      recipientUserId: recipient,
    );
  }

  // ------------------------------------------------------------------- group

  GroupKey generateGroupKey(int chatId) {
    final key = _sodium.secureRandom(Protocol.groupKeyBytes);
    return GroupKey(
      id: _groupKeyId(chatId, key),
      key: key,
      createdAt: DateTime.now(),
    );
  }

  Uint8List _groupKeyId(int chatId, SecureKey key) => key.runUnlockedSync(
    (raw) => Uint8List.fromList(
      _sodium.crypto
          .genericHash(
            message: _concat([utf8.encode('tc-gkid-v1'), _int64(chatId), raw]),
            outLen: 16,
          )
          .sublist(0, Protocol.keyIdBytes),
    ),
  );

  Uint8List encryptGroup(int chatId, GroupKey key, Payload payload) {
    final header =
        (_Writer()
              ..u8(Protocol.version)
              ..u8(Protocol.typeGroup)
              ..bytes(key.id)
              ..bytes(mySignKeyId)
              ..bytes(_nonce()))
            .take();
    final ct = _aead.encrypt(
      message: _encodePayload(payload),
      nonce: Uint8List.sublistView(header, header.length - Protocol.nonceBytes),
      key: key.key,
      additionalData: _concat([header, _int64(chatId)]),
    );
    final sig = _sign(
      _domain('tc-group-v1', _concat([_int64(chatId), header, ct])),
    );
    return _concat([header, ct, sig]);
  }

  /// The caller must check the sender's userId against the Telegram sender.
  OpenedGroupMessage decryptGroup(
    int chatId,
    Uint8List envelope,
    KeyLookup keys,
  ) {
    final r = _Reader(envelope)..header(Protocol.typeGroup);
    final groupKeyId = r.bytes(Protocol.keyIdBytes);
    final signKeyId = r.bytes(Protocol.keyIdBytes);
    final nonce = r.bytes(Protocol.nonceBytes);
    final header = Uint8List.sublistView(envelope, 0, r.offset);
    if (envelope.length - r.offset <
        Protocol.macBytes + Protocol.signatureBytes) {
      throw ProtocolException('truncated');
    }
    final sigStart = envelope.length - Protocol.signatureBytes;
    final ct = Uint8List.sublistView(envelope, r.offset, sigStart);
    final sig = Uint8List.sublistView(envelope, sigStart);

    final sender = _eq(signKeyId, mySignKeyId)
        ? myKeys
        : keys.peerBySignKeyId(signKeyId);
    if (sender == null) throw ProtocolException('unknown sender key');
    final signed = _domain(
      'tc-group-v1',
      _concat([_int64(chatId), header, ct]),
    );
    if (!_verify(signed, sig, sender.signPublic)) {
      throw ProtocolException('bad group message signature');
    }

    final key = keys.groupKey(chatId, groupKeyId);
    if (key == null) throw ProtocolException('unknown group key');
    final plain = _decrypt(
      ct,
      nonce,
      key.key,
      _concat([header, _int64(chatId)]),
    );
    return OpenedGroupMessage(payload: _decodePayload(plain), sender: sender);
  }

  /// Splits into several envelopes if needed. We are always added as a
  /// recipient so our other devices get the key too.
  List<Uint8List> createGroupKeyBundles(
    int chatId,
    GroupKey key,
    List<PeerKeys> recipients,
  ) {
    final all = <Uint8List>[
      _me.encryption.publicKey,
      for (final p in recipients)
        if (!_eq(p.encPublic, _me.encryption.publicKey)) p.encPublic,
    ];
    final ad = _concat([_int64(chatId), key.id]);
    final bundles = <Uint8List>[];

    for (var i = 0; i < all.length; i += Protocol.maxGroupKeyRecipients) {
      final chunk = all.skip(i).take(Protocol.maxGroupKeyRecipients).toList();
      final w = _Writer()
        ..u8(Protocol.version)
        ..u8(Protocol.typeGroupKey)
        ..i64(chatId)
        ..bytes(key.id)
        ..bytes(mySignKeyId)
        ..u8(chunk.length);
      for (final enc in chunk) {
        final nonce = _nonce();
        final wrapped = key.key.runUnlockedSync((raw) {
          final copy = Uint8List.fromList(raw);
          final ct = _aead.encrypt(
            message: copy,
            nonce: nonce,
            key: _pairKey(enc),
            additionalData: ad,
          );
          copy.fillRange(0, copy.length, 0);
          return ct;
        });
        w
          ..bytes(keyId(enc))
          ..bytes(nonce)
          ..bytes(wrapped);
      }
      final body = w.take();
      bundles.add(_concat([body, _sign(_domain('tc-gkey-v1', body))]));
    }
    return bundles;
  }

  OpenedGroupKey? openGroupKeyBundle(
    int chatId,
    Uint8List envelope,
    KeyLookup keys,
  ) {
    final r = _Reader(envelope)..header(Protocol.typeGroupKey);
    final bundleChatId = r.i64();
    final keyIdBytes = r.bytes(Protocol.keyIdBytes);
    final signKeyId = r.bytes(Protocol.keyIdBytes);
    final count = r.u8();
    const entryLen =
        Protocol.keyIdBytes +
        Protocol.nonceBytes +
        Protocol.groupKeyBytes +
        Protocol.macBytes;
    final entriesStart = r.offset;
    r.bytes(count * entryLen);
    final body = Uint8List.sublistView(envelope, 0, r.offset);
    final sig = r.bytes(Protocol.signatureBytes);
    r.end();

    if (bundleChatId != chatId) throw ProtocolException('wrong chat');
    final distributor = _eq(signKeyId, mySignKeyId)
        ? myKeys
        : keys.peerBySignKeyId(signKeyId);
    if (distributor == null) throw ProtocolException('unknown distributor key');
    if (!_verify(_domain('tc-gkey-v1', body), sig, distributor.signPublic)) {
      throw ProtocolException('bad group key signature');
    }

    for (var i = 0; i < count; i++) {
      final e = _Reader(envelope)..offset = entriesStart + i * entryLen;
      final recipient = e.bytes(Protocol.keyIdBytes);
      if (!_eq(recipient, myEncKeyId)) continue;
      final nonce = e.bytes(Protocol.nonceBytes);
      final wrapped = e.bytes(Protocol.groupKeyBytes + Protocol.macBytes);
      final raw = _decrypt(
        wrapped,
        nonce,
        _pairKey(distributor.encPublic),
        _concat([_int64(chatId), keyIdBytes]),
      );
      final secure = _sodium.secureCopy(raw);
      raw.fillRange(0, raw.length, 0);
      if (!_eq(_groupKeyId(chatId, secure), keyIdBytes)) {
        secure.dispose();
        throw ProtocolException('group key id mismatch');
      }
      final key = GroupKey(
        id: keyIdBytes,
        key: secure,
        createdAt: DateTime.now(),
      );
      return OpenedGroupKey(key: key, distributor: distributor);
    }
    return null;
  }

  // ----------------------------------------------------------- safety number

  /// 60 digits, identical on both sides.
  String safetyNumber(PeerKeys peer) {
    String part(PeerKeys k) {
      final h = _sodium.crypto.genericHash(
        message: _concat([
          utf8.encode('tc-fp-v1'),
          _int64(k.userId),
          k.encPublic,
          k.signPublic,
        ]),
        outLen: 30,
      );
      final buf = StringBuffer();
      for (var i = 0; i < 30; i += 5) {
        var v = 0;
        for (var j = 0; j < 5; j++) {
          v = (v << 8) | h[i + j];
        }
        buf.write((v % 100000).toString().padLeft(5, '0'));
      }
      return buf.toString();
    }

    final mine = myKeys;
    final parts = [mine, peer]..sort((a, b) => a.userId.compareTo(b.userId));
    return parts.map(part).join();
  }

  // ----------------------------------------------------------------- helpers

  Aead get _aead => _sodium.crypto.aeadXChaCha20Poly1305IETF;

  Uint8List _nonce() => _sodium.randombytes.buf(Protocol.nonceBytes);

  Uint8List _sign(Uint8List message) => _sodium.crypto.sign.detached(
    message: message,
    secretKey: _me.signing.secretKey,
  );

  bool _verify(Uint8List message, Uint8List sig, Uint8List publicKey) => _sodium
      .crypto
      .sign
      .verifyDetached(message: message, signature: sig, publicKey: publicKey);

  Uint8List _decrypt(
    Uint8List ct,
    Uint8List nonce,
    SecureKey key,
    Uint8List ad,
  ) {
    try {
      return _aead.decrypt(
        cipherText: ct,
        nonce: nonce,
        key: key,
        additionalData: ad,
      );
    } on SodiumException {
      throw ProtocolException('decryption failed');
    }
  }

  SecureKey _pairKey(Uint8List peerEnc) {
    final cacheKey = base64.encode(peerEnc);
    return _pairKeys[cacheKey] ??= () {
      if (peerEnc.length != 32) throw ProtocolException('invalid public key');
      final SecureKey shared;
      try {
        shared = _sodium.crypto.scalarmult(
          n: _me.encryption.secretKey,
          p: peerEnc,
        );
      } on SodiumException {
        throw ProtocolException('invalid public key');
      }
      final mine = _me.encryption.publicKey;
      final (lo, hi) = _compare(mine, peerEnc) <= 0
          ? (mine, peerEnc)
          : (peerEnc, mine);
      final key = shared.runUnlockedSync(
        (s) => _sodium.crypto.genericHash(
          message: _concat([utf8.encode('tc-pair-v1'), s, lo, hi]),
          outLen: 32,
        ),
      );
      shared.dispose();
      final secure = _sodium.secureCopy(key);
      key.fillRange(0, key.length, 0);
      return secure;
    }();
  }

  static Uint8List _encodePayload(Payload payload) => switch (payload) {
    TextPayload(:final text) => _concat([
      Uint8List.fromList([Protocol.contentText]),
      utf8.encode(text),
    ]),
    UnknownPayload() => throw ArgumentError('cannot encode unknown payload'),
  };

  @visibleForTesting
  static Payload decodePayload(Uint8List plain) => _decodePayload(plain);

  static Payload _decodePayload(Uint8List plain) {
    if (plain.isEmpty) throw ProtocolException('empty payload');
    final body = Uint8List.sublistView(plain, 1);
    return switch (plain[0]) {
      Protocol.contentText => TextPayload(_utf8(body)),
      final other => UnknownPayload(other),
    };
  }

  static String _utf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw ProtocolException('invalid text');
    }
  }

  /// Seconds; rejects values that can't be a date.
  static const _maxTimestamp = 1 << 40;

  void dispose() {
    for (final k in _pairKeys.values) {
      k.dispose();
    }
    _pairKeys.clear();
  }
}

// --------------------------------------------------------------- byte helpers

Uint8List _domain(String domain, Uint8List body) =>
    _concat([utf8.encode(domain), body]);

Uint8List _int64(int v) => (ByteData(8)..setInt64(0, v)).buffer.asUint8List();

Uint8List _concat(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.takeBytes();
}

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _compare(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

class _Writer {
  final _b = BytesBuilder();

  void u8(int v) => _b.addByte(v);
  void i64(int v) => _b.add(_int64(v));
  void bytes(List<int> v) => _b.add(v);
  Uint8List take() => _b.takeBytes();
}

class _Reader {
  _Reader(this._data);

  final Uint8List _data;
  int offset = 0;

  void header(int expectedType) {
    if (u8() != Protocol.version) {
      throw ProtocolException('unsupported version');
    }
    if (u8() != expectedType) throw ProtocolException('unexpected type');
  }

  int u8() {
    _need(1);
    return _data[offset++];
  }

  int i64() {
    _need(8);
    final v = ByteData.sublistView(_data, offset, offset + 8).getInt64(0);
    offset += 8;
    return v;
  }

  Uint8List bytes(int n) {
    _need(n);
    final v = Uint8List.fromList(
      Uint8List.sublistView(_data, offset, offset + n),
    );
    offset += n;
    return v;
  }

  Uint8List rest() {
    final v = Uint8List.sublistView(_data, offset);
    offset = _data.length;
    return v;
  }

  void end() {
    if (offset != _data.length) throw ProtocolException('trailing bytes');
  }

  void _need(int n) {
    if (offset + n > _data.length) throw ProtocolException('truncated');
  }
}
