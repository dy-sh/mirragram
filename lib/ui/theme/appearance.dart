import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../tdlib/td_client.dart';
import '../../telegram/telegram_service.dart';
import 'palette.dart';
import 'wallpaper.dart';

/// Theme and text size are stored in a local file; wallpapers are stored in
/// TDLib (setDefaultBackground), like in the official apps.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._tg, Directory dataDir)
    : _file = File(p.join(dataDir.path, 'appearance.json')) {
    _read();
    _tg.addListener(_onTelegram);
  }

  final TelegramService _tg;
  final File _file;

  TgThemeVariant dayVariant = TgThemeVariant.dayClassic;
  TgThemeVariant nightVariant = TgThemeVariant.night;

  /// Follow the system dark mode.
  bool autoNight = true;

  /// Used when [autoNight] is off.
  bool nightMode = false;

  double textSize = defaultTextSize;
  static const defaultTextSize = 17.0;
  static const textSizes = [14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0];

  /// Null means the system language.
  String? languageCode;

  Locale? get locale => languageCode == null ? null : Locale(languageCode!);

  bool _patternsRequested = false;

  bool isDark(Brightness platform) =>
      autoNight ? platform == Brightness.dark : nightMode;

  TgColors colors(Brightness platform) =>
      (isDark(platform) ? nightVariant : dayVariant).colors;

  WallpaperSpec wallpaper(TgColors colors) =>
      WallpaperSpec.fromTd(_tg.defaultBackgrounds[colors.isDark]) ??
      colors.defaultWallpaper;

  /// Also resets the wallpaper to the theme's default.
  void selectVariant(TgThemeVariant variant, Brightness platform) {
    if (variant.isDark) {
      nightVariant = variant;
    } else {
      dayVariant = variant;
    }
    if (isDark(platform) != variant.isDark) {
      autoNight = false;
      nightMode = variant.isDark;
    }
    unawaited(resetWallpaper(dark: variant.isDark));
    _changed();
  }

  void setNightMode(bool value) {
    autoNight = false;
    nightMode = value;
    _changed();
  }

  void setAutoNight(bool value, Brightness platform) {
    if (!value) nightMode = platform == Brightness.dark;
    autoNight = value;
    _changed();
  }

  void setLanguage(String? code) {
    languageCode = code;
    _changed();
  }

  void setTextSize(double value) {
    textSize = value;
    _changed();
  }

  Future<void> setWallpaper(WallpaperSpec spec, {required bool dark}) async {
    final type = spec.tdType;
    if (type == null) return resetWallpaper(dark: dark);
    await _tg.client.send({
      '@type': 'setDefaultBackground',
      'background': spec.backgroundId == null
          ? null
          : {
              '@type': 'inputBackgroundRemote',
              'background_id': '${spec.backgroundId}',
            },
      'type': type,
      'for_dark_theme': dark,
    });
  }

  Future<void> resetWallpaper({required bool dark}) async {
    try {
      await _tg.client.send({
        '@type': 'deleteDefaultBackground',
        'for_dark_theme': dark,
      });
    } on TdError {
      // No wallpaper was set.
    }
  }

  Future<List<WallpaperSpec>> installedWallpapers({required bool dark}) async {
    final res = await _tg.client.send({
      '@type': 'getInstalledBackgrounds',
      'for_dark_theme': dark,
    });
    return [
      for (final bg in (res['backgrounds'] as List).cast<TdObject>())
        ?WallpaperSpec.fromTd(bg),
    ];
  }

  // ------------------------------------------------------------------ private

  void _onTelegram() {
    if (_patternsRequested || _tg.authStateType != 'authorizationStateReady') {
      return;
    }
    _patternsRequested = true;
    unawaited(_resolveDefaultPattern());
  }

  /// Falls back to the first pattern among the account's wallpapers.
  Future<void> _resolveDefaultPattern() async {
    const name = WallpaperSpec.defaultPatternName;
    TdObject? file;
    try {
      final bg = await _tg.client.send({
        '@type': 'searchBackground',
        'name': name,
      });
      file = (bg['document'] as TdObject?)?['document'] as TdObject?;
    } on TdError {
      try {
        final list = await installedWallpapers(dark: false);
        file = list
            .where((w) => w.patternFile != null)
            .firstOrNull
            ?.patternFile;
      } on TdError {
        file = null;
      }
    }
    if (file == null) return;
    WallpaperView.registerPattern(name, file);
    notifyListeners();
  }

  void _read() {
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      dayVariant = _variant(json['day']) ?? dayVariant;
      nightVariant = _variant(json['night']) ?? nightVariant;
      autoNight = json['autoNight'] as bool? ?? autoNight;
      nightMode = json['nightMode'] as bool? ?? nightMode;
      textSize = (json['textSize'] as num?)?.toDouble() ?? textSize;
      languageCode = json['language'] as String?;
    } catch (_) {
      // First launch: defaults.
    }
  }

  static TgThemeVariant? _variant(Object? name) =>
      TgThemeVariant.values.where((v) => v.name == name).firstOrNull;

  void _changed() {
    notifyListeners();
    final json = jsonEncode({
      'day': dayVariant.name,
      'night': nightVariant.name,
      'autoNight': autoNight,
      'nightMode': nightMode,
      'textSize': textSize,
      'language': languageCode,
    });
    unawaited(_file.writeAsString(json).then((_) {}, onError: (Object _) {}));
  }

  @override
  void dispose() {
    _tg.removeListener(_onTelegram);
    super.dispose();
  }
}
