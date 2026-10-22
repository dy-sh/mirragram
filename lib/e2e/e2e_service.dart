import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import '../crypto/identity.dart';
import '../crypto/protocol.dart';
import '../tdlib/td_client.dart';
import 'key_store.dart';

enum E2eStatus { loading, needsPassword, ready }

/// How a protocol message should be displayed.
sealed class E2eView {
  const E2eView();
}

class E2eText extends E2eView {
  const E2eText(this.text);

  final String text;
}

class E2eKeyAnnouncement extends E2eView {
  const E2eKeyAnnouncement({required this.userId, required this.valid});

  final int userId;
  final bool valid;
}

class E2eGroupKeyAnnouncement extends E2eView {
  const E2eGroupKeyAnnouncement({required this.forMe});

  final bool forMe;
}

enum UndecryptableReason {
  noSenderKey,
  noGroupKey,
  otherKey,
  forgedSender,
  unsupported,
  corrupted,
}

class E2eUndecryptable extends E2eView {
  const E2eUndecryptable(this.reason);

  final UndecryptableReason reason;
}

class E2eLocked extends E2eView {
  const E2eLocked();
}

enum E2eError { noPeerKey, noGroupKey, tooLong }

class E2eException implements Exception {
  E2eException(this.error);

  final E2eError error;

  @override
  String toString() => 'E2eException(${error.name})';
}

class E2eService extends ChangeNotifier {
  E2eService(this._sodium, this._dataDir);

  final SodiumSumo _sodium;
  final Directory _dataDir;
  final _secure = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  E2eStatus status = E2eStatus.loading;
  int? _userId;
  Identity? _identity;
  E2eProtocol? _proto;
  KeyStore? _store;

  int keysVersion = 0;
  final _cache = <String, E2eView>{};

  bool get isReady => status == E2eStatus.ready;
  KeyStore get store => _store!;
  E2eProtocol get protocol => _proto!;

  String _seedKey(int userId) => 'e2e_seed_$userId';

  Future<void> init(int userId) async {
    _userId = userId;
    final seed = await _secure.read(key: _seedKey(userId));
    if (seed == null) {
      status = E2eStatus.needsPassword;
      notifyListeners();
      return;
    }
    await _activate(base64.decode(seed));
  }

  /// Keys are derived from the password, so creating keys and restoring
  /// them on a new device is the same operation.
  Future<void> setPassword(String password) async {
    final userId = _userId!;
    final seed = await Identity.deriveSeed(password: password, userId: userId);
    await _secure.write(key: _seedKey(userId), value: base64.encode(seed));
    await _activate(seed);
  }

  Future<void> _activate(Uint8List seed) async {
    _dispose();
    final identity = Identity.fromSeed(_sodium, seed, _userId!);
    seed.fillRange(0, seed.length, 0);
    final proto = E2eProtocol(_sodium, identity);
    _identity = identity;
    _proto = proto;
    _store = await KeyStore.open(
      sodium: _sodium,
      file: File(p.join(_dataDir.path, 'keys_$_userId.bin')),
      storageKey: identity.storageKey,
      keyId: proto.keyId,
    );
    status = E2eStatus.ready;
    _changed();
  }

  Future<void> reset() async {
    if (_userId != null) await _secure.delete(key: _seedKey(_userId!));
    _dispose();
    status = E2eStatus.loading;
    _userId = null;
    _changed();
  }

  void refresh() => _changed();

