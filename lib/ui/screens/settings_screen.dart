import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../layout/nav.dart';
import '../tg_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/language_picker.dart';
import '../widgets/tg_list.dart';
import 'appearance_screen.dart';
import 'e2e_password_screen.dart';
import '../../l10n/l10n.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.groupedBackground,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: const [_ProfileHeader(), SettingsMenu(embedded: true)],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final c = TgColors.of(context);
    return ListenableBuilder(
      listenable: tg,
      builder: (context, _) => Column(
        children: [
          const SizedBox(height: 32),
          Center(child: Avatar.user(tg.myUserId, size: 100)),
          const SizedBox(height: 12),
          Text(
            tg.userName(tg.myUserId ?? 0),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: c.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _contacts(tg.users[tg.myUserId]),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.secondaryText),
          ),
        ],
      ),
    );
  }
}

String _contacts(Map<String, dynamic>? me) {
  final usernames = (me?['usernames'] as Map?)?['active_usernames'] as List?;
  return [
    if ((me?['phone_number'] as String? ?? '').isNotEmpty)
      '+${me!['phone_number']}',
    if (usernames != null && usernames.isNotEmpty) '@${usernames.first}',
  ].join(' • ');
}

/// On desktop this is the sidebar, and the selected section opens on the
/// right.
class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key, this.embedded = false});

  /// Inside the mobile settings screen, which draws the profile itself.
  final bool embedded;

  static const defaultId = 'settings:appearance';
  static Widget defaultPage(BuildContext context) => const AppearanceScreen();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final nav = TgNav.of(context);
    final c = TgColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.tg, scope.e2e, scope.appearance]),
      builder: (context, _) {
        TgCell item(
          String id,
          String title,
          Widget icon,
          WidgetBuilder page, {
          String? value,
        }) {
          final fullId = 'settings:$id';
          return TgCell(
            leading: icon,
            title: title,
            value: value,
            chevron: true,
            selected: nav.isDesktop && nav.selectedId == fullId,
            onTap: () => nav.open(context, fullId, page),
          );
        }

        final sections = [
          TgSection(
            children: [
              item(
                'appearance',
                context.l10n.appearance,
                const TgIconBox(
                  CupertinoIcons.paintbrush_fill,
                  Color(0xFF1C8BF5),
                ),
                defaultPage,
              ),
              TgCell(
                leading: const TgIconBox(
                  CupertinoIcons.globe,
                  Color(0xFFB259F0),
                ),
                title: context.l10n.language,
                value: scope.appearance.languageCode == null
                    ? context.l10n.languageSystem
                    : context.l10n.languageName,
                chevron: true,
                onTap: () => showLanguagePicker(context),
              ),
              item(
                'e2e',
                context.l10n.encryption,
                TgIconBox(CupertinoIcons.lock_shield_fill, c.secure),
                (context) => E2ePasswordScreen(
                  onDone: () => Navigator.of(context).maybePop(),
                ),
                value: scope.e2e.isReady ? context.l10n.on : context.l10n.off,
              ),
            ],
          ),
          TgSection(
            children: [
              TgCell(
                leading: TgIconBox(
                  CupertinoIcons.square_arrow_right,
                  c.destructive,
                ),
                title: context.l10n.logOut,
                titleColor: c.destructive,
                onTap: () => _logOut(context),
              ),
            ],
          ),
        ];
        if (embedded) return Column(children: sections);

        final me = scope.tg.users[scope.tg.myUserId];
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
              child: Row(
                children: [
                  Avatar.user(scope.tg.myUserId, size: 60),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scope.tg.userName(scope.tg.myUserId ?? 0),
                          style: TgText.title.copyWith(color: c.primaryText),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _contacts(me),
                          style: TextStyle(
                            fontSize: 14,
                            color: c.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...sections,
          ],
        );
      },
    );
  }

  Future<void> _logOut(BuildContext context) async {
    final scope = AppScope.of(context);
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(context.l10n.logOutTitle),
        content: Text(context.l10n.logOutMessage),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.logOut),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await scope.e2e.reset();
    await scope.tg.logOut();
  }
}
