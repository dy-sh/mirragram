import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../e2e/e2e_service.dart';
import '../../l10n/l10n.dart';
import '../../tdlib/td_client.dart';
import '../format.dart';
import '../tg_theme.dart';
import 'message_photo.dart';
import 'message_video.dart';
import 'read_checks.dart';

/// The time and checks sit inside the bubble and the text flows around them.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.e2e,
    required this.read,
    required this.tail,
    required this.maxWidth,
    this.senderName,
    this.senderColor,
  });

  final TdObject message;
  final E2eView? e2e;
  final bool read;

  /// The last message in a series gets a tail.
  final bool tail;
  final double maxWidth;
  final String? senderName;
  final Color? senderColor;

  bool get _out => message['is_outgoing'] == true;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    final textSize = AppScope.of(context).appearance.textSize;
    final metaColor = _out ? c.bubbleOutMeta : c.bubbleInMeta;
    final encrypted = e2e is E2eText;
    final edited = (message['edit_date'] as int? ?? 0) > 0;

    final meta = _meta(
      context,
      metaColor,
      encrypted: encrypted,
      edited: edited,
    );
    // Space reserved for the time at the end of the last line.
    final metaReserve =
        40.0 + (_out ? 18 : 0) + (encrypted ? 13 : 0) + (edited ? 28 : 0);

    final content = message['content'] as TdObject;
    if (e2e == null && content['@type'] == 'messageVideoNote') {
      return _videoNote(context, content['video_note'] as TdObject);
    }
    final media = e2e == null ? _media(content) : null;
    final caption = media == null
        ? ''
        : ((content['caption'] as TdObject?)?['text'] as String? ?? '');
    if (media != null && caption.isEmpty && senderName == null) {
      return _mediaOnly(context, media);
    }

    final (text, style) = media != null
        ? (
            caption,
            TgText.message.copyWith(
              fontSize: textSize,
              color: _out ? c.bubbleOutText : c.bubbleInText,
            ),
          )
        : _body(context, c, textSize);
    final photoSize = media?.size;

    return Padding(
      padding: EdgeInsets.only(
        left: _out ? 0 : (tail ? 0 : BubblePainter.tailWidth),
        right: _out ? (tail ? 0 : BubblePainter.tailWidth) : 0,
      ),
      child: CustomPaint(
        painter: BubblePainter(
          colors: _out ? c.bubbleOut : [c.bubbleIn],
          shadow: c.bubbleShadow,
          out: _out,
          tail: tail,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: photoSize == null
                ? maxWidth
                : photoSize.width + 4 + _tailPad,
            minWidth: 60,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (media != null && senderName != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    _out ? 11 : 11 + _tailPad,
                    6,
                    11,
                    4,
                  ),
                  child: _senderLabel(textSize),
                ),
              if (media != null && photoSize != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    _out ? 2 : 2 + _tailPad,
                    2,
                    _out ? 2 + _tailPad : 2,
                    caption.isEmpty ? 2 : 0,
                  ),
                  child: ClipRRect(
                    borderRadius: caption.isEmpty
                        ? BorderRadius.circular(BubblePainter.radius - 4)
                        : const BorderRadius.vertical(
                            top: Radius.circular(BubblePainter.radius - 2),
                            bottom: Radius.circular(4),
                          ),
                    child: Stack(
                      children: [
                        media.build(photoSize),
                        if (caption.isEmpty)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: _metaPill(context),
                          ),
                      ],
                    ),
                  ),
                ),
              if (media == null || caption.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    _out ? 11 : (tail ? 11 + BubblePainter.tailWidth : 11),
                    6,
                    _out ? (tail ? 11 + BubblePainter.tailWidth : 11) : 11,
                    6,
                  ),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (senderName != null && media == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: _senderLabel(textSize),
                            ),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: text, style: style),
                                WidgetSpan(
                                  child: SizedBox(
                                    width: metaReserve,
                                    height: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Positioned(right: 0, bottom: 0, child: meta),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _photoMaxWidth = 320.0;

  Widget _senderLabel(double textSize) => Text(
    senderName!,
    style: TextStyle(
      fontSize: textSize - 2,
      fontWeight: FontWeight.w600,
      color: senderColor,
    ),
  );

  double get _tailPad => tail ? BubblePainter.tailWidth : 0;

  Widget _meta(
    BuildContext context,
    Color color, {
    required bool encrypted,
    required bool edited,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (encrypted)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(CupertinoIcons.lock_fill, size: 10, color: color),
          ),
        if (edited)
          Text(
            context.l10n.edited,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          ),
        Text(
          hhmm(fromUnix(message['date'] as int)),
          style: TextStyle(fontSize: 11, color: color),
        ),
        if (_out) ...[
          const SizedBox(width: 3),
          ReadChecks(
            read: read,
            pending: message['sending_state'] != null,
            color: color,
            size: 12,
          ),
        ],
      ],
    );
  }

  /// Photo, video or GIF with its display size.
  _Media? _media(TdObject content) {
    final uploading = message['sending_state'] != null;
    final width = math.min(maxWidth, _photoMaxWidth);
    switch (content['@type']) {
      case 'messagePhoto':
        final photo = content['photo'] as TdObject;
        return _Media(
          photoDisplaySize(photo, width),
          (size) =>
              MessagePhoto(photo: photo, size: size, uploading: uploading),
        );
      case 'messageVideo' || 'messageAnimation':
        final isAnimation = content['@type'] == 'messageAnimation';
        final video =
            (isAnimation ? content['animation'] : content['video']) as TdObject;
        return _Media(
          mediaDisplaySize(
            video['width'] as int? ?? 0,
            video['height'] as int? ?? 0,
            width,
          ),
          (size) => MessageVideo(
            media: video,
            size: size,
            isAnimation: isAnimation,
            uploading: uploading,
          ),
        );
      default:
        return null;
    }
  }

  Widget _videoNote(BuildContext context, TdObject note) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Stack(
        children: [
          MessageVideoNote(note: note),
          Positioned(right: 4, bottom: 4, child: _metaPill(context)),
        ],
      ),
    );
  }

  Widget _metaPill(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0x80000000),
      borderRadius: BorderRadius.circular(10),
    ),
    child: _meta(
      context,
      const Color(0xFFFFFFFF),
      encrypted: false,
      edited: (message['edit_date'] as int? ?? 0) > 0,
    ),
  );

  /// Media without a caption: no bubble background, the time sits on the
  /// media.
  Widget _mediaOnly(BuildContext context, _Media media) {
    final size = media.size;
    final full = Size(size.width + _tailPad, size.height);
    return Padding(
      padding: EdgeInsets.only(
        left: _out ? 0 : (tail ? 0 : BubblePainter.tailWidth),
        right: _out ? (tail ? 0 : BubblePainter.tailWidth) : 0,
      ),
      child: ClipPath(
        clipper: _BubbleClipper(out: _out, tail: tail),
        child: SizedBox.fromSize(
          size: full,
          child: Stack(
            children: [
              media.build(full),
              Positioned(
                right: 6 + (_out ? _tailPad : 0),
                bottom: 6,
                child: _metaPill(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, TextStyle) _body(BuildContext context, TgColors c, double size) {
    final l = context.l10n;
    final normal = TgText.message.copyWith(
      fontSize: size,
      color: _out ? c.bubbleOutText : c.bubbleInText,
    );
    final italic = TextStyle(
      fontSize: size - 1,
      fontStyle: FontStyle.italic,
      color: _out ? c.bubbleOutMeta : c.bubbleInMeta,
    );
    return switch (e2e) {
      E2eText(:final text) => (text, normal),
      E2eUndecryptable(:final reason) => (
        '🔒 ${l.undecryptable(undecryptableReason(l, reason))}',
        italic,
      ),
      E2eLocked() => ('🔒 ${l.lockedMessage}', italic),
      E2eKeyAnnouncement() || E2eGroupKeyAnnouncement() => ('🔑', normal),
      null => switch ((message['content'] as TdObject)['@type']) {
        'messageText' => (contentPreview(l, message, null), normal),
        _ => ('[${contentPreview(l, message, null)}]', italic),
      },
    };
  }
}

class _Media {
  const _Media(this.size, this.build);

  final Size size;
  final Widget Function(Size size) build;
}

class _BubbleClipper extends CustomClipper<Path> {
  _BubbleClipper({required this.out, required this.tail});

  final bool out;
  final bool tail;

  @override
  Path getClip(Size size) => BubblePainter.shape(size, tail: tail, out: out);

  @override
  bool shouldReclip(_BubbleClipper old) => old.out != out || old.tail != tail;
}

class BubblePainter extends CustomPainter {
  BubblePainter({
    required this.colors,
    required this.out,
    required this.tail,
    this.shadow,
  });

  final List<Color> colors;
  final bool out;
  final bool tail;
  final Color? shadow;

  static const radius = 17.0;
  static const tailWidth = 6.0;

  /// Outgoing bubbles are the mirrored incoming shape.
  static Path shape(Size size, {required bool tail, required bool out}) {
    const r = radius;
    final w = size.width, h = size.height;
    final left = tail ? tailWidth : 0.0;
    final p = Path()
      ..moveTo(left + r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r));
    if (tail) {
      p
        ..lineTo(3, h)
        ..cubicTo(1.4, h, 0.2, h - 0.6, 0.6, h - 1.6)
        ..cubicTo(left - 1.5, h - 4.5, left, h - 9, left, h - 16)
        ..lineTo(left, r);
    } else {
      p
        ..lineTo(left + r, h)
        ..arcToPoint(Offset(left, h - r), radius: const Radius.circular(r))
        ..lineTo(left, r);
    }
    p
      ..arcToPoint(Offset(left + r, 0), radius: const Radius.circular(r))
      ..close();
    if (!out) return p;
    final mirror = Matrix4.identity()
      ..translateByDouble(w, 0, 0, 1)
      ..scaleByDouble(-1, 1, 1, 1);
    return p.transform(mirror.storage);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape(size, tail: tail, out: out);
    if (shadow != null) {
      canvas.drawPath(
        path.shift(const Offset(0, 0.6)),
        Paint()
          ..color = shadow!
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
      );
    }
    final paint = Paint();
    if (colors.length > 1) {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(Offset.zero & size);
    } else {
      paint.color = colors.first;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(BubblePainter old) =>
      old.colors != colors ||
      old.out != out ||
      old.tail != tail ||
      old.shadow != shadow;
}

class ServicePill extends StatelessWidget {
  const ServicePill(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: c.serviceBubble,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              if (icon != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(icon, size: 13, color: c.serviceText),
                  ),
                ),
              TextSpan(text: text),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.serviceText,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
