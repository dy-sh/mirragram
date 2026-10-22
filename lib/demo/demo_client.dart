import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:path/path.dart' as p;

import '../tdlib/td_client.dart';

/// Fake TDLib for working on the UI without an account:
///   flutter run -d macos --dart-define=TG_DEMO=true
///
class DemoTdClient implements TdClient {
  DemoTdClient._(this._dir);

  final Directory _dir;
  final _updates = StreamController<TdObject>.broadcast();
  final _messages = <int, List<TdObject>>{};
  final _backgrounds = <bool, TdObject?>{};
  var _nextMessageId = 1000;
  late final TdObject _patternFile;

  static const _me = 1;
  static const _names = {3: 'Sergey Kravtsov', 4: 'Kate Coral'};
  static final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static Future<TdClient> create(Directory dir) async {
    final client = DemoTdClient._(dir);
    await client._writePattern();
    await client._writePhotos();
    scheduleMicrotask(client._start);
    return client;
  }

  @override
  Stream<TdObject> get updates => _updates.stream;

  @override
  Future<TdObject> send(TdObject request) async {
    await Future<void>.delayed(Duration.zero);
    return _json(_handle(request));
  }

  /// Round-trips through JSON to get `Map<String, dynamic>` like real TDLib.
  static TdObject _json(TdObject obj) =>
      jsonDecode(jsonEncode(obj)) as TdObject;

  TdObject _handle(TdObject request) {
    switch (request['@type']) {
      case 'getMe':
        return _user(_me, 'Alex', '', phone: '15555550123');
      case 'loadChats':
        throw TdError(404, 'Not Found');
      case 'getChatHistory':
        final all = _messages[request['chat_id']] ?? [];
        final from = request['from_message_id'] as int;
        final page = all.reversed
            .where((m) => from == 0 || (m['id'] as int) < from)
            .take(request['limit'] as int)
            .toList();
        return {'@type': 'messages', 'messages': page};
      case 'getContacts':
        return {
          '@type': 'users',
          'user_ids': [2, 3, 4, 5],
        };
      case 'sendMessage':
        return _send(
          request['chat_id'] as int,
          request['input_message_content'] as TdObject,
        );
      case 'sendMessageAlbum':
        final chatId = request['chat_id'] as int;
        return {
          '@type': 'messages',
          'messages': [
            for (final c in request['input_message_contents'] as List)
              _send(chatId, c as TdObject),
          ],
        };
      case 'getInstalledBackgrounds':
        return {
          '@type': 'backgrounds',
          'backgrounds': request['for_dark_theme'] == true
              ? _darkBackgrounds()
              : _lightBackgrounds(),
        };
      case 'searchBackground':
        return _patternBackground(1, [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884]);
      case 'setDefaultBackground':
        final dark = request['for_dark_theme'] == true;
        final input = request['background'] as TdObject?;
        final id = input?['background_id'];
        final all = [..._lightBackgrounds(), ..._darkBackgrounds()];
        final bg = <String, dynamic>{
          ...(all.where((b) => b['id'] == id).firstOrNull ??
              {'@type': 'background', 'id': '0', 'name': ''}),
          'type': request['type'],
        };
        _backgrounds[dark] = bg;
        _emit({
          '@type': 'updateDefaultBackground',
          'for_dark_theme': dark,
          'background': bg,
        });
        return bg;
      case 'deleteDefaultBackground':
        final dark = request['for_dark_theme'] == true;
        _backgrounds[dark] = null;
        _emit({'@type': 'updateDefaultBackground', 'for_dark_theme': dark});
        return {'@type': 'ok'};
      case 'createPrivateChat':
        final userId = request['user_id'] as int;
        if (!_messages.containsKey(userId)) {
          _messages[userId] = [];
          _emit({
            '@type': 'updateNewChat',
            'chat': {
              '@type': 'chat',
              'id': userId,
              'title': _names[userId] ?? '',
              'type': {'@type': 'chatTypePrivate', 'user_id': userId},
              'positions': <Object>[],
            },
          });
        }
        return {'@type': 'chat', 'id': userId};
      case 'downloadFile':
        throw TdError(400, 'Demo: no files');
      default:
        return {'@type': 'ok'};
    }
  }

  @override
  void dispose() => _updates.close();

  void _emit(TdObject u) {
    if (!_updates.isClosed) _updates.add(_json(u));
  }

  // -------------------------------------------------------------------- data

