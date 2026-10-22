import 'dart:async';

import 'package:flutter/foundation.dart';

import '../e2e/e2e_service.dart';
import '../tdlib/td_client.dart';
import 'telegram_service.dart';

/// Messages of an open chat, sorted by id.
class ChatController extends ChangeNotifier {
  ChatController(this._tg, this._e2e, this.chatId) {
    _sub = _tg.messageUpdates.listen(_onUpdate);
    unawaited(_tg.client.send({'@type': 'openChat', 'chat_id': chatId}));
    unawaited(_loadInitial());
  }

  final TelegramService _tg;
  final E2eService _e2e;
  final int chatId;
  late final StreamSubscription<TdObject> _sub;

  final messages = <TdObject>[];
  bool loadingOlder = false;
  bool reachedStart = false;

  Future<void> _loadInitial() async {
    // TDLib returns only locally cached messages first.
    while (messages.length < 30 && !reachedStart && !_disposed) {
      if (!await loadOlder()) return;
    }
    unawaited(_scanForKeys().catchError((_) {}));
  }

  /// Returns false if loading failed.
  Future<bool> loadOlder() async {
    if (loadingOlder || reachedStart || _disposed) return true;
    loadingOlder = true;
    try {
      final page = await _history(
        messages.isEmpty ? 0 : messages.first['id'] as int,
        50,
      );
      if (page.isEmpty) {
        reachedStart = true;
      } else {
        _e2e.ingest(page);
        _insert(page);
        _markRead(page);
      }
      return true;
    } on TdError {
      return false;
    } finally {
      loadingOlder = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Keys may have been announced long ago, so older history is scanned
  /// for them without being displayed.
  Future<void> _scanForKeys() async {
    if (!_e2e.isReady || messages.isEmpty) return;
    var from = messages.first['id'] as int;
    for (var scanned = 0; scanned < 500 && !_disposed;) {
      final page = await _history(from, 100);
      if (page.isEmpty) break;
      _e2e.ingest(page);
      scanned += page.length;
      from = page.last['id'] as int;
    }
  }

  Future<List<TdObject>> _history(int fromMessageId, int limit) async {
    final res = await _tg.client.send({
      '@type': 'getChatHistory',
      'chat_id': chatId,
      'from_message_id': fromMessageId,
      'offset': 0,
      'limit': limit,
      'only_local': false,
    });
    return (res['messages'] as List).cast<TdObject>();
  }

  void _insert(Iterable<TdObject> items) {
    final byId = {for (final m in messages) m['id'] as int: m};
    for (final m in items) {
      byId[m['id'] as int] = m;
    }
    messages
      ..clear()
      ..addAll(
        byId.values.toList()
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int)),
      );
  }

  void _markRead(Iterable<TdObject> items) {
    final ids = [
      for (final m in items)
        if (m['is_outgoing'] != true) m['id'],
    ];
    if (ids.isEmpty) return;
    unawaited(
      _tg.client.send({
        '@type': 'viewMessages',
        'chat_id': chatId,
        'message_ids': ids,
        'source': null,
        'force_read': true,
      }),
    );
  }

  void _onUpdate(TdObject u) {
    switch (u['@type']) {
      case 'updateNewMessage':
        final m = u['message'] as TdObject;
        if (m['chat_id'] != chatId) return;
        _insert([m]);
        _markRead([m]);
      case 'updateMessageSendSucceeded' || 'updateMessageSendFailed':
        final m = u['message'] as TdObject;
        if (m['chat_id'] != chatId) return;
        messages.removeWhere((x) => x['id'] == u['old_message_id']);
        _insert([m]);
      case 'updateMessageContent':
        if (u['chat_id'] != chatId) return;
        final m = messages.where((x) => x['id'] == u['message_id']).firstOrNull;
        if (m == null) return;
        m['content'] = u['new_content'];
      case 'updateMessageEdited':
        if (u['chat_id'] != chatId) return;
        final m = messages.where((x) => x['id'] == u['message_id']).firstOrNull;
        if (m == null) return;
        m['edit_date'] = u['edit_date'];
      case 'updateDeleteMessages':
        if (u['chat_id'] != chatId || u['is_permanent'] != true) return;
        final ids = (u['message_ids'] as List).toSet();
        messages.removeWhere((x) => ids.contains(x['id']));
      default:
        return;
    }
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    unawaited(_tg.client.send({'@type': 'closeChat', 'chat_id': chatId}));
    super.dispose();
  }
}
