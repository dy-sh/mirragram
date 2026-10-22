import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../e2e/e2e_service.dart';
import '../../l10n/l10n.dart';
import '../../tdlib/td_client.dart';
import '../format.dart';
import '../layout/nav.dart';
import '../tg_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/read_checks.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.background,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(context.l10n.tabChats),
            border: null,
            backgroundColor: c.navBar,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: CupertinoSearchTextField(
                placeholder: context.l10n.search,
                backgroundColor: c.searchField,
                style: TextStyle(color: c.primaryText),
                placeholderStyle: TextStyle(color: c.placeholder),
                itemColor: c.placeholder,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          ChatListSliver(query: _query),
        ],
      ),
    );
  }
}

class ChatListSliver extends StatelessWidget {
  const ChatListSliver({super.key, this.query = ''});

  final String query;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.tg, scope.e2e]),
      builder: (context, _) {
        var chats = scope.tg.mainChatList;
        if (query.isNotEmpty) {
          final q = query.toLowerCase();
          chats = chats
              .where((c) => _title(context, c).toLowerCase().contains(q))
              .toList();
        }
        return SliverList.builder(
          itemCount: chats.length,
          itemBuilder: (context, i) => ChatListTile(chat: chats[i]),
        );
      },
    );
  }

  static String _title(BuildContext context, TdObject chat) =>
      AppScope.of(context).tg.isSavedMessages(chat)
      ? context.l10n.savedMessages
      : chat['title'] as String;
}

class ChatListTile extends StatelessWidget {
  const ChatListTile({super.key, required this.chat});

  final TdObject chat;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final nav = TgNav.of(context);
    final c = TgColors.of(context);
    final tg = scope.tg;
    final e2e = scope.e2e;
    final chatId = chat['id'] as int;
    final desktop = nav.isDesktop;
    final selected = nav.selectedId == TgNav.chatId(chatId);
    final last = chat['last_message'] as TdObject?;
    final unread = chat['unread_count'] as int? ?? 0;
    final muted = tg.isMuted(chat);
    final pinned = tg.isPinned(chat);
    final encrypted = e2e.isReady && e2e.store.isEncryptionEnabled(chatId);
    final draft = chat['draft_message'] as TdObject?;
    final saved = tg.isSavedMessages(chat);
    final l = context.l10n;

    const white = Color(0xFFFFFFFF);
    final titleColor = selected
        ? white
        : (encrypted ? c.secure : c.primaryText);
    final secondary = selected ? white.withValues(alpha: 0.8) : c.secondaryText;
    final authorColor = selected ? white : c.primaryText;
    final accent = selected ? white : c.accent;

    final e2eView = last == null ? null : e2e.view(last);
    final title = saved ? l.savedMessages : chat['title'] as String;
    final previewStyle = TgText.preview.copyWith(color: secondary);

    Widget preview;
    if (draft != null) {
      final draftText =
          ((draft['content'] as TdObject?)?['text'] as TdObject?)?['text'] ??
          '';
      preview = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l.draft,
              style: TextStyle(color: selected ? white : c.destructive),
            ),
            TextSpan(text: '$draftText'),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: previewStyle,
      );
    } else if (last != null) {
      final text = contentPreview(l, last, e2eView).replaceAll('\n', ' ');
      final showAuthor = tg.isGroup(chat) && !isServiceMessage(last);
      final author = last['is_outgoing'] == true ? l.you : tg.senderName(last);
      preview = Text.rich(
        TextSpan(
          children: [
            if (showAuthor)
              TextSpan(
                text: '$author\n',
                style: TextStyle(color: authorColor),
              ),
            if (e2eView is E2eText)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(
                    CupertinoIcons.lock_fill,
                    size: 13,
                    color: selected ? white : c.secure,
                  ),
                ),
              ),
            TextSpan(text: text),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: previewStyle,
      );
    } else {
      preview = const SizedBox.shrink();
    }

    final avatarSize = desktop ? 54.0 : Tg.chatListAvatar;
    final rowHeight = desktop ? 72.0 : 76.0;

    final content = Row(
      children: [
        Avatar.chat(chat, size: avatarSize),
        SizedBox(width: desktop ? 10 : 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(right: 10, top: 7, bottom: 7),
            decoration: BoxDecoration(
              border: desktop
                  ? null
                  : Border(bottom: BorderSide(color: c.separator, width: 0.33)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (encrypted)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Icon(
                                CupertinoIcons.lock_fill,
                                size: 14,
                                color: titleColor,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TgText.title.copyWith(
                                color: titleColor,
                                fontSize: desktop ? 15.5 : 17,
                              ),
                            ),
                          ),
                          if (tg.isVerified(chat))
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Icon(
                                CupertinoIcons.checkmark_seal_fill,
                                size: 16,
                                color: accent,
                              ),
                            ),
                          if (muted)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Icon(
                                CupertinoIcons.speaker_slash_fill,
                                size: 13,
                                color: selected ? secondary : c.mutedBadge,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (last != null && last['is_outgoing'] == true && !saved)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ReadChecks(
                          read:
                              (last['id'] as int) <=
                              (chat['last_read_outbox_message_id'] as int? ??
                                  0),
                          pending: last['sending_state'] != null,
                          color: accent,
                        ),
                      ),
                    if (last != null)
                      Text(
                        chatListDate(l, last['date'] as int),
                        style: TgText.date.copyWith(
                          color: secondary,
                          fontSize: desktop ? 13 : 14,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(fontSize: desktop ? 14.5 : 15.5),
                          child: preview,
                        ),
                      ),
                      if (unread > 0)
                        _Badge(
                          count: unread,
                          color: selected
                              ? white
                              : (muted ? c.mutedBadge : c.accent),
                          textColor: selected ? c.selected : white,
                        )
                      else if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Icon(
                            CupertinoIcons.pin_fill,
                            size: 16,
                            color: selected ? white : c.mutedBadge,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => nav.open(
        context,
        TgNav.chatId(chatId),
        (_) => ChatScreen(chatId: chatId),
      ),
      child: desktop
          ? Container(
              height: rowHeight,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: selected ? c.selected : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: content,
            )
          : Container(
              color: pinned ? c.pinned : c.background,
              height: rowHeight,
              padding: const EdgeInsets.only(left: 10),
              child: content,
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.color,
    required this.textColor,
  });

  final int count;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          count > 999 ? context.l10n.unreadThousands(count ~/ 1000) : '$count',
          style: TextStyle(color: textColor, fontSize: 14),
        ),
      ),
    );
  }
}
