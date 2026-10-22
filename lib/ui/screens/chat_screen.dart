import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../e2e/chat_encryption.dart';
import '../../e2e/e2e_service.dart';
import '../../tdlib/td_client.dart';
import '../../telegram/chat_controller.dart';
import '../format.dart';
import '../layout/nav.dart';
import '../media/pick_images.dart';
import '../media/send_photos_sheet.dart';
import '../theme/wallpaper.dart';
import '../tg_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/tg_button.dart';
import 'chat_encryption_screen.dart';
import '../../l10n/l10n.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatController? _controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final scope = AppScope.of(context);
    _controller = ChatController(scope.tg, scope.e2e, widget.chatId);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _controller!.loadOlder();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ChatEncryption _encryption(BuildContext context) {
    final scope = AppScope.of(context);
    return ChatEncryption(scope.tg, scope.e2e, scope.tg.chats[widget.chatId]!);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final tg = AppScope.of(context).tg;
    final enc = _encryption(context);
    try {
      final (outgoing, encrypted) = enc.prepareOutgoing(text);
      setState(() => _sending = true);
      await tg.sendText(widget.chatId, outgoing, disableLinkPreview: encrypted);
      _input.clear();
    } on E2eException catch (e) {
      if (mounted) {
        await showTgAlert(
          context,
          context.l10n.cantSend,
          e2eErrorText(context.l10n, e.error),
        );
      }
    } on TdError catch (e) {
      if (mounted) await showTgAlert(context, context.l10n.error, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final l = context.l10n;
    final tg = AppScope.of(context).tg;
    final encrypted = _encryption(context).state == ChatE2eState.on;
    final images = await pickImages();
    if (images.isEmpty || !mounted) return;
    if (images.any((i) => i.bytes > maxPhotoBytes)) {
      return showTgAlert(context, l.error, l.photoTooLarge);
    }
    final caption = await showSendPhotosSheet(
      context,
      images,
      encryptedChat: encrypted,
    );
    if (caption == null) return;
    try {
      await tg.sendPhotos(widget.chatId, [
        for (final i in images)
          (path: i.path, width: i.width, height: i.height),
      ], caption);
    } on TdError catch (e) {
      if (mounted) await showTgAlert(context, l.error, e.message);
    }
  }

  void _openEncryption() => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => ChatEncryptionScreen(chatId: widget.chatId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final desktop = TgNav.maybeOf(context)?.isDesktop ?? false;
    final c = TgColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.tg,
        scope.e2e,
        scope.appearance,
        _controller!,
      ]),
      builder: (context, _) {
        final tg = scope.tg;
        final chat = tg.chats[widget.chatId]!;
        final enc = _encryption(context);
        return CupertinoPageScaffold(
          backgroundColor: c.background,
          navigationBar: desktop ? null : _navBar(context, chat, enc),
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatWallpaper(colors: c, chat: chat),
              ),
              SafeArea(
                child: Column(
                  children: [
                    if (desktop)
                      _DesktopHeader(
                        chat: chat,
                        subtitle: _subtitle(context, chat),
                        secure: enc.state == ChatE2eState.on,
                        onEncryption: _openEncryption,
                      ),
                    if (enc.isOffered) _OfferBanner(enc: enc),
                    Expanded(child: _messages(context, chat)),
                    _InputPanel(
                      controller: _input,
                      state: enc.state,
                      sending: _sending,
                      desktop: desktop,
                      onSend: _send,
                      onLockTap: _openEncryption,
                      onAttach: _attach,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _subtitle(BuildContext context, TdObject chat) {
    final tg = AppScope.of(context).tg;
    final peer = tg.privateUserId(chat);
    if (tg.isSavedMessages(chat)) return '';
    if (peer != null) return lastSeen(context.l10n, tg.users[peer]);
    final count = tg.memberCount(chat);
    return count == null ? '' : context.l10n.members(count);
  }

  ObstructingPreferredSizeWidget _navBar(
    BuildContext context,
    TdObject chat,
    ChatEncryption enc,
  ) {
    final tg = AppScope.of(context).tg;
    final c = TgColors.of(context);
    final subtitle = _subtitle(context, chat);
    final secure = enc.state == ChatE2eState.on;

    return CupertinoNavigationBar(
      backgroundColor: c.navBar,
      border: Border(bottom: BorderSide(color: c.separator, width: 0.33)),
      previousPageTitle: context.l10n.tabChats,
      middle: GestureDetector(
        onTap: _openEncryption,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (secure)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      CupertinoIcons.lock_fill,
                      size: 14,
                      color: c.secure,
                    ),
                  ),
                Flexible(
                  child: Text(
                    tg.isSavedMessages(chat)
                        ? context.l10n.savedMessages
                        : chat['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TgText.navTitle.copyWith(
                      color: secure ? c.secure : c.primaryText,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TgText.navSubtitle.copyWith(
                  color: subtitle == context.l10n.online
                      ? c.accent
                      : c.secondaryText,
                ),
              ),
          ],
        ),
      ),
      trailing: GestureDetector(
        onTap: _openEncryption,
        child: Avatar.chat(chat, size: 37),
      ),
    );
  }

  Widget _messages(BuildContext context, TdObject chat) {
    final scope = AppScope.of(context);
    final tg = scope.tg;
    final e2e = scope.e2e;
    final messages = _controller!.messages;
    final isGroup = tg.isGroup(chat);
    final lastReadOut = chat['last_read_outbox_message_id'] as int? ?? 0;

    // Reversed list: index 0 is the newest message at the bottom.
    return LayoutBuilder(
      builder: (context, constraints) => _list(
        context,
        messages,
        isGroup: isGroup,
        lastReadOut: lastReadOut,
        e2e: e2e,
        bubbleMaxWidth: (constraints.maxWidth * 0.78).clamp(200, 520),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<TdObject> messages, {
    required bool isGroup,
    required int lastReadOut,
    required E2eService e2e,
    required double bubbleMaxWidth,
  }) {
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final index = messages.length - 1 - i;
        final m = messages[index];
        final prev = index > 0 ? messages[index - 1] : null;
        final next = index < messages.length - 1 ? messages[index + 1] : null;
        final date = fromUnix(m['date'] as int);
        final newDay =
            prev == null || !_sameDay(fromUnix(prev['date'] as int), date);

        return Column(
          children: [
            if (newDay) ServicePill(dayHeader(context.l10n, date)),
            _messageRow(
              context,
              m,
              prev: newDay ? null : prev,
              next: next,
              isGroup: isGroup,
              lastReadOut: lastReadOut,
              e2e: e2e.view(m),
              bubbleMaxWidth: bubbleMaxWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _messageRow(
    BuildContext context,
    TdObject m, {
    required TdObject? prev,
    required TdObject? next,
    required bool isGroup,
    required int lastReadOut,
    required E2eView? e2e,
    required double bubbleMaxWidth,
  }) {
    final tg = AppScope.of(context).tg;

    final l = context.l10n;
    if (isServiceMessage(m)) return ServicePill(contentPreview(l, m, null));
    final out = m['is_outgoing'] == true;
    switch (e2e) {
      case E2eKeyAnnouncement(:final userId, :final valid):
        return ServicePill(
          !valid
              ? l.forgedKey
              : (out
                    ? l.youPublishedKey
                    : l.peerPublishedKey(tg.userName(userId))),
          icon: CupertinoIcons.lock_fill,
        );
      case E2eGroupKeyAnnouncement(:final forMe):
        final text = out
            ? l.youSharedGroupKey
            : l.peerSharedGroupKey(tg.senderName(m));
        return ServicePill(
          forMe ? text : '$text (${l.notForThisDevice})',
          icon: CupertinoIcons.lock_fill,
        );
      default:
        break;
    }

    bool sameSeries(TdObject? other) =>
        other != null &&
        !isServiceMessage(other) &&
        _senderKey(other) == _senderKey(m) &&
        ((other['date'] as int) - (m['date'] as int)).abs() < 300;
    final firstInSeries = !sameSeries(prev);
    final lastInSeries = !sameSeries(next);
    final showSender = isGroup && !out && firstInSeries;
    final senderId = senderUserId(m) ?? 0;
    final c = TgColors.of(context);
    final accentId = tg.users[senderId]?['accent_color_id'] as int?;
    final colorIndex = accentId != null && accentId >= 0 && accentId < 7
        ? accentId
        : Tg.colorIndex(senderId);

    final bubble = MessageBubble(
      message: m,
      e2e: e2e,
      read: (m['id'] as int) <= lastReadOut,
      tail: lastInSeries,
      maxWidth: bubbleMaxWidth,
      senderName: showSender ? tg.senderName(m) : null,
      senderColor: (c.isDark ? Tg.nameColorsDark : Tg.nameColors)[colorIndex],
    );

    return Padding(
      padding: EdgeInsets.only(left: 8, right: 8, top: firstInSeries ? 6 : 1),
      child: Row(
        mainAxisAlignment: out
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isGroup && !out)
            SizedBox(
              width: 42,
              child: lastInSeries
                  ? Align(
                      alignment: Alignment.bottomLeft,
                      child: Avatar.user(senderId, size: 37),
                    )
                  : null,
            ),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  static String _senderKey(TdObject m) {
    final s = m['sender_id'] as TdObject;
    return '${s['user_id'] ?? s['chat_id']}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.enc});

  final ChatEncryption enc;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.separator, width: 0.33)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(CupertinoIcons.lock_fill, size: 18, color: c.secure),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              enc.isGroup
                  ? context.l10n.groupUsesEncryption
                  : context.l10n.peerUsesEncryption,
              style: TextStyle(fontSize: 14, color: c.primaryText),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: enc.enable,
            child: Text(
              context.l10n.enable,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.chat,
    required this.subtitle,
    required this.secure,
    required this.onEncryption,
  });

  final TdObject chat;
  final String subtitle;
  final bool secure;
  final VoidCallback onEncryption;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final tg = AppScope.of(context).tg;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.isDark ? c.cell : c.background,
        border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onEncryption,
            child: Avatar.chat(chat, size: 38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEncryption,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (secure)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            CupertinoIcons.lock_fill,
                            size: 13,
                            color: c.secure,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          tg.isSavedMessages(chat)
                              ? context.l10n.savedMessages
                              : chat['title'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TgText.navTitle.copyWith(
                            fontSize: 15.5,
                            color: secure ? c.secure : c.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TgText.navSubtitle.copyWith(
                        color: subtitle == context.l10n.online
                            ? c.accent
                            : c.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            onPressed: onEncryption,
            child: Icon(
              secure ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
              size: 22,
              color: secure ? c.secure : c.panelIcon,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.controller,
    required this.state,
    required this.sending,
    required this.desktop,
    required this.onSend,
    required this.onLockTap,
    required this.onAttach,
  });

  final TextEditingController controller;
  final ChatE2eState state;
  final bool sending;
  final bool desktop;
  final VoidCallback onSend;
  final VoidCallback onLockTap;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final lockColor = switch (state) {
      ChatE2eState.on => c.secure,
      ChatE2eState.waiting => const Color(0xFFFF9500),
      _ => c.panelIcon.withValues(alpha: 0.7),
    };
    final placeholder = switch (state) {
      ChatE2eState.on => context.l10n.encryptedMessagePlaceholder,
      ChatE2eState.waiting => context.l10n.waitingPeerKeyPlaceholder,
      _ =>
        desktop
            ? context.l10n.writeMessagePlaceholder
            : context.l10n.messagePlaceholder,
    };

    final field = CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      minLines: 1,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(fontSize: 17, color: c.primaryText),
      placeholderStyle: TextStyle(fontSize: 17, color: c.placeholder),
      cursorColor: c.accent,
      padding: const EdgeInsets.fromLTRB(4, 7, 10, 7),
      onSubmitted: desktop ? (_) => onSend() : null,
      textInputAction: desktop ? TextInputAction.send : null,
      decoration: BoxDecoration(
        color: c.inputField,
        border: Border.all(color: c.inputFieldBorder, width: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      prefix: state == ChatE2eState.unsupported
          ? const SizedBox(width: 8)
          : GestureDetector(
              onTap: onLockTap,
              child: Padding(
                padding: const EdgeInsets.only(left: 9, right: 2),
                child: Icon(
                  state == ChatE2eState.on || state == ChatE2eState.waiting
                      ? CupertinoIcons.lock_fill
                      : CupertinoIcons.lock_open_fill,
                  size: 17,
                  color: lockColor,
                ),
              ),
            ),
    );

    return Container(
      decoration: BoxDecoration(
        color: desktop ? (c.isDark ? c.cell : c.background) : c.navBar,
        border: Border(top: BorderSide(color: c.separator, width: 0.33)),
      ),
      padding: EdgeInsets.fromLTRB(4, desktop ? 8 : 6, 6, desktop ? 8 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            minimumSize: const Size(36, 36),
            onPressed: onAttach,
            child: Icon(CupertinoIcons.paperclip, color: c.panelIcon, size: 26),
          ),
          Expanded(child: field),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.trim().isEmpty) {
                return CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(36, 36),
                  onPressed: () {},
                  child: Icon(CupertinoIcons.mic, color: c.panelIcon, size: 26),
                );
              }
              return CupertinoButton(
                padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                minimumSize: const Size(36, 36),
                onPressed: sending ? null : onSend,
                child: Container(
                  width: 33,
                  height: 33,
                  decoration: BoxDecoration(
                    color: state == ChatE2eState.on ? c.secure : c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.arrow_up,
                    color: Color(0xFFFFFFFF),
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
