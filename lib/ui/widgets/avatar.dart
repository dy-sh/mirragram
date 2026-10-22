import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../tdlib/td_client.dart';
import '../tg_theme.dart';

class Avatar extends StatelessWidget {
  const Avatar.chat(this.chat, {super.key, this.size = Tg.chatListAvatar})
    : userId = null;

  const Avatar.user(this.userId, {super.key, this.size = Tg.chatListAvatar})
    : chat = null;

  final TdObject? chat;
  final int? userId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final user = userId != null ? tg.users[userId] : null;

    if (chat != null && tg.isSavedMessages(chat!)) {
      return _circle(
        Tg.avatarGradients[5],
        Icon(
          CupertinoIcons.bookmark_fill,
          color: const Color(0xFFFFFFFF),
          size: size * 0.45,
        ),
      );
    }

    final photoInfo = chat != null
        ? chat!['photo'] as TdObject?
        : user?['profile_photo'] as TdObject?;
    final photo = photoInfo?['small'] as TdObject?;
    final path = tg.localPath(photo);
    if (path != null) {
      return ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final accent = chat != null
        ? chat!['accent_color_id'] as int?
        : user?['accent_color_id'] as int?;
    final colorIndex = accent != null && accent >= 0 && accent < 7
        ? accent
        : Tg.colorIndex(chat != null ? _peerId(chat!) : (userId ?? 0));
    final name = chat != null
        ? chat!['title'] as String
        : '${user?['first_name'] ?? ''} ${user?['last_name'] ?? ''}';
    return _circle(
      Tg.avatarGradients[colorIndex],
      Text(
        initials(name),
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _circle(List<Color> gradient, Widget child) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gradient,
      ),
    ),
    child: child,
  );

  /// Without accent_color_id, Telegram picks the color by user or group id,
  /// not by chat id.
  static int _peerId(TdObject chat) {
    final type = chat['type'] as TdObject;
    return switch (type['@type']) {
      'chatTypePrivate' || 'chatTypeSecret' => type['user_id'] as int,
      'chatTypeBasicGroup' => type['basic_group_id'] as int,
      'chatTypeSupergroup' => type['supergroup_id'] as int,
      _ => chat['id'] as int,
    };
  }
}

String initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  String first(String w) => String.fromCharCodes(w.runes.take(1)).toUpperCase();
  return words.length == 1
      ? first(words[0])
      : first(words[0]) + first(words[1]);
}
