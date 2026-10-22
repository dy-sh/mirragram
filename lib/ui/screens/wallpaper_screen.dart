import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../tdlib/td_client.dart';
import '../theme/wallpaper.dart';
import '../tg_theme.dart';
import '../widgets/tg_button.dart';
import '../widgets/tg_list.dart';
import 'appearance_screen.dart';
import '../../l10n/l10n.dart';

/// The account's wallpapers plus built-in colors, chosen separately for the
/// day and night themes.
class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key, required this.dark});

  final bool dark;

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> {
  late final Future<List<WallpaperSpec>> _installed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _installed = AppScope.of(context).appearance
        .installedWallpapers(dark: widget.dark)
        .catchError((Object _) => <WallpaperSpec>[]);
  }

  void _preview(WallpaperSpec spec) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => WallpaperPreviewScreen(spec: spec, dark: widget.dark),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.chatWallpaper),
        previousPageTitle: context.l10n.back,
        backgroundColor: c.navBar,
        border: Border(bottom: BorderSide(color: c.separator, width: 0.33)),
      ),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([scope.tg, scope.appearance]),
          builder: (context, _) {
            final current = scope.appearance.wallpaper(
              widget.dark ? _nightColors(scope) : _dayColors(scope),
            );
            return FutureBuilder(
              future: _installed,
              builder: (context, snapshot) {
                final installed = snapshot.data ?? const <WallpaperSpec>[];
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: TgSection(
                        footer: widget.dark
                            ? context.l10n.wallpaperNightFooter
                            : context.l10n.wallpaperDayFooter,
                        children: [
                          TgCell(
                            title: context.l10n.wallpaperReset,
                            titleColor: c.accent,
                            onTap: () => scope.appearance.resetWallpaper(
                              dark: widget.dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (installed.isNotEmpty) ...[
                      _header(c, context.l10n.wallpapers),
                      _grid(installed, current),
                    ] else if (snapshot.connectionState != ConnectionState.done)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CupertinoActivityIndicator(),
                        ),
                      ),
                    _header(c, context.l10n.colors),
                    _grid([
                      for (final fill in WallpaperSpec.builtinFills)
                        WallpaperSpec.fromFill(fill),
                    ], current),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  TgColors _dayColors(AppScope scope) => scope.appearance.dayVariant.colors;
  TgColors _nightColors(AppScope scope) => scope.appearance.nightVariant.colors;

  Widget _header(TgColors c, String title) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(32, 22, 16, 7),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 13, color: c.secondaryText),
      ),
    ),
  );

  Widget _grid(List<WallpaperSpec> specs, WallpaperSpec current) {
    final c = TgColors.of(context);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.62,
        ),
        itemCount: specs.length,
        itemBuilder: (context, i) {
          final spec = specs[i];
          final selected = spec == current;
          return GestureDetector(
            onTap: () => _preview(spec),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WallpaperView(spec, thumbnail: true),
                  if (selected)
                    Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFFFFF),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 16,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class WallpaperPreviewScreen extends StatefulWidget {
  const WallpaperPreviewScreen({
    super.key,
    required this.spec,
    required this.dark,
  });

  final WallpaperSpec spec;
  final bool dark;

  @override
  State<WallpaperPreviewScreen> createState() => _WallpaperPreviewScreenState();
}

class _WallpaperPreviewScreenState extends State<WallpaperPreviewScreen> {
  bool _saving = false;

  Future<void> _apply() async {
    setState(() => _saving = true);
    try {
      await AppScope.of(
        context,
      ).appearance.setWallpaper(widget.spec, dark: widget.dark);
      if (mounted) Navigator.of(context).pop();
    } on TdError catch (e) {
      if (mounted) await showTgAlert(context, context.l10n.error, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.background,
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.preview),
        previousPageTitle: context.l10n.wallpapers,
        backgroundColor: c.navBar,
        border: Border(bottom: BorderSide(color: c.separator, width: 0.33)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: ThemePreview(wallpaper: widget.spec)),
            Container(
              color: c.navBar,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  Expanded(
                    child: TgButton(
                      label: context.l10n.setWallpaper,
                      loading: _saving,
                      onPressed: _apply,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
