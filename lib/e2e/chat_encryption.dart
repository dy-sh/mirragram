import '../tdlib/td_client.dart';
import '../telegram/telegram_service.dart';
import 'e2e_service.dart';

enum ChatE2eState {
  /// Channels, secret chats and other chat types.
  unsupported,

  /// No encryption password on this device yet.
  locked,
  off,

  /// Enabled, but the peer's key or the group key is missing.
  waiting,
  on,
}

class ChatEncryption {
  ChatEncryption(this._tg, this._e2e, this.chat);

  final TelegramService _tg;
  final E2eService _e2e;
  final TdObject chat;

  int get chatId => chat['id'] as int;
  int? get peerUserId => _tg.privateUserId(chat);
  bool get isGroup => _tg.isGroup(chat);

  ChatE2eState get state {
    if (peerUserId == null && !isGroup) return ChatE2eState.unsupported;
    if (!_e2e.isReady) return ChatE2eState.locked;
    if (!_e2e.store.isEncryptionEnabled(chatId)) return ChatE2eState.off;
    return hasKey ? ChatE2eState.on : ChatE2eState.waiting;
  }

  bool get hasKey => isGroup
      ? _e2e.store.currentGroupKey(chatId) != null
      : (peerUserId == _tg.myUserId || _e2e.store.peer(peerUserId!) != null);

  /// The peer or the group already uses encryption, but we don't.
  bool get isOffered =>
      peerUserId != _tg.myUserId &&
      _e2e.isReady &&
      !_e2e.store.isEncryptionEnabled(chatId) &&
      (hasKey || _e2e.store.isChatActive(chatId));

  Future<void> enable() async {
    _e2e.store.setEncryptionEnabled(chatId, true);
    if (peerUserId != _tg.myUserId && !_e2e.store.hasAnnounced(chatId)) {
      await _tg.sendText(
        chatId,
        _e2e.announcementText(),
        disableLinkPreview: true,
      );
      _e2e.store.markAnnounced(chatId);
    }
    if (isGroup && _e2e.store.currentGroupKey(chatId) == null) {
      await rotateGroupKey();
    }
    _e2e.refresh();
  }

  void disable() {
    _e2e.store.setEncryptionEnabled(chatId, false);
    _e2e.refresh();
  }

  /// Returns the number of recipients, excluding us.
  Future<int> rotateGroupKey() async {
    final members = await _tg.groupMemberIds(chat);
    final result = _e2e.rotateGroupKey(chatId, members);
    for (final text in result.messages) {
      await _tg.sendText(chatId, text, disableLinkPreview: true);
    }
    return result.recipients;
  }

  /// Returns the text to send and whether it is encrypted.
  (String, bool) prepareOutgoing(String text) {
    if (state == ChatE2eState.off ||
        state == ChatE2eState.unsupported ||
        state == ChatE2eState.locked) {
      return (text, false);
    }
    final encrypted = isGroup
        ? _e2e.encryptGroup(chatId, text)
        : _e2e.encryptDirect(peerUserId!, text);
    return (encrypted, true);
  }
}