  void _start() {
    _emit({
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateReady'},
    });
    final users = [
      _user(_me, 'Alex', '', phone: '15555550123'),
      _user(2, 'Anna', 'Smith', online: true),
      _user(3, 'Sergey', 'Kravtsov'),
      _user(4, 'Kate', 'Coral'),
      _user(5, 'Daniel', 'Brooks'),
      _user(777000, 'Telegram', ''),
    ];
    for (final u in users) {
      _emit({'@type': 'updateUser', 'user': u});
    }
    _emit({
      '@type': 'updateSupergroup',
      'supergroup': {'@type': 'supergroup', 'id': 50, 'member_count': 1532},
    });
    _emit({
      '@type': 'updateBasicGroup',
      'basic_group': {'@type': 'basicGroup', 'id': 60, 'member_count': 4},
    });

    var order = 9000;
    void chat(
      int id,
      String title,
      TdObject type,
      List<(int sender, String text, int ago)> history, {
      bool pinned = false,
      int unread = 0,
      bool muted = false,
    }) {
      final msgs = [
        for (final (sender, text, ago) in history)
          _message(id, sender, text, _now - ago, out: sender == _me),
      ];
      _messages[id] = msgs;
      _emit({
        '@type': 'updateNewChat',
        'chat': {
          '@type': 'chat',
          'id': id,
          'title': title,
          'type': type,
          'unread_count': unread,
          'last_read_outbox_message_id': msgs.isEmpty
              ? 0
              : msgs.last['id'] as int,
          'notification_settings': {'mute_for': muted ? 1 << 30 : 0},
          'positions': <Object>[],
        },
      });
      _emit({
        '@type': 'updateChatLastMessage',
        'chat_id': id,
        'last_message': msgs.isEmpty ? null : msgs.last,
        'positions': [
          {
            '@type': 'chatPosition',
            'list': {'@type': 'chatListMain'},
            'order': '${order--}',
            'is_pinned': pinned,
          },
        ],
      });
    }

    TdObject private(int userId) => {
      '@type': 'chatTypePrivate',
      'user_id': userId,
    };

    chat(_me, 'Alex', private(_me), [
      (
        _me,
        'To do this week:\n- renew the visa\n- open a bank account',
        86400 * 3,
      ),
      (_me, 'hi 2', 3600),
    ], pinned: true);
    chat(
      -100050,
      'Game_DW',
      {'@type': 'chatTypeSupergroup', 'supergroup_id': 50, 'is_channel': false},
      [
        (3, 'Has anyone tried the new build?', 86400 * 2),
        (4, 'Yes, it runs smoothly on my laptop', 86400 * 2 - 60),
        (4, 'But it stutters on the phone', 86400 * 2 - 50),
        if (_hasVideos) ...[
          (3, '[video] Gameplay from the new build', 86400 * 2 - 40),
          (4, '[gif]', 86400 * 2 - 30),
          (4, '[note]', 86400 * 2 - 20),
        ],
        (_me, 'FPS drops by about 15-20%, but it’s too early to say', 86400),
      ],
      pinned: true,
    );
    chat(2, 'Anna Smith', private(2), [
      (2, 'Hi! Will you be at the meeting tomorrow?', 7200),
      (_me, "Yes, I'll be there by ten", 7100),
      (2, 'Great 👍', 7000),
      (2, '[photo 0] The view from the office today', 3000),
      (2, '[photo 1]', 2900),
      (_me, '[photo 0]', 2000),
      (2, 'Please bring the project documents', 600),
    ], unread: 2);
    chat(777000, 'Telegram', private(777000), [
      (
        777000,
        'New login. We detected a login into your account from a new '
            'device.',
        5000,
      ),
    ]);
    chat(
      -100060,
      'LiXiang Belarus',
      {'@type': 'chatTypeBasicGroup', 'basic_group_id': 60},
      [(3, 'It has always been there, nobody noticed?', 9000)],
      unread: 49000,
      muted: true,
    );
    chat(5, 'Daniel Brooks', private(5), [
      (5, 'Hi Alex, how are you? Any new thoughts on the project?', 20000),
      (_me, "Hi! Yes, I'll tell you tonight", 19000),
    ]);
  }

  TdObject _user(
    int id,
    String first,
    String last, {
    String phone = '',
    bool online = false,
  }) => {
    '@type': 'user',
    'id': id,
    'first_name': first,
    'last_name': last,
    'phone_number': phone,
    'usernames': {
      'active_usernames': id == _me ? ['demo_user'] : <String>[],
    },
    'status': online
        ? {'@type': 'userStatusOnline', 'expires': _now + 300}
        : {'@type': 'userStatusOffline', 'was_online': _now - 1800},
  };

