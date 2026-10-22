import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../l10n/l10n.dart';
import '../../tdlib/td_client.dart';
import '../format.dart';
import '../layout/nav.dart';
import '../tg_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/tg_button.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.background,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          CupertinoSliverNavigationBar(
            largeTitle: Text(context.l10n.tabContacts),
            border: null,
            backgroundColor: c.navBar,
          ),
        ],
        body: const ContactsList(),
      ),
    );
  }
}

/// Recently online contacts first.
class ContactsList extends StatefulWidget {
  const ContactsList({super.key, this.query = ''});

  final String query;

  @override
  State<ContactsList> createState() => _ContactsListState();
}

class _ContactsListState extends State<ContactsList> {
  List<int>? _ids;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    AppScope.of(context).tg.client
        .send({'@type': 'getContacts'})
        .then(
          (res) {
            if (mounted) {
              setState(() => _ids = (res['user_ids'] as List).cast<int>());
            }
          },
          onError: (Object _) {
            if (mounted) setState(() => _ids = []);
          },
        );
  }

  Future<void> _open(int userId) async {
    final tg = AppScope.of(context).tg;
    final nav = TgNav.of(context);
    final TdObject chat;
    try {
      chat = await tg.client.send({
        '@type': 'createPrivateChat',
        'user_id': userId,
        'force': false,
      });
    } on TdError catch (e) {
      if (mounted) await showTgAlert(context, context.l10n.error, e.message);
      return;
    }
    if (!mounted) return;
    final chatId = chat['id'] as int;
    nav.open(context, TgNav.chatId(chatId), (_) => ChatScreen(chatId: chatId));
  }

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final c = TgColors.of(context);
    if (_ids == null) return const Center(child: CupertinoActivityIndicator());
    return ListenableBuilder(
      listenable: tg,
      builder: (context, _) {
        final q = widget.query.toLowerCase();
        final ids =
            _ids!
                .where((id) => tg.userName(id).toLowerCase().contains(q))
                .toList()
              ..sort(
                (a, b) => _onlineRank(
                  tg.users[b],
                ).compareTo(_onlineRank(tg.users[a])),
              );
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: ids.length,
          itemBuilder: (context, i) {
            final id = ids[i];
            final status = lastSeen(context.l10n, tg.users[id]);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(id),
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    Avatar.user(id, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: c.separator, width: 0.33),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tg.userName(id),
                              style: TgText.title.copyWith(
                                color: c.primaryText,
                              ),
                            ),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 14,
                                color: isOnline(tg.users[id])
                                    ? c.accent
                                    : c.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static int _onlineRank(TdObject? user) {
    final status = user?['status'] as TdObject?;
    return switch (status?['@type']) {
      'userStatusOnline' => 1 << 40,
      'userStatusOffline' => status!['was_online'] as int,
      _ => 0,
    };
  }
}
