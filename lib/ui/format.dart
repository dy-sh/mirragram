import 'package:intl/intl.dart';

import '../e2e/e2e_service.dart';
import '../l10n/l10n.dart';
import '../tdlib/td_client.dart';

DateTime fromUnix(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

int _daysAgo(DateTime t) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
}

String chatListDate(AppLocalizations l, int unix) {
  final t = fromUnix(unix);
  final days = _daysAgo(t);
  if (days == 0) return hhmm(t);
  if (days < 7) return DateFormat.E(l.localeName).format(t);
  return DateFormat(l.shortDatePattern, l.localeName).format(t);
}

String dayHeader(AppLocalizations l, DateTime t) {
  final days = _daysAgo(t);
  if (days == 0) return l.today;
  if (days == 1) return l.yesterday;
  return t.year == DateTime.now().year
      ? DateFormat.MMMMd(l.localeName).format(t)
      : DateFormat.yMMMMd(l.localeName).format(t);
}

String lastSeen(AppLocalizations l, TdObject? user) {
  final status = user?['status'] as TdObject?;
  switch (status?['@type']) {
    case 'userStatusOnline':
      return l.online;
    case 'userStatusOffline':
      final t = fromUnix(status!['was_online'] as int);
      final minutes = DateTime.now().difference(t).inMinutes;
      if (minutes < 1) return l.lastSeenJustNow;
      if (minutes < 60) return l.lastSeenMinutesAgo(minutes);
      if (_daysAgo(t) == 0) return l.lastSeenAt(hhmm(t));
      return l.lastSeenOn(DateFormat.MMMd(l.localeName).format(t), hhmm(t));
    case 'userStatusRecently':
      return l.lastSeenRecently;
    case 'userStatusLastWeek':
      return l.lastSeenWithinWeek;
    case 'userStatusLastMonth':
      return l.lastSeenWithinMonth;
    default:
      return l.lastSeenLongAgo;
  }
}

bool isOnline(TdObject? user) =>
    (user?['status'] as TdObject?)?['@type'] == 'userStatusOnline';

String contentPreview(AppLocalizations l, TdObject message, E2eView? e2e) {
  if (e2e != null) return e2eText(l, e2e);
  final content = message['content'] as TdObject;
  String withCaption(String label) {
    final caption =
        ((content['caption'] as TdObject?)?['text'] as String?) ?? '';
    return caption.isEmpty ? label : '$label, $caption';
  }

  return switch (content['@type']) {
    'messageText' => (content['text'] as TdObject)['text'] as String,
    'messagePhoto' => withCaption(l.contentPhoto),
    'messageVideo' => withCaption(l.contentVideo),
    'messageAnimation' => withCaption(l.contentGif),
    'messageDocument' => withCaption(
      ((content['document'] as TdObject)['file_name'] as String?) ??
          l.contentFile,
    ),
    'messageVoiceNote' => l.contentVoice,
    'messageVideoNote' => l.contentVideoMessage,
    'messageAudio' => withCaption(l.contentMusic),
    'messageSticker' =>
      '${(content['sticker'] as TdObject)['emoji']} ${l.contentSticker}',
    'messageLocation' || 'messageVenue' => l.contentLocation,
    'messageContact' => l.contentContact,
    'messagePoll' => l.contentPoll,
    'messageCall' => l.contentCall,
    'messageContactRegistered' => l.serviceJoinedTelegram,
    'messageChatAddMembers' => l.serviceMembersAdded,
    'messageChatJoinByLink' => l.serviceJoinedByLink,
    'messageChatDeleteMember' => l.serviceMemberLeft,
    'messageChatChangeTitle' => l.serviceTitleChanged(
      content['title'] as String,
    ),
    'messageBasicGroupChatCreate' ||
    'messageSupergroupChatCreate' => l.serviceGroupCreated,
    'messagePinMessage' => l.serviceMessagePinned,
    _ => l.contentMessage,
  };
}

String e2eText(AppLocalizations l, E2eView view) => switch (view) {
  E2eText(:final text) => text,
  E2eKeyAnnouncement() => '🔑 ${l.e2eKeyPreview}',
  E2eGroupKeyAnnouncement() => '🔑 ${l.e2eGroupKeyPreview}',
  E2eUndecryptable() || E2eLocked() => '🔒 ${l.e2eEncryptedPreview}',
};

String undecryptableReason(AppLocalizations l, UndecryptableReason r) =>
    switch (r) {
      UndecryptableReason.noSenderKey => l.undecryptableNoSenderKey,
      UndecryptableReason.noGroupKey => l.undecryptableNoGroupKey,
      UndecryptableReason.otherKey => l.undecryptableOtherKey,
      UndecryptableReason.forgedSender => l.undecryptableForgedSender,
      UndecryptableReason.unsupported => l.undecryptableUnsupported,
      UndecryptableReason.corrupted => l.undecryptableCorrupted,
    };

String e2eErrorText(AppLocalizations l, E2eError e) => switch (e) {
  E2eError.noPeerKey => l.e2eErrorNoPeerKey,
  E2eError.noGroupKey => l.e2eErrorNoGroupKey,
  E2eError.tooLong => l.e2eErrorTooLong,
};

/// Service messages are drawn centered, without a bubble.
bool isServiceMessage(TdObject message) {
  final type = (message['content'] as TdObject)['@type'] as String;
  return const {
    'messageContactRegistered',
    'messageChatAddMembers',
    'messageChatJoinByLink',
    'messageChatDeleteMember',
    'messageChatChangeTitle',
    'messageBasicGroupChatCreate',
    'messageSupergroupChatCreate',
    'messagePinMessage',
    'messageChatChangePhoto',
    'messageChatDeletePhoto',
    'messageChatUpgradeTo',
    'messageChatUpgradeFrom',
    'messageScreenshotTaken',
    'messageChatSetMessageAutoDeleteTime',
  }.contains(type);
}
