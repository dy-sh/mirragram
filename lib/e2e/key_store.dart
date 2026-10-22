import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/protocol.dart';

/// Peer and group keys, stored in a file encrypted with
/// [Identity.storageKey].
class KeyStore implements KeyLookup {
  KeyStore._(this._sodium, this._file, this._storageKey, this._keyId);

  final SodiumSumo _sodium;
  final File _file;
  final SecureKey _storageKey;
  final Uint8List Function(Uint8List) _keyId;

  /// Old keys are kept to read history; the newest one is current.
  final _peers = <int, List<PeerKeys>>{};
  final _verified = <int>{};

  final _groupKeys = <int, List<GroupKey>>{};

  final _encryptedChats = <int>{};

  final _announcedChats = <int>{};

  /// Chats where someone else announced a key.
  final _activeChats = <int>{};

  /// Ids of group keys we distributed.
  final _ownedGroupKeyIds = <String>{};

  static Future<KeyStore> open({
    required SodiumSumo sodium,
    required File file,
    required SecureKey storageKey,
    required Uint8List Function(Uint8List) keyId,
  }) async {
    final store = KeyStore._(sodium, file, storageKey, keyId);
    if (await file.exists()) {
      try {
        store._load(await file.readAsBytes());
      } catch (_) {
        // Damaged store: keep it aside and rebuild keys from chat history.
        store._clear();
        await file.rename('${file.path}.corrupt');
      }
    }
    return store;
  }

  // ------------------------------------------------------------------ peers

  PeerKeys? peer(int userId) => _newest(_peers[userId], (k) => k.createdAt);

  bool isVerified(int userId) => _verified.contains(userId);

  /// Returns true if the key is new. A changed key resets verification.
  bool addPeer(PeerKeys keys) {
    final list = _peers.putIfAbsent(keys.userId, () => []);
    if (list.any((k) => _eq(k.encPublic, keys.encPublic))) return false;
    final current = peer(keys.userId);
    if (current != null && keys.createdAt.isAfter(current.createdAt)) {
      _verified.remove(keys.userId);
    }
    list.add(keys);
    _save();
    return true;
  }

  void setVerified(int userId, bool verified) {
    verified ? _verified.add(userId) : _verified.remove(userId);
    _save();
  }

  Iterable<PeerKeys> get allPeers => _peers.keys.map((id) => peer(id)!);

  @override
  PeerKeys? peerByEncKeyId(Uint8List keyId) =>
      _findPeer((k) => k.encPublic, keyId);

  @override
  PeerKeys? peerBySignKeyId(Uint8List keyId) =>
      _findPeer((k) => k.signPublic, keyId);

  PeerKeys? _findPeer(Uint8List Function(PeerKeys) pick, Uint8List keyId) {
    for (final list in _peers.values) {
      for (final k in list) {
        if (_eq(_keyId(pick(k)), keyId)) return k;
      }
    }
    return null;
  }

  // ----------------------------------------------------------------- groups

  GroupKey? currentGroupKey(int chatId) =>
      _newest(_groupKeys[chatId], (k) => k.createdAt);

  @override
  GroupKey? groupKey(int chatId, Uint8List keyId) =>
      _groupKeys[chatId]?.where((k) => _eq(k.id, keyId)).firstOrNull;

  /// [key.createdAt] should be the Telegram date of the message that
  /// delivered it, so the newest key wins regardless of processing order.
  bool addGroupKey(int chatId, GroupKey key, {required bool own}) {
    final list = _groupKeys.putIfAbsent(chatId, () => []);
    if (list.any((k) => _eq(k.id, key.id))) {
      key.key.dispose();
      return false;
    }
    list.add(key);
    if (own) _ownedGroupKeyIds.add(base64.encode(key.id));
    _save();
    return true;
  }

  bool ownsGroupKey(int chatId) {
    final key = currentGroupKey(chatId);
    return key != null && _ownedGroupKeyIds.contains(base64.encode(key.id));
  }

