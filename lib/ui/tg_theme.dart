import 'package:flutter/cupertino.dart';

export 'theme/palette.dart';

/// Theme-independent sizes and colors. Theme colors live in [TgColors].
abstract final class Tg {
  /// Same order as Telegram's accent colors 0–6.
  static const avatarGradients = [
    [Color(0xFFFF885E), Color(0xFFFF516A)],
    [Color(0xFFFFCD6A), Color(0xFFFFA85C)],
    [Color(0xFF82B1FF), Color(0xFF665FFF)],
    [Color(0xFFA0DE7E), Color(0xFF54CB68)],
    [Color(0xFF53EDD6), Color(0xFF28C9B7)],
    [Color(0xFF72D5FD), Color(0xFF2A9EF1)],
    [Color(0xFFE0A2F3), Color(0xFFD669ED)],
  ];

  static const nameColors = [
    Color(0xFFFC5C51),
    Color(0xFFFA790F),
    Color(0xFF895DD5),
    Color(0xFF0FB297),
    Color(0xFF00C1A6),
    Color(0xFF3CA5EC),
    Color(0xFFD95574),
  ];
  static const nameColorsDark = [
    Color(0xFFFF8E86),
    Color(0xFFFFA357),
    Color(0xFFB18FFF),
    Color(0xFF4DD6BF),
    Color(0xFF45E8D1),
    Color(0xFF7AC9FF),
    Color(0xFFFF7FD5),
  ];

  static int colorIndex(int id) => id.abs() % 7;

  static const chatListAvatar = 60.0;

  /// From this width on, the layout switches to Telegram Desktop style.
  static const desktopBreakpoint = 700.0;
  static const sidebarWidth = 320.0;
}

/// Text styles without colors; colors come from the theme.
abstract final class TgText {
  static const title = TextStyle(
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const preview = TextStyle(
    fontSize: 15,
    letterSpacing: -0.2,
    height: 1.25,
  );
  static const date = TextStyle(fontSize: 14);
  static const message = TextStyle(letterSpacing: -0.4, height: 1.25);
  static const navTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );
  static const navSubtitle = TextStyle(fontSize: 13);
}