  void _changed() {
    keysVersion++;
    _cache.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------- incoming

  /// Picks up key announcements and group keys. Messages must be in
  /// chronological order.
  void ingest(Iterable<TdObject> messages) {
    if (!isReady) return;
    var changed = false;
    for (final m in messages) {
      final envelope = _envelope(m);
      if (envelope == null) continue;
      final chatId = m['chat_id'] as int;
      try {
        switch (Protocol.envelopeType(envelope)) {
          case Protocol.typeAnnounce:
            final keys = protocol.openAnnouncement(envelope);
            if (keys.userId != senderUserId(m)) break;
            if (keys.userId == _userId) {
              changed |= store.markAnnounced(chatId);
            } else {
              changed |= store.addPeer(keys);
              changed |= store.markChatActive(chatId);
            }
          case Protocol.typeGroupKey:
            final opened = protocol.openGroupKeyBundle(chatId, envelope, store);
            if (opened != null &&
                opened.distributor.userId == senderUserId(m)) {
              changed |= store.addGroupKey(
                chatId,
                opened.key,
                own: opened.distributor.userId == _userId,
              );
            }
        }
      } on ProtocolException {
        // Damaged or not ours: shown as undecryptable.
      }
    }
    if (changed) _changed();
  }

  /// Returns null for regular messages.
  E2eView? view(TdObject message) {
    final text = messageText(message);
    if (text == null || !text.startsWith(Protocol.textPrefix)) return null;
    final cacheKey = '${message['chat_id']}:${message['id']}:${text.hashCode}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final envelope = Protocol.decodeText(text);
    if (envelope == null) return null;
    if (!isReady) return const E2eLocked();

    final chatId = message['chat_id'] as int;
    final sender = senderUserId(message);
    final E2eView result;
    try {
      result = switch (Protocol.envelopeType(envelope)) {
        Protocol.typeAnnounce => () {
          final keys = protocol.openAnnouncement(envelope);
          return E2eKeyAnnouncement(
            userId: keys.userId,
            valid: keys.userId == sender,
          );
        }(),
        Protocol.typeDirect => _payloadView(
          protocol.decryptDirect(envelope, store),
        ),
        Protocol.typeGroup => () {
          final opened = protocol.decryptGroup(chatId, envelope, store);
          if (opened.sender.userId != sender) {
            return const E2eUndecryptable(UndecryptableReason.forgedSender);
          }
          return _payloadView(opened.payload);
        }(),
        Protocol.typeGroupKey => E2eGroupKeyAnnouncement(
          forMe: protocol.openGroupKeyBundle(chatId, envelope, store) != null,
        ),
        _ => const E2eUndecryptable(UndecryptableReason.unsupported),
      };
    } on ProtocolException catch (e) {
      return _cache[cacheKey] = E2eUndecryptable(_reason(e));
    }
    return _cache[cacheKey] = result;
  }

  E2eView _payloadView(Payload payload) => switch (payload) {
    TextPayload(:final text) => E2eText(text),
    UnknownPayload() => const E2eUndecryptable(UndecryptableReason.unsupported),
  };

  UndecryptableReason _reason(ProtocolException e) => switch (e.message) {
    'unknown peer key' ||
    'unknown sender key' => UndecryptableReason.noSenderKey,
    'unknown group key' => UndecryptableReason.noGroupKey,
    'message is not for this key' => UndecryptableReason.otherKey,
    _ => UndecryptableReason.corrupted,
  };

  Uint8List? _envelope(TdObject message) {
    final text = messageText(message);
    return text == null ? null : Protocol.decodeText(text);
  }

  // ------------------------------------------------------------- outgoing

  String announcementText() =>
      Protocol.encodeText(protocol.createAnnouncement());

  String encryptDirect(int peerUserId, String text) {
    final peer = peerUserId == _userId
        ? protocol.myKeys
        : store.peer(peerUserId);
    if (peer == null) {
      throw E2eException(E2eError.noPeerKey);
    }
    return _checkLength(protocol.encryptDirect(peer, TextPayload(text)));
  }

  String encryptGroup(int chatId, String text) {
    final key = store.currentGroupKey(chatId);
    if (key == null) throw E2eException(E2eError.noGroupKey);
    return _checkLength(protocol.encryptGroup(chatId, key, TextPayload(text)));
  }

  /// Returns the messages to post in the group.
  ({List<String> messages, int recipients}) rotateGroupKey(
    int chatId,
    Iterable<int> memberUserIds,
  ) {
    final members = memberUserIds.toSet();
    final recipients = store.allPeers
        .where((k) => members.contains(k.userId))
        .toList();
    final key = protocol.generateGroupKey();
    store.addGroupKey(chatId, key, own: true);
    _changed();
    final bundles = protocol.createGroupKeyBundles(chatId, key, recipients);
    return (
      messages: bundles.map(Protocol.encodeText).toList(),
      recipients: recipients.length,
    );
  }

  /// When a new member announces their key in a group whose current key we
  /// distributed, returns a bundle for them. Call for live messages only.
  String? reshareGroupKey(TdObject message) {
    if (!isReady) return null;
    final chatId = message['chat_id'] as int;
    final envelope = _envelope(message);
    if (envelope == null ||
        Protocol.envelopeType(envelope) != Protocol.typeAnnounce ||
        message['is_outgoing'] == true ||
        !store.isEncryptionEnabled(chatId) ||
        !store.ownsGroupKey(chatId)) {
      return null;
    }
    final key = store.currentGroupKey(chatId);
    final peer = store.peer(senderUserId(message) ?? 0);
    if (key == null || peer == null) return null;
    final bundles = protocol.createGroupKeyBundles(chatId, key, [peer]);
    return Protocol.encodeText(bundles.single);
  }

  String _checkLength(Uint8List envelope) {
    final text = Protocol.encodeText(envelope);
    if (text.length > Protocol.maxTextLength) {
      throw E2eException(E2eError.tooLong);
    }
    return text;
  }

  String? safetyNumber(int peerUserId) {
    final peer = store.peer(peerUserId);
    return peer == null ? null : protocol.safetyNumber(peer);
  }

  void _dispose() {
    _proto?.dispose();
    _identity?.dispose();
    _proto = null;
    _identity = null;
    _store = null;
  }
}

// ------------------------------------------------------------ td helpers

String? messageText(TdObject message) {
  final content = message['content'] as TdObject?;
  if (content?['@type'] != 'messageText') return null;
  return (content!['text'] as TdObject)['text'] as String;
}

int? senderUserId(TdObject message) {
  final sender = message['sender_id'] as TdObject?;
  return sender?['@type'] == 'messageSenderUser'
      ? sender!['user_id'] as int
      : null;
}