  static T? _newest<T>(List<T>? list, DateTime Function(T) date) {
    if (list == null || list.isEmpty) return null;
    return list.reduce((a, b) => date(b).isAfter(date(a)) ? b : a);
  }

  // --------------------------------------------------------------- settings

  bool isEncryptionEnabled(int chatId) => _encryptedChats.contains(chatId);

  void setEncryptionEnabled(int chatId, bool enabled) {
    enabled ? _encryptedChats.add(chatId) : _encryptedChats.remove(chatId);
    _save();
  }

  bool hasAnnounced(int chatId) => _announcedChats.contains(chatId);

  bool isChatActive(int chatId) => _activeChats.contains(chatId);

  bool markChatActive(int chatId) {
    if (!_activeChats.add(chatId)) return false;
    _save();
    return true;
  }

  bool markAnnounced(int chatId) {
    if (!_announcedChats.add(chatId)) return false;
    _save();
    return true;
  }

  // ------------------------------------------------------------ persistence

  void _load(Uint8List data) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = Uint8List.sublistView(data, 0, aead.nonceBytes);
    final plain = aead.decrypt(
      cipherText: Uint8List.sublistView(data, aead.nonceBytes),
      nonce: nonce,
      key: _storageKey,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;

    for (final e in (json['peers'] as Map<String, dynamic>).entries) {
      _peers[int.parse(e.key)] = [
        for (final k in e.value as List)
          PeerKeys.fromJson(k as Map<String, dynamic>),
      ];
    }
    _verified.addAll((json['verified'] as List).cast<int>());
    for (final e in (json['groups'] as Map<String, dynamic>).entries) {
      _groupKeys[int.parse(e.key)] = [
        for (final k in (e.value as List).cast<Map<String, dynamic>>())
          GroupKey(
            id: base64.decode(k['id'] as String),
            key: _sodium.secureCopy(base64.decode(k['key'] as String)),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              k['createdAt'] as int,
            ),
          ),
      ];
    }
    _encryptedChats.addAll((json['encryptedChats'] as List).cast<int>());
    _announcedChats.addAll((json['announcedChats'] as List? ?? []).cast<int>());
    _activeChats.addAll((json['activeChats'] as List? ?? []).cast<int>());
    _ownedGroupKeyIds.addAll(
      (json['ownedGroupKeyIds'] as List? ?? []).cast<String>(),
    );
  }

  void _clear() {
    dispose();
    _peers.clear();
    _verified.clear();
    _encryptedChats.clear();
    _announcedChats.clear();
    _activeChats.clear();
    _ownedGroupKeyIds.clear();
  }

  void dispose() {
    for (final list in _groupKeys.values) {
      for (final k in list) {
        k.key.dispose();
      }
    }
    _groupKeys.clear();
  }

  void _save() {
    final json = {
      'peers': {
        for (final e in _peers.entries)
          '${e.key}': [for (final k in e.value) k.toJson()],
      },
      'verified': _verified.toList(),
      'groups': {
        for (final e in _groupKeys.entries)
          '${e.key}': [
            for (final k in e.value)
              {
                'id': base64.encode(k.id),
                'key': k.key.runUnlockedSync(base64.encode),
                'createdAt': k.createdAt.millisecondsSinceEpoch,
              },
          ],
      },
      'encryptedChats': _encryptedChats.toList(),
      'announcedChats': _announcedChats.toList(),
      'activeChats': _activeChats.toList(),
      'ownedGroupKeyIds': _ownedGroupKeyIds.toList(),
    };
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final ct = aead.encrypt(
      message: utf8.encode(jsonEncode(json)),
      nonce: nonce,
      key: _storageKey,
    );
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsBytesSync([...nonce, ...ct], flush: true);
    tmp.renameSync(_file.path);
  }

  static bool _eq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
