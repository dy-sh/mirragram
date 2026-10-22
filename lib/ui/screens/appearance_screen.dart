import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../l10n/l10n.dart';
import '../../tdlib/td_client.dart';
import '../layout/nav.dart';
import '../tg_theme.dart';
import '../theme/appearance.dart';
import '../theme/wallpaper.dart';
import '../widgets/message_bubble.dart';
import '../widgets/tg_list.dart';
import 'wallpaper_screen.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = AppScope.of(context).appearance;
    final c = TgColors.of(context);
    final platform = MediaQuery.platformBrightnessOf(context);
    final desktop = TgNav.maybeOf(context)?.isDesktop ?? false;

    return CupertinoPageScaffold(
      backgroundColor: c.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.appearance),
        previousPageTitle: desktop ? null : context.l10n.tabSettings,
        backgroundColor: c.navBar,
        border: Border(bottom: BorderSide(color: c.separator, width: 0.33)),
      ),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: appearance,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  TgSection(
                    header: context.l10n.colorTheme,
                    children: [
                      const SizedBox(height: 190, child: ThemePreview()),
                      _ThemeTiles(appearance: appearance, platform: platform),
                    ],
                  ),
                  TgSection(
                    children: [
                      TgCell(
                        title: context.l10n.chatWallpaper,
                        chevron: true,
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute<void>(
                            builder: (_) => WallpaperScreen(dark: c.isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  TgSection(
                    header: context.l10n.nightMode,
                    footer: appearance.autoNight
                        ? context.l10n.autoNightFooter
                        : null,
                    children: [
                      TgCell(
                        title: context.l10n.nightMode,
                        trailing: TgSwitch(
                          value: appearance.isDark(platform),
                          onChanged: appearance.setNightMode,
                        ),
                      ),
                      TgCell(
                        title: context.l10n.autoNight,
                        value: appearance.autoNight
                            ? context.l10n.autoNightSystem
                            : context.l10n.autoNightOff,
                        chevron: true,
                        onTap: () => _pickAutoNight(context, platform),
                      ),
                    ],
                  ),
                  TgSection(
                    header: context.l10n.textSize,
                    children: [_TextSizeSlider(appearance: appearance)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAutoNight(BuildContext context, Brightness platform) {
    final appearance = AppScope.of(context).appearance;
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(context.l10n.autoNightTitle),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              appearance.setAutoNight(true, platform);
              Navigator.pop(context);
            },
            child: Text(context.l10n.autoNightFollowSystem),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              appearance.setAutoNight(false, platform);
              Navigator.pop(context);
            },
            child: Text(context.l10n.autoNightOff),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
      ),
    );
  }
}

/// Sample conversation over a wallpaper.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, this.wallpaper});

  /// Defaults to the current wallpaper.
  final WallpaperSpec? wallpaper;

  static TdObject _message(
    String text, {
    required bool out,
    int minute = 0,
  }) => {
    '@type': 'message',
    'id': out ? 2 : 1,
    'is_outgoing': out,
    'date':
        DateTime(2026, 1, 1, 21, 20 + minute).millisecondsSinceEpoch ~/ 1000,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': 0},
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': text},
    },
  };

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth * 0.75;
        Widget bubble(TdObject m, {required bool tail}) => Align(
          alignment: m['is_outgoing'] == true
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: MessageBubble(
              message: m,
              e2e: null,
              read: true,
              tail: tail,
              maxWidth: maxWidth,
            ),
          ),
        );
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (wallpaper != null)
                WallpaperView(wallpaper!)
              else
                ChatWallpaper(colors: c),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  bubble(_message(l.previewIncoming1, out: false), tail: false),
                  bubble(_message(l.previewIncoming2, out: false), tail: true),
                  const SizedBox(height: 6),
                  bubble(
                    _message(l.previewOutgoing, out: true, minute: 2),
                    tail: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeTiles extends StatelessWidget {
  const _ThemeTiles({required this.appearance, required this.platform});

  final AppearanceController appearance;
  final Brightness platform;

  @override
  Widget build(BuildContext context) {
    final current = TgColors.of(context);
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          for (final variant in TgThemeVariant.values)
            _ThemeTile(
              variant: variant,
              selected: current.variant == variant,
              onTap: () => appearance.selectVariant(variant, platform),
            ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final TgThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = TgColors.of(context);
    final colors = variant.colors;
    Widget pill(Color color, List<Color>? gradient, Alignment align) => Align(
      alignment: align,
      child: Container(
        width: 46,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          gradient: gradient != null && gradient.length > 1
              ? LinearGradient(colors: gradient)
              : null,
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 92,
              height: 74,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: selected ? current.accent : current.separator,
                  width: selected ? 2 : 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WallpaperView(colors.defaultWallpaper, thumbnail: true),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        pill(colors.bubbleIn, null, Alignment.centerLeft),
                        const SizedBox(height: 7),
                        pill(
                          colors.bubbleOut.first,
                          colors.bubbleOut,
                          Alignment.centerRight,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              themeName(context.l10n, variant),
              style: TextStyle(
                fontSize: 13,
                color: selected ? current.accent : current.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextSizeSlider extends StatelessWidget {
  const _TextSizeSlider({required this.appearance});

  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    const sizes = AppearanceController.textSizes;
    final index = sizes.indexOf(appearance.textSize).clamp(0, sizes.length - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text('A', style: TextStyle(fontSize: 13, color: c.primaryText)),
          Expanded(
            child: CupertinoSlider(
              value: index.toDouble(),
              min: 0,
              max: sizes.length - 1.0,
              divisions: sizes.length - 1,
              activeColor: c.accent,
              onChanged: (v) => appearance.setTextSize(sizes[v.round()]),
            ),
          ),
          Text('A', style: TextStyle(fontSize: 22, color: c.primaryText)),
        ],
      ),
    );
  }
}

String themeName(AppLocalizations l, TgThemeVariant variant) =>
    switch (variant) {
      TgThemeVariant.dayClassic => l.themeDayClassic,
      TgThemeVariant.day => l.themeDay,
      TgThemeVariant.night => l.themeNight,
      TgThemeVariant.nightTinted => l.themeNightTinted,
    };