  TdObject _send(int chatId, TdObject input) {
    final m = switch (input['@type']) {
      'inputMessagePhoto' => _photoMessage(
        chatId,
        _me,
        _localFile(
          ((input['photo'] as TdObject)['photo'] as TdObject)['path'] as String,
        ),
        (input['photo'] as TdObject)['width'] as int,
        (input['photo'] as TdObject)['height'] as int,
        (input['caption'] as TdObject)['text'] as String,
        _now + 1,
      ),
      _ => _message(
        chatId,
        _me,
        (input['text'] as TdObject)['text'] as String,
        _now + 1,
        out: true,
      ),
    };
    _messages.putIfAbsent(chatId, () => []).add(m);
    _emit({'@type': 'updateNewMessage', 'message': m});
    _emit({
      '@type': 'updateChatLastMessage',
      'chat_id': chatId,
      'last_message': m,
      'positions': <Object>[],
    });
    return m;
  }

  /// `[photo N] caption` in demo history becomes a photo message.
  TdObject _message(
    int chatId,
    int sender,
    String text,
    int date, {
    required bool out,
  }) {
    final photo = RegExp(
      r'^\[photo (\d)\] ?(.*)$',
      dotAll: true,
    ).firstMatch(text);
    if (photo != null) {
      final (file, w, h) = _photos[int.parse(photo.group(1)!)];
      return _photoMessage(chatId, sender, file, w, h, photo.group(2)!, date);
    }
    final video = RegExp(
      r'^\[(video|gif|note)\] ?(.*)$',
      dotAll: true,
    ).firstMatch(text);
    if (video != null) {
      return _videoMessage(
        chatId,
        sender,
        video.group(1)!,
        video.group(2)!,
        date,
      );
    }
    return {
      '@type': 'message',
      'id': _nextMessageId++,
      'chat_id': chatId,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': sender},
      'is_outgoing': out,
      'date': date,
      'edit_date': 0,
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': text,
          'entities': <Object>[],
        },
      },
    };
  }

  TdObject _photoMessage(
    int chatId,
    int sender,
    TdObject file,
    int width,
    int height,
    String caption,
    int date,
  ) => {
    '@type': 'message',
    'id': _nextMessageId++,
    'chat_id': chatId,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': sender},
    'is_outgoing': sender == _me,
    'date': date,
    'edit_date': 0,
    'content': {
      '@type': 'messagePhoto',
      'photo': {
        '@type': 'photo',
        'sizes': [
          {
            '@type': 'photoSize',
            'type': 'y',
            'photo': file,
            'width': width,
            'height': height,
          },
        ],
      },
      'caption': {'@type': 'formattedText', 'text': caption},
    },
  };

  /// The app doesn't generate videos; demo shows them only if
  /// `demo_video.mp4`, `demo_gif.mp4` and `demo_note.mp4` exist in the demo
  /// data directory.
  bool get _hasVideos => [
    'video',
    'gif',
    'note',
  ].every((k) => File(p.join(_dir.path, 'demo_$k.mp4')).existsSync());

  TdObject _videoMessage(
    int chatId,
    int sender,
    String kind,
    String caption,
    int date,
  ) {
    final file = _localFile(p.join(_dir.path, 'demo_$kind.mp4'));
    final (cover, w, h) = _photos[kind == 'note' ? 1 : 0];
    final thumbnail = {
      '@type': 'thumbnail',
      'format': {'@type': 'thumbnailFormatPng'},
      'width': w,
      'height': h,
      'file': cover,
    };
    final content = switch (kind) {
      'note' => {
        '@type': 'messageVideoNote',
        'video_note': {
          '@type': 'videoNote',
          'duration': 5,
          'length': 384,
          'thumbnail': thumbnail,
          'video': file,
        },
      },
      'gif' => {
        '@type': 'messageAnimation',
        'animation': {
          '@type': 'animation',
          'duration': 3,
          'width': 480,
          'height': 360,
          'thumbnail': thumbnail,
          'animation': file,
        },
        'caption': {'@type': 'formattedText', 'text': caption},
      },
      _ => {
        '@type': 'messageVideo',
        'video': {
          '@type': 'video',
          'duration': 8,
          'width': 1280,
          'height': 720,
          'thumbnail': thumbnail,
          'video': file,
        },
        'caption': {'@type': 'formattedText', 'text': caption},
      },
    };
    return {
      '@type': 'message',
      'id': _nextMessageId++,
      'chat_id': chatId,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': sender},
      'is_outgoing': sender == _me,
      'date': date,
      'edit_date': 0,
      'content': content,
    };
  }

  var _nextFileId = 900100;

  TdObject _localFile(String path) => {
    '@type': 'file',
    'id': _nextFileId++,
    'local': {
      '@type': 'localFile',
      'path': path,
      'is_downloading_completed': true,
    },
  };

  final _photos = <(TdObject, int, int)>[];

  /// Generated landscape and portrait pictures for demo photo messages.
  Future<void> _writePhotos() async {
    for (final (i, w, h, colors) in [
      (0, 1280, 960, const [Color(0xFF2E86DE), Color(0xFF48DBFB)]),
      (1, 900, 1200, const [Color(0xFFEE5253), Color(0xFFFECA57)]),
    ]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ).createShader(rect),
      );
      final rnd = Random(i);
      for (var k = 0; k < 18; k++) {
        canvas.drawCircle(
          Offset(rnd.nextDouble() * w, rnd.nextDouble() * h),
          30 + rnd.nextDouble() * 140,
          Paint()..color = const Color(0x33FFFFFF),
        );
      }
      final image = await recorder.endRecording().toImage(w, h);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = p.join(_dir.path, 'demo_photo_$i.png');
      await File(path).writeAsBytes(png!.buffer.asUint8List());
      _photos.add((_localFile(path), w, h));
    }
  }

  // ------------------------------------------------------------- backgrounds

  List<TdObject> _lightBackgrounds() => [
    _patternBackground(1, [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884]),
    _patternBackground(2, [0x8DC0EB, 0xB9D1EA, 0xC6B1EF, 0xEBD7EF]),
    _patternBackground(3, [0xFEC496, 0xDD6CB9, 0x962FBF, 0x4F5BD5]),
    _fillBackground(4, {
      '@type': 'backgroundFillFreeformGradient',
      'colors': [0xE4B2EA, 0x8376C2, 0xEAB9D9, 0xB493E6],
    }),
    _fillBackground(5, {'@type': 'backgroundFillSolid', 'color': 0xC7E3C2}),
    _fillBackground(6, {
      '@type': 'backgroundFillGradient',
      'top_color': 0xB2CEE1,
      'bottom_color': 0xF1E4B5,
      'rotation_angle': 45,
    }),
  ];

  List<TdObject> _darkBackgrounds() => [
    _patternBackground(11, [
      0x6A5BD8,
      0x3F6FDD,
      0x8B5ACF,
      0x3A86D6,
    ], inverted: true),
    _patternBackground(12, [
      0x2E8B57,
      0x3CB371,
      0x1F6F8B,
      0x4A9C6D,
    ], inverted: true),
    _fillBackground(13, {'@type': 'backgroundFillSolid', 'color': 0x0E1621}),
    _fillBackground(14, {'@type': 'backgroundFillSolid', 'color': 0x1C1C1D}),
  ];

  TdObject _patternBackground(
    int id,
    List<int> colors, {
    bool inverted = false,
  }) => {
    '@type': 'background',
    'id': '$id',
    'name': 'demo$id',
    'document': {'@type': 'document', 'document': _patternFile},
    'type': {
      '@type': 'backgroundTypePattern',
      'fill': {'@type': 'backgroundFillFreeformGradient', 'colors': colors},
      'intensity': 50,
      'is_inverted': inverted,
      'is_moving': false,
    },
  };

  TdObject _fillBackground(int id, TdObject fill) => {
    '@type': 'background',
    'id': '$id',
    'name': 'demo$id',
    'type': {'@type': 'backgroundTypeFill', 'fill': fill},
  };

  /// A simple pattern in Telegram's .tgv format (gzipped SVG).
  Future<void> _writePattern() async {
    final rnd = Random(7);
    final shapes = StringBuffer();
    for (var i = 0; i < 260; i++) {
      final x = rnd.nextDouble() * 1440, y = rnd.nextDouble() * 2960;
      final r = 18 + rnd.nextDouble() * 34;
      switch (i % 4) {
        case 0:
          shapes.write(
            '<circle cx="$x" cy="$y" r="$r" fill="none" stroke="#000" '
            'stroke-width="7"/>',
          );
        case 1:
          shapes.write(
            '<path d="M${x - r} $y L$x ${y - r} L${x + r} $y L$x ${y + r}Z" '
            'fill="none" stroke="#000" stroke-width="7" '
            'stroke-linejoin="round"/>',
          );
        case 2:
          shapes.write(
            '<path d="M${x - r} ${y + r / 2} Q$x ${y - r} ${x + r} '
            '${y + r / 2}" fill="none" stroke="#000" stroke-width="7" '
            'stroke-linecap="round"/>',
          );
        default:
          shapes.write('<circle cx="$x" cy="$y" r="${r / 3}" fill="#000"/>');
      }
    }
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="2960" '
        'viewBox="0 0 1440 2960">$shapes</svg>';
    final path = p.join(_dir.path, 'demo_pattern.tgv');
    await File(path).writeAsBytes(gzip.encode(utf8.encode(svg)));
    _patternFile = {
      '@type': 'file',
      'id': 900001,
      'local': {
        '@type': 'localFile',
        'path': path,
        'is_downloading_completed': true,
      },
    };
  }
}
