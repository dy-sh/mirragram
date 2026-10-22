import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../tdlib/td_client.dart';

/// API credentials from https://my.telegram.org, passed at build time:
///   flutter run --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...
const _apiId = int.fromEnvironment('TG_API_ID');
const _apiHash = String.fromEnvironment('TG_API_HASH');
const _useTestDc = bool.fromEnvironment('TG_TEST_DC');

/// Keep in sync with `version` in pubspec.yaml (checked by a test).
const appVersion = '0.1.0';

/// Account state and a cache of TDLib objects kept up to date by updates.
class TelegramService extends ChangeNotifier {
  TelegramService._(this.client, this._dataDir, this._createClient);

  TdClient client;
  StreamSubscription<TdObject>? _updatesSub;
  final Directory _dataDir;
  final Future<TdClient> Function() _createClient;

  TdObject authState = const {'@type': 'authorizationStateWaitTdlibParameters'};
  int? myUserId;

  final chats = <int, TdObject>{};
  final users = <int, TdObject>{};
  final basicGroups = <int, TdObject>{};
  final supergroups = <int, TdObject>{};
  final files = <int, TdObject>{};

  /// Keyed by `for_dark_theme`.
  final defaultBackgrounds = <bool, TdObject?>{};
  final _requestedFiles = <int>{};

  final _messageUpdates = StreamController<TdObject>.broadcast();
  Stream<TdObject> get messageUpdates => _messageUpdates.stream;

  bool _notifyScheduled = false;
  bool _chatsLoaded = false;

  static Future<TelegramService> start(
    Directory dataDir, {
    Future<TdClient> Function()? createClient,
  }) async {
    if (createClient == null && (_apiId == 0 || _apiHash.isEmpty)) {
      throw StateError(
        'TG_API_ID and TG_API_HASH are not set. Get them at my.telegram.org '
        'and run: flutter run --dart-define=TG_API_ID=... '
        '--dart-define=TG_API_HASH=...',
      );
    }
    final create = createClient ?? TdClient.create;
    final service = TelegramService._(await create(), dataDir, create);
    service._updatesSub = service.client.updates.listen(service._onUpdate);
    return service;
  }

  /// TDLib closes the client after logOut; a new login needs a new one.
  Future<void> _restartClient() async {
    await _updatesSub?.cancel();
    client.dispose();
    client = await _createClient();
    _updatesSub = client.updates.listen(_onUpdate);
  }

  String get authStateType => authState['@type'] as String;

  // ----------------------------------------------------------------- updates

  void _onUpdate(TdObject u) {
    switch (u['@type']) {
      case 'updateAuthorizationState':
        _onAuthState(u['authorization_state'] as TdObject).catchError((_) {});
      case 'updateNewChat':
        final chat = u['chat'] as TdObject;
        chats[chat['id'] as int] = chat;
      case 'updateChatTitle':
        _patchChat(u, {'title': u['title']});
      case 'updateChatPhoto':
        _patchChat(u, {'photo': u['photo']});
      case 'updateChatLastMessage':
        _patchChat(u, {'last_message': u['last_message']});
        _setPositions(u['chat_id'] as int, u['positions'] as List);
      case 'updateChatPosition':
        _setPosition(u['chat_id'] as int, u['position'] as TdObject);
      case 'updateChatDraftMessage':
        _patchChat(u, {'draft_message': u['draft_message']});
        _setPositions(u['chat_id'] as int, u['positions'] as List);
      case 'updateChatReadInbox':
        _patchChat(u, {
          'last_read_inbox_message_id': u['last_read_inbox_message_id'],
          'unread_count': u['unread_count'],
        });
      case 'updateChatReadOutbox':
        _patchChat(u, {
          'last_read_outbox_message_id': u['last_read_outbox_message_id'],
        });
      case 'updateChatUnreadMentionCount':
        _patchChat(u, {'unread_mention_count': u['unread_mention_count']});
      case 'updateChatBackground':
        _patchChat(u, {'background': u['background']});
      case 'updateDefaultBackground':
        defaultBackgrounds[u['for_dark_theme'] == true] =
            u['background'] as TdObject?;
      case 'updateChatNotificationSettings':
        _patchChat(u, {'notification_settings': u['notification_settings']});
      case 'updateUser':
        final user = u['user'] as TdObject;
        users[user['id'] as int] = user;
      case 'updateUserStatus':
        final user = users[u['user_id'] as int];
        if (user != null) user['status'] = u['status'];
      case 'updateBasicGroup':
        final g = u['basic_group'] as TdObject;
        basicGroups[g['id'] as int] = g;
      case 'updateSupergroup':
        final g = u['supergroup'] as TdObject;
        supergroups[g['id'] as int] = g;
      case 'updateFile':
        final f = u['file'] as TdObject;
        files[f['id'] as int] = f;
      case 'updateNewMessage' ||
          'updateMessageSendSucceeded' ||
          'updateMessageSendFailed' ||
          'updateMessageContent' ||
          'updateMessageEdited' ||
          'updateDeleteMessages':
        _messageUpdates.add(u);
        return;
      default:
        return;
    }
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void _patchChat(TdObject u, Map<String, dynamic> fields) {
    chats[u['chat_id'] as int]?.addAll(fields);
  }

  void _setPositions(int chatId, List positions) {
    for (final pos in positions) {
      _setPosition(chatId, pos as TdObject);
    }
  }

  void _setPosition(int chatId, TdObject position) {
    final chat = chats[chatId];
    if (chat == null) return;
    final listType = (position['list'] as TdObject)['@type'];
    final positions = (chat['positions'] as List? ?? [])
        .cast<TdObject>()
        .where((pos) => (pos['list'] as TdObject)['@type'] != listType)
        .toList();
    if (position['order'] != '0') positions.add(position);
    chat['positions'] = positions;
  }

  // -------------------------------------------------------------------- auth

  Future<void> _onAuthState(TdObject state) async {
    authState = state;
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        await client.send({
          '@type': 'setTdlibParameters',
          'use_test_dc': _useTestDc,
          'database_directory': p.join(_dataDir.path, 'tdlib'),
          'files_directory': p.join(_dataDir.path, 'tdlib_files'),
          'database_encryption_key': '',
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'api_id': _apiId,
          'api_hash': _apiHash,
          'system_language_code':
              PlatformDispatcher.instance.locale.languageCode,
          'device_model': Platform.operatingSystem,
          'system_version': Platform.operatingSystemVersion,
          'application_version': appVersion,
        });
      case 'authorizationStateReady':
        final me = await client.send({'@type': 'getMe'});
        myUserId = me['id'] as int;
        users[myUserId!] = me;
        unawaited(loadChats());
      case 'authorizationStateClosed':
        myUserId = null;
        for (final cache in [chats, users, basicGroups, supergroups, files]) {
          cache.clear();
        }
        _requestedFiles.clear();
        defaultBackgrounds.clear();
        _chatsLoaded = false;
        unawaited(_restartClient());
    }
    _scheduleNotify();
  }

