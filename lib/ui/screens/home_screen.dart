import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../l10n/l10n.dart';
import '../layout/nav.dart';
import '../tg_theme.dart';
import '../theme/wallpaper.dart';
import '../widgets/message_bubble.dart';
import 'chat_list_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

/// Tabs like Telegram for iPhone on narrow windows, two panes like
/// Telegram Desktop on wide ones.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= Tg.desktopBreakpoint
          ? const _DesktopHome()
          : const _MobileHome(),
    );
  }
}

int unreadChats(BuildContext context) {
  final tg = AppScope.of(context).tg;
  return tg.mainChatList
      .where((c) => (c['unread_count'] as int? ?? 0) > 0 && !tg.isMuted(c))
      .length;
}

enum _Tab {
  contacts(CupertinoIcons.person_crop_circle_fill),
  chats(CupertinoIcons.chat_bubble_2_fill),
  settings(CupertinoIcons.gear_solid);

  const _Tab(this.icon);

  final IconData icon;

  String title(AppLocalizations l) => switch (this) {
    contacts => l.tabContacts,
    chats => l.tabChats,
    settings => l.tabSettings,
  };
}

// ------------------------------------------------------------------- mobile

class _MobileHome extends StatefulWidget {
  const _MobileHome();

  @override
  State<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<_MobileHome> {
  final _controller = CupertinoTabController(initialIndex: 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final c = TgColors.of(context);
    return TgNav(
      isDesktop: false,
      selectedId: null,
      onOpen: pushPage,
      child: CupertinoTabScaffold(
        controller: _controller,
        backgroundColor: c.background,
        tabBar: CupertinoTabBar(
          activeColor: c.accent,
          inactiveColor: c.tabInactive,
          backgroundColor: c.navBar,
          border: Border(top: BorderSide(color: c.separator, width: 0.33)),
          iconSize: 28,
          items: [
            for (final tab in _Tab.values)
              BottomNavigationBarItem(
                icon: tab == _Tab.chats
                    ? ListenableBuilder(
                        listenable: tg,
                        builder: (context, _) => _TabIcon(
                          icon: tab.icon,
                          badge: unreadChats(context),
                        ),
                      )
                    : Icon(tab.icon),
                label: tab.title(context.l10n),
              ),
          ],
        ),
        tabBuilder: (context, index) => CupertinoTabView(
          builder: (context) => switch (_Tab.values[index]) {
            _Tab.contacts => const ContactsScreen(),
            _Tab.chats => const ChatListScreen(),
            _Tab.settings => const SettingsScreen(),
          },
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, required this.badge});

  final IconData icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (badge > 0)
          Positioned(
            right: -10,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.destructive,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ desktop

class _DesktopHome extends StatefulWidget {
  const _DesktopHome();

  @override
  State<_DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<_DesktopHome> {
  _Tab _tab = _Tab.chats;
  String? _selectedId;
  WidgetBuilder? _detail;
  String _query = '';
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _heroController = CupertinoApp.createCupertinoHeroController();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _heroController.dispose();
    super.dispose();
  }

  void _open(BuildContext context, String id, WidgetBuilder builder) {
    setState(() {
      _selectedId = id;
      _detail = builder;
    });
  }

  void _close() => setState(() {
    _selectedId = null;
    _detail = null;
  });

  void _selectTab(_Tab tab) => setState(() {
    if (_tab != tab) {
      _tab = tab;
      _query = '';
      _search.clear();
      if (tab == _Tab.settings) {
        _selectedId = SettingsMenu.defaultId;
        _detail = SettingsMenu.defaultPage;
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final sidebarColor = c.isDark ? c.cell : c.background;
    return TgNav(
      isDesktop: true,
      selectedId: _selectedId,
      onOpen: _open,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              _searchFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _searchFocus.requestFocus(),
        },
        child: Focus(
          autofocus: true,
          child: CupertinoPageScaffold(
            backgroundColor: c.background,
            child: Row(
              children: [
                SizedBox(
                  width: Tg.sidebarWidth,
                  child: ColoredBox(
                    color: sidebarColor,
                    child: SafeArea(
                      right: false,
                      child: Column(
                        children: [
                          _sidebarHeader(c),
                          Expanded(child: _sidebarContent()),
                          _sidebarTabs(c),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(width: 0.5, color: c.separator),
                Expanded(child: _detailPane(c)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarHeader(TgColors c) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(_tab.title(context.l10n), style: TgText.navTitle),
              ),
            ],
          ),
        ),
        if (_tab != _Tab.settings)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: CupertinoSearchTextField(
              controller: _search,
              focusNode: _searchFocus,
              placeholder: context.l10n.searchShortcut,
              backgroundColor: c.isDark ? c.background : c.searchField,
              borderRadius: BorderRadius.circular(18),
              style: TextStyle(color: c.primaryText),
              placeholderStyle: TextStyle(color: c.placeholder),
              itemColor: c.placeholder,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
      ],
    );
  }

  Widget _sidebarContent() => switch (_tab) {
    _Tab.chats => CustomScrollView(slivers: [ChatListSliver(query: _query)]),
    _Tab.contacts => ContactsList(query: _query),
    _Tab.settings => const SettingsMenu(),
  };

  Widget _sidebarTabs(TgColors c) {
    final tg = AppScope.of(context).tg;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: Row(
        children: [
          for (final tab in _Tab.values)
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _selectTab(tab),
                child: IconTheme(
                  data: IconThemeData(
                    color: tab == _tab ? c.accent : c.tabInactive,
                    size: 28,
                  ),
                  child: tab == _Tab.chats
                      ? ListenableBuilder(
                          listenable: tg,
                          builder: (context, _) => _TabIcon(
                            icon: tab.icon,
                            badge: unreadChats(context),
                          ),
                        )
                      : Icon(tab.icon),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailPane(TgColors c) {
    final detail = _detail;
    if (detail == null) {
      if (_tab == _Tab.settings) return ColoredBox(color: c.groupedBackground);
      return Stack(
        fit: StackFit.expand,
        children: [
          ChatWallpaper(colors: c),
          Center(child: ServicePill(context.l10n.selectChat)),
        ],
      );
    }
    return HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: ValueKey(_selectedId),
        onGenerateRoute: (settings) =>
            CupertinoPageRoute<void>(builder: detail, settings: settings),
      ),
    );
  }
}
