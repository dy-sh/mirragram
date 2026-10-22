import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../e2e/chat_encryption.dart';
import '../../l10n/l10n.dart';
import '../../tdlib/td_client.dart';
import '../tg_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/tg_button.dart';
import '../widgets/tg_list.dart';
import 'e2e_password_screen.dart';

class ChatEncryptionScreen extends StatefulWidget {
  const ChatEncryptionScreen({super.key, required this.chatId});

  final int chatId;

  @override
  State<ChatEncryptionScreen> createState() => _ChatEncryptionScreenState();
}

class _ChatEncryptionScreenState extends State<ChatEncryptionScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on TdError catch (e) {
      if (mounted) await showTgAlert(context, context.l10n.error, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.tg, scope.e2e]),
      builder: (context, _) {
        final chat = scope.tg.chats[widget.chatId]!;
        final enc = ChatEncryption(scope.tg, scope.e2e, chat);
        final c = TgColors.of(context);
        return CupertinoPageScaffold(
          backgroundColor: c.groupedBackground,
          navigationBar: CupertinoNavigationBar(
            middle: Text(context.l10n.encryption),
            previousPageTitle: context.l10n.back,
            backgroundColor: c.navBar,
            border: Border(bottom: BorderSide(color: c.separator, width: 0.33)),
          ),
          child: SafeArea(
            child: ListView(
              children: [
                const SizedBox(height: 24),
                Center(child: Avatar.chat(chat, size: 80)),
                const SizedBox(height: 12),
                Text(
                  scope.tg.isSavedMessages(chat)
                      ? context.l10n.savedMessages
                      : chat['title'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: c.primaryText,
                  ),
                ),
                ..._body(context, enc),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, ChatEncryption enc) {
    final e2e = AppScope.of(context).e2e;
    final tg = AppScope.of(context).tg;

    switch (enc.state) {
      case ChatE2eState.unsupported:
        return [_Footer(context.l10n.encryptionUnsupported)];
      case ChatE2eState.locked:
        return [
          _Footer(context.l10n.encryptionLocked),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TgButton(
              label: context.l10n.setEncryptionPassword,
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (context) =>
                      E2ePasswordScreen(onDone: () => Navigator.pop(context)),
                ),
              ),
            ),
          ),
        ];
      default:
    }

    final c = TgColors.of(context);
    final enabled =
        enc.state == ChatE2eState.on || enc.state == ChatE2eState.waiting;
    final peer = enc.peerUserId;
    final widgets = <Widget>[
      TgSection(
        footer: _sectionFooter(enc),
        children: [
          TgCell(
            leading: Icon(CupertinoIcons.lock_fill, color: c.secure),
            title: context.l10n.encryptMessages,
            trailing: _busy
                ? const CupertinoActivityIndicator()
                : TgSwitch(
                    value: enabled,
                    color: c.secure,
                    onChanged: (v) => v ? _run(enc.enable) : enc.disable(),
                  ),
          ),
        ],
      ),
    ];

    if (peer != null && peer != tg.myUserId) {
      final number = e2e.safetyNumber(peer);
      widgets.add(
        TgSection(
          header: context.l10n.peerKey,
          footer: number == null ? null : context.l10n.peerKeyFooter,
          children: [
            if (number == null)
              TgCell(title: context.l10n.peerKeyMissing)
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _SafetyNumber(number),
              ),
              TgCell(
                title: context.l10n.verified,
                trailing: TgSwitch(
                  value: e2e.store.isVerified(peer),
                  color: c.secure,
                  onChanged: (v) {
                    e2e.store.setVerified(peer, v);
                    e2e.refresh();
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (enc.isGroup && enabled) {
      widgets.add(
        TgSection(
          header: context.l10n.groupKey,
          footer: context.l10n.groupKeyFooter,
          children: [
            TgCell(
              title: context.l10n.groupKey,
              value: enc.hasKey
                  ? context.l10n.groupKeyPresent
                  : context.l10n.groupKeyAbsent,
            ),
            TgCell(
              title: context.l10n.shareNewKey,
              titleColor: c.accent,
              onTap: _busy
                  ? null
                  : () => _run(() async {
                      final n = await enc.rotateGroupKey();
                      if (context.mounted) {
                        await showTgAlert(
                          context,
                          context.l10n.keySent,
                          context.l10n.keySentRecipients(n),
                        );
                      }
                    }),
            ),
          ],
        ),
      );
    }
    return widgets;
  }

  String _sectionFooter(ChatEncryption enc) => switch (enc.state) {
    ChatE2eState.waiting =>
      enc.isGroup ? context.l10n.waitingGroupKey : context.l10n.waitingPeerKey,
    ChatE2eState.on => context.l10n.encryptionOnFooter,
    _ => context.l10n.encryptionOffFooter,
  };
}

class _SafetyNumber extends StatelessWidget {
  const _SafetyNumber(this.number);

  final String number;

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (var i = 0; i < number.length; i += 5) number.substring(i, i + 5),
    ];
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final g in groups.skip(row * 4).take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      g,
                      style: TextStyle(
                        color: TgColors.of(context).primaryText,
                        fontSize: 18,
                        fontFamily: 'Menlo',
                        fontFamilyFallback: const ['Courier', 'monospace'],
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, color: TgColors.of(context).secondaryText),
    ),
  );
}