  Future<void> sendPhoneNumber(String phone) => client.send({
    '@type': 'setAuthenticationPhoneNumber',
    'phone_number': phone,
  });

  Future<void> sendCode(String code) =>
      client.send({'@type': 'checkAuthenticationCode', 'code': code});

  Future<void> sendPassword(String password) => client.send({
    '@type': 'checkAuthenticationPassword',
    'password': password,
  });

  Future<void> register(String firstName, String lastName) => client.send({
    '@type': 'registerUser',
    'first_name': firstName,
    'last_name': lastName,
  });

  Future<void> logOut() => client.send({'@type': 'logOut'});

  // ------------------------------------------------------------------- chats

  Future<void> loadChats() async {
    if (_chatsLoaded) return;
    try {
      while (true) {
        await client.send({
          '@type': 'loadChats',
          'chat_list': {'@type': 'chatListMain'},
          'limit': 100,
        });
      }
    } on TdError catch (e) {
      if (e.code == 404) _chatsLoaded = true;
    }
  }

  List<TdObject> get mainChatList {
    final result = <(int, TdObject)>[];
    for (final chat in chats.values) {
      for (final pos in (chat['positions'] as List? ?? []).cast<TdObject>()) {
        if ((pos['list'] as TdObject)['@type'] == 'chatListMain') {
          result.add((int.parse(pos['order'] as String), chat));
        }
      }
    }
    result.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final r in result) r.$2];
  }

  bool isPinned(TdObject chat) =>
      (chat['positions'] as List? ?? []).cast<TdObject>().any(
        (pos) =>
            (pos['list'] as TdObject)['@type'] == 'chatListMain' &&
            pos['is_pinned'] == true,
      );

  bool isMuted(TdObject chat) =>
      ((chat['notification_settings'] as TdObject?)?['mute_for'] as int? ?? 0) >
      0;

  int? privateUserId(TdObject chat) {
    final type = chat['type'] as TdObject;
    return type['@type'] == 'chatTypePrivate' ? type['user_id'] as int : null;
  }

  bool isGroup(TdObject chat) {
    final type = chat['type'] as TdObject;
    return type['@type'] == 'chatTypeBasicGroup' ||
        (type['@type'] == 'chatTypeSupergroup' && type['is_channel'] != true);
  }

  bool isSavedMessages(TdObject chat) =>
      myUserId != null && privateUserId(chat) == myUserId;

  bool isVerified(TdObject chat) {
    final type = chat['type'] as TdObject;
    final TdObject? owner = switch (type['@type']) {
      'chatTypePrivate' => users[type['user_id']],
      'chatTypeSupergroup' => supergroups[type['supergroup_id']],
      _ => null,
    };
    final status = owner?['verification_status'] as TdObject?;
    return status?['is_verified'] == true;
  }

  int? memberCount(TdObject chat) {
    final type = chat['type'] as TdObject;
    return switch (type['@type']) {
      'chatTypeBasicGroup' =>
        basicGroups[type['basic_group_id']]?['member_count'] as int?,
      'chatTypeSupergroup' =>
        supergroups[type['supergroup_id']]?['member_count'] as int?,
      _ => null,
    };
  }

  /// For supergroups, only the first 200 members.
  Future<List<int>> groupMemberIds(TdObject chat) async {
    final type = chat['type'] as TdObject;
    final List members;
    if (type['@type'] == 'chatTypeBasicGroup') {
      final info = await client.send({
        '@type': 'getBasicGroupFullInfo',
        'basic_group_id': type['basic_group_id'],
      });
      members = info['members'] as List;
    } else {
      final res = await client.send({
        '@type': 'getSupergroupMembers',
        'supergroup_id': type['supergroup_id'],
        'filter': {'@type': 'supergroupMembersFilterRecent'},
        'offset': 0,
        'limit': 200,
      });
      members = res['members'] as List;
    }
    return [
      for (final m in members.cast<TdObject>())
        if ((m['member_id'] as TdObject)['@type'] == 'messageSenderUser')
          (m['member_id'] as TdObject)['user_id'] as int,
    ];
  }

  String userName(int userId) {
    final u = users[userId];
    if (u == null) return '';
    return '${u['first_name']} ${u['last_name']}'.trim();
  }

  String senderName(TdObject message) {
    final sender = message['sender_id'] as TdObject;
    return sender['@type'] == 'messageSenderUser'
        ? userName(sender['user_id'] as int)
        : (chats[sender['chat_id']]?['title'] as String? ?? '');
  }

  // ------------------------------------------------------------------- files

  TdObject current(TdObject file) => files[file['id'] as int] ?? file;

  /// Returns the local path if the file is fully downloaded.
  String? downloadedPath(TdObject? file) {
    if (file == null) return null;
    final local = current(file)['local'] as TdObject;
    return local['is_downloading_completed'] == true
        ? local['path'] as String
        : null;
  }

  /// Download progress from 0 to 1.
  double downloadProgress(TdObject file) {
    final f = current(file);
    final total = (f['size'] as int? ?? 0) > 0
        ? f['size'] as int
        : f['expected_size'] as int? ?? 0;
    final done = (f['local'] as TdObject)['downloaded_size'] as int? ?? 0;
    return total == 0 ? 0 : (done / total).clamp(0, 1);
  }

  bool isDownloading(TdObject file) =>
      (current(file)['local'] as TdObject)['is_downloading_active'] == true;

  /// Requests are deduplicated; a failed download can be requested again.
  void download(TdObject file, {int priority = 1}) {
    final id = file['id'] as int;
    if (downloadedPath(file) != null || !_requestedFiles.add(id)) return;
    client
        .send({
          '@type': 'downloadFile',
          'file_id': id,
          'priority': priority,
          'offset': 0,
          'limit': 0,
          'synchronous': false,
        })
        .then((f) {
          if (f['@type'] == 'file') files[id] = f;
        }, onError: (Object _) => _requestedFiles.remove(id));
  }

  void cancelDownload(TdObject file) {
    final id = file['id'] as int;
    if (!_requestedFiles.remove(id) || downloadedPath(file) != null) return;
    client
        .send({
          '@type': 'cancelDownloadFile',
          'file_id': id,
          'only_if_pending': false,
        })
        .catchError((_) => <String, dynamic>{});
  }

  /// Returns the local path, or starts the download and returns null.
  String? localPath(TdObject? file) {
    if (file == null) return null;
    final path = downloadedPath(file);
    if (path == null) download(file);
    return path;
  }

  // ---------------------------------------------------------------- messages

  Future<TdObject> sendText(
    int chatId,
    String text, {
    int? replyToMessageId,
    bool disableLinkPreview = false,
  }) => client.send({
    '@type': 'sendMessage',
    'chat_id': chatId,
    'reply_to': replyToMessageId == null
        ? null
        : {
            '@type': 'inputMessageReplyToMessage',
            'message_id': replyToMessageId,
          },
    'input_message_content': {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': text, 'entities': []},
      'link_preview_options': {
        '@type': 'linkPreviewOptions',
        'is_disabled': disableLinkPreview,
      },
      'clear_draft': true,
    },
  });

  /// Several photos are sent as an album with the caption on the first one.
  Future<void> sendPhotos(
    int chatId,
    List<({String path, int width, int height})> photos,
    String caption,
  ) {
    TdObject content(int i) => {
      '@type': 'inputMessagePhoto',
      'photo': {
        '@type': 'inputPhoto',
        'photo': {'@type': 'inputFileLocal', 'path': photos[i].path},
        'width': photos[i].width,
        'height': photos[i].height,
      },
      'caption': {
        '@type': 'formattedText',
        'text': i == 0 ? caption : '',
        'entities': [],
      },
    };
    if (photos.length == 1) {
      return client.send({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': content(0),
      });
    }
    return client.send({
      '@type': 'sendMessageAlbum',
      'chat_id': chatId,
      'input_message_contents': [
        for (var i = 0; i < photos.length; i++) content(i),
      ],
    });
  }

  @override
  void dispose() {
    _messageUpdates.close();
    client.dispose();
    super.dispose();
  }
}
