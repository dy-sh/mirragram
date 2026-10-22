import 'package:flutter/cupertino.dart';

/// Outgoing status: clock (sending), one check (sent), two checks (read).
class ReadChecks extends StatelessWidget {
  const ReadChecks({
    super.key,
    required this.read,
    required this.pending,
    required this.color,
    this.size = 14,
  });

  final bool read;
  final bool pending;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return Icon(CupertinoIcons.clock, size: size - 2, color: color);
    }
    return CustomPaint(
      size: Size(size * 1.3, size * 0.8),
      painter: _ChecksPainter(read: read, color: color),
    );
  }
}

class _ChecksPainter extends CustomPainter {
  _ChecksPainter({required this.read, required this.color});

  final bool read;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final h = size.height;
    final w = h * 1.15;

    void check(double dx, {bool full = true}) {
      final path = Path();
      if (full) {
        path
          ..moveTo(dx, h * 0.55)
          ..lineTo(dx + w * 0.35, h * 0.95);
      } else {
        path.moveTo(dx + w * 0.35, h * 0.95);
      }
      path.lineTo(dx + w, h * 0.05);
      canvas.drawPath(path, paint);
    }

    if (read) {
      check(0);
      check(size.width - w, full: false);
    } else {
      check(size.width - w);
    }
  }

  @override
  bool shouldRepaint(_ChecksPainter old) =>
      old.read != read || old.color != color;
}
