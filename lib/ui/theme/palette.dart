import 'package:flutter/cupertino.dart';

import 'wallpaper.dart';

/// Day and night themes are chosen separately; night mode switches between
/// them.
enum TgThemeVariant {
  dayClassic,
  day,
  night,
  nightTinted;

  bool get isDark => this == night || this == nightTinted;

  TgColors get colors => switch (this) {
    dayClassic => TgColors.dayClassic,
    day => TgColors.day,
    night => TgColors.night,
    nightTinted => TgColors.nightTinted,
  };
}

@immutable
class TgColors {
  const TgColors({
    required this.variant,
    required this.accent,
    required this.background,
    required this.groupedBackground,
    required this.cell,
    required this.pinned,
    required this.separator,
    required this.primaryText,
    required this.secondaryText,
    required this.mutedBadge,
    required this.searchField,
    required this.navBar,
    required this.tabInactive,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.bubbleInText,
    required this.bubbleOutText,
    required this.bubbleInMeta,
    required this.bubbleOutMeta,
    required this.bubbleOutLink,
    required this.bubbleShadow,
    required this.serviceBubble,
    required this.serviceText,
    required this.inputField,
    required this.inputFieldBorder,
    required this.panelIcon,
    required this.secure,
    required this.defaultWallpaper,
  });

  final TgThemeVariant variant;
  final Color accent;

  /// Lists (chats, contacts).
  final Color background;

  /// Grouped screens (settings).
  final Color groupedBackground;

  /// Grouped cells and the desktop sidebar.
  final Color cell;
  final Color pinned;
  final Color separator;
  final Color primaryText;
  final Color secondaryText;
  final Color mutedBadge;
  final Color searchField;

  final Color navBar;
  final Color tabInactive;

  final Color bubbleIn;
  final List<Color> bubbleOut;
  final Color bubbleInText;
  final Color bubbleOutText;
  final Color bubbleInMeta;
  final Color bubbleOutMeta;
  final Color bubbleOutLink;
  final Color? bubbleShadow;

  final Color serviceBubble;
  final Color serviceText;
  final Color inputField;
  final Color inputFieldBorder;
  final Color panelIcon;

  /// Encrypted chats are green, like Telegram's secret chats.
  final Color secure;
  final WallpaperSpec defaultWallpaper;

  bool get isDark => variant.isDark;
  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;
  Color get destructive =>
      isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
  Color get placeholder => secondaryText.withValues(alpha: 0.75);

  Color get selected => accent;

  static TgColors of(BuildContext context) =>
      _TgColorsScope.maybeOf(context) ?? dayClassic;

  static const dayClassic = TgColors(
    variant: TgThemeVariant.dayClassic,
    accent: Color(0xFF0088FF),
    background: Color(0xFFFFFFFF),
    groupedBackground: Color(0xFFEFEFF4),
    cell: Color(0xFFFFFFFF),
    pinned: Color(0xFFF7F7F7),
    separator: Color(0xFFC8C7CC),
    primaryText: Color(0xFF000000),
    secondaryText: Color(0xFF8E8E93),
    mutedBadge: Color(0xFFB6B6BB),
    searchField: Color(0xFFE9E9EB),
    navBar: Color(0xF2F7F7F7),
    tabInactive: Color(0xFF959595),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: [Color(0xFFE1FFC7)],
    bubbleInText: Color(0xFF000000),
    bubbleOutText: Color(0xFF000000),
    bubbleInMeta: Color(0xFFA1AAB3),
    bubbleOutMeta: Color(0xFF3FAA3C),
    bubbleOutLink: Color(0xFF0088FF),
    bubbleShadow: Color(0x26000000),
    serviceBubble: Color(0x59748391),
    serviceText: Color(0xFFFFFFFF),
    inputField: Color(0xFFFFFFFF),
    inputFieldBorder: Color(0xFFD9DCE0),
    panelIcon: Color(0xFF858E99),
    secure: Color(0xFF00B12C),
    defaultWallpaper: WallpaperSpec.classic,
  );

  static const day = TgColors(
    variant: TgThemeVariant.day,
    accent: Color(0xFF007AFF),
    background: Color(0xFFFFFFFF),
    groupedBackground: Color(0xFFEFEFF4),
    cell: Color(0xFFFFFFFF),
    pinned: Color(0xFFF7F7F7),
    separator: Color(0xFFC8C7CC),
    primaryText: Color(0xFF000000),
    secondaryText: Color(0xFF8E8E93),
    mutedBadge: Color(0xFFB6B6BB),
    searchField: Color(0xFFE9E9EB),
    navBar: Color(0xF2F7F7F7),
    tabInactive: Color(0xFF959595),
    bubbleIn: Color(0xFFF1F1F4),
    bubbleOut: [Color(0xFF1D93FF), Color(0xFF007AFF)],
    bubbleInText: Color(0xFF000000),
    bubbleOutText: Color(0xFFFFFFFF),
    bubbleInMeta: Color(0xFF8E8E93),
    bubbleOutMeta: Color(0xC7FFFFFF),
    bubbleOutLink: Color(0xFFFFFFFF),
    bubbleShadow: null,
    serviceBubble: Color(0x99748391),
    serviceText: Color(0xFFFFFFFF),
    inputField: Color(0xFFFFFFFF),
    inputFieldBorder: Color(0xFFD9DCE0),
    panelIcon: Color(0xFF858E99),
    secure: Color(0xFF00B12C),
    defaultWallpaper: WallpaperSpec.white,
  );

