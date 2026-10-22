import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../e2e/e2e_service.dart';
import '../../tdlib/td_client.dart';
import '../format.dart';
import '../tg_theme.dart';
import 'read_checks.dart';
import '../../l10n/l10n.dart';

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

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (encrypted)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(CupertinoIcons.lock_fill, size: 10, color: metaColor),
          ),
        if (edited)
          Text(
            context.l10n.edited,
            style: TextStyle(
              fontSize: 11,
              color: metaColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        Text(
          hhmm(fromUnix(message['date'] as int)),
          style: TextStyle(fontSize: 11, color: metaColor),
        ),
        if (_out) ...[
          const SizedBox(width: 3),
          ReadChecks(
            read: read,
            pending: message['sending_state'] != null,
            color: metaColor,
            size: 12,
          ),
        ],
      ],
    );
    // Space reserved for the time at the end of the last line.
    final metaReserve =
        40.0 + (_out ? 18 : 0) + (encrypted ? 13 : 0) + (edited ? 28 : 0);

    final (text, style) = _body(context, c, textSize);

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
          constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 60),
          child: Padding(
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
                    if (senderName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(
                          senderName!,
                          style: TextStyle(
                            fontSize: textSize - 2,
                            fontWeight: FontWeight.w600,
                            color: senderColor,
                          ),
                        ),
                      ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: text, style: style),
                          WidgetSpan(
                            child: SizedBox(width: metaReserve, height: 14),
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