  static const night = TgColors(
    variant: TgThemeVariant.night,
    accent: Color(0xFF3E88F7),
    background: Color(0xFF000000),
    groupedBackground: Color(0xFF000000),
    cell: Color(0xFF1C1C1D),
    pinned: Color(0xFF1C1C1D),
    separator: Color(0xFF38383B),
    primaryText: Color(0xFFFFFFFF),
    secondaryText: Color(0xFF8D8E93),
    mutedBadge: Color(0xFF5D5D5F),
    searchField: Color(0xFF1C1C1E),
    navBar: Color(0xF01C1C1D),
    tabInactive: Color(0xFF808084),
    bubbleIn: Color(0xFF262628),
    bubbleOut: [Color(0xFF3E88F7), Color(0xFF3172D9)],
    bubbleInText: Color(0xFFFFFFFF),
    bubbleOutText: Color(0xFFFFFFFF),
    bubbleInMeta: Color(0xFF8D8E93),
    bubbleOutMeta: Color(0xB3FFFFFF),
    bubbleOutLink: Color(0xFFFFFFFF),
    bubbleShadow: null,
    serviceBubble: Color(0xB31C1C1D),
    serviceText: Color(0xFFFFFFFF),
    inputField: Color(0xFF060606),
    inputFieldBorder: Color(0xFF353537),
    panelIcon: Color(0xFF8D8E93),
    secure: Color(0xFF30D158),
    defaultWallpaper: WallpaperSpec.nightDefault,
  );

  static const nightTinted = TgColors(
    variant: TgThemeVariant.nightTinted,
    accent: Color(0xFF5EA7EC),
    background: Color(0xFF17212B),
    groupedBackground: Color(0xFF0E1621),
    cell: Color(0xFF17212B),
    pinned: Color(0xFF1C2834),
    separator: Color(0xFF0B1119),
    primaryText: Color(0xFFF5F5F5),
    secondaryText: Color(0xFF708499),
    mutedBadge: Color(0xFF3B4754),
    searchField: Color(0xFF242F3D),
    navBar: Color(0xF017212B),
    tabInactive: Color(0xFF6C7883),
    bubbleIn: Color(0xFF182533),
    bubbleOut: [Color(0xFF2B5278)],
    bubbleInText: Color(0xFFF5F5F5),
    bubbleOutText: Color(0xFFF5F5F5),
    bubbleInMeta: Color(0xFF6D7F8F),
    bubbleOutMeta: Color(0xFF7DA8D3),
    bubbleOutLink: Color(0xFF8CC8FF),
    bubbleShadow: null,
    serviceBubble: Color(0x991E2C3A),
    serviceText: Color(0xFFF5F5F5),
    inputField: Color(0xFF17212B),
    inputFieldBorder: Color(0xFF0E1621),
    panelIcon: Color(0xFF6C7883),
    secure: Color(0xFF4FCE5D),
    defaultWallpaper: WallpaperSpec.nightTintedDefault,
  );

  CupertinoThemeData get cupertino {
    const base = CupertinoTextThemeData();
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: accent,
      primaryContrastingColor: const Color(0xFFFFFFFF),
      scaffoldBackgroundColor: background,
      barBackgroundColor: navBar,
      textTheme: CupertinoTextThemeData(
        primaryColor: accent,
        textStyle: base.textStyle.copyWith(color: primaryText),
        navTitleTextStyle: base.navTitleTextStyle.copyWith(color: primaryText),
        navLargeTitleTextStyle: base.navLargeTitleTextStyle.copyWith(
          color: primaryText,
        ),
        actionTextStyle: base.actionTextStyle.copyWith(color: accent),
        navActionTextStyle: base.navActionTextStyle.copyWith(color: accent),
        tabLabelTextStyle: base.tabLabelTextStyle.copyWith(color: tabInactive),
      ),
    );
  }
}

class TgColorsScope extends StatelessWidget {
  const TgColorsScope({super.key, required this.colors, required this.child});

  final TgColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => _TgColorsScope(
    colors: colors,
    child: CupertinoTheme(data: colors.cupertino, child: child),
  );
}

class _TgColorsScope extends InheritedWidget {
  const _TgColorsScope({required this.colors, required super.child});

  final TgColors colors;

  static TgColors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TgColorsScope>()?.colors;

  @override
  bool updateShouldNotify(_TgColorsScope old) => old.colors != colors;
}
