import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app.dart';
import '../../tdlib/td_client.dart';
import 'palette.dart';

@immutable
sealed class WallpaperFill {
  const WallpaperFill();

  static WallpaperFill fromTd(TdObject fill) => switch (fill['@type']) {
    'backgroundFillSolid' => SolidFill(_color(fill['color'])),
    'backgroundFillGradient' => LinearFill(
      _color(fill['top_color']),
      _color(fill['bottom_color']),
      fill['rotation_angle'] as int? ?? 0,
    ),
    'backgroundFillFreeformGradient' => FreeformFill([
      for (final c in fill['colors'] as List) _color(c),
    ]),
    _ => const SolidFill(Color(0xFFFFFFFF)),
  };

  TdObject toTd();

  Color get average;

  static Color _color(Object? v) => Color(0xFF000000 | ((v as int) & 0xFFFFFF));
  static int _int(Color c) => c.toARGB32() & 0xFFFFFF;
}

class SolidFill extends WallpaperFill {
  const SolidFill(this.color);

  final Color color;

  @override
  Color get average => color;

  @override
  TdObject toTd() => {
    '@type': 'backgroundFillSolid',
    'color': WallpaperFill._int(color),
  };

  @override
  bool operator ==(Object other) => other is SolidFill && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

class LinearFill extends WallpaperFill {
  const LinearFill(this.top, this.bottom, this.rotation);

  final Color top;
  final Color bottom;

  /// Degrees clockwise; 0 is top to bottom.
  final int rotation;

  @override
  Color get average => Color.lerp(top, bottom, 0.5)!;

  @override
  TdObject toTd() => {
    '@type': 'backgroundFillGradient',
    'top_color': WallpaperFill._int(top),
    'bottom_color': WallpaperFill._int(bottom),
    'rotation_angle': rotation,
  };

  Gradient get gradient {
    final a = rotation * math.pi / 180;
    final dir = Alignment(-math.sin(a), math.cos(a));
    return LinearGradient(
      begin: Alignment(-dir.x, -dir.y),
      end: dir,
      colors: [top, bottom],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LinearFill &&
      other.top == top &&
      other.bottom == bottom &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(top, bottom, rotation);
}

class FreeformFill extends WallpaperFill {
  const FreeformFill(this.colors);

  final List<Color> colors;

  @override
  Color get average {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final c in colors) {
      r += c.r;
      g += c.g;
      b += c.b;
    }
    final n = colors.length;
    return Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
  }

  @override
  TdObject toTd() => {
    '@type': 'backgroundFillFreeformGradient',
    'colors': [for (final c in colors) WallpaperFill._int(c)],
  };

  @override
  bool operator ==(Object other) =>
      other is FreeformFill &&
      other.colors.length == colors.length &&
      List.generate(
        colors.length,
        (i) => other.colors[i] == colors[i],
      ).every((x) => x);

  @override
  int get hashCode => Object.hashAll(colors);
}

@immutable
class WallpaperSpec {
  const WallpaperSpec({
    required this.key,
    this.fill,
    this.backgroundId,
    this.name,
    this.patternFile,
    this.patternName,
    this.intensity = 0,
    this.inverted = false,
    this.imageFile,
    this.thumbnailFile,
    this.blurred = false,
  });

  final String key;
  final WallpaperFill? fill;

  final int? backgroundId;
  final String? name;

  /// Pattern file (.tgv, gzipped SVG).
  final TdObject? patternFile;

  /// Pattern to look up by name (built-in wallpapers).
  final String? patternName;
  final int intensity;
  final bool inverted;

  final TdObject? imageFile;
  final TdObject? thumbnailFile;
  final bool blurred;

  bool get hasPattern => patternFile != null || patternName != null;

  static const classic = WallpaperSpec(
    key: 'builtin:classic',
    fill: FreeformFill([
      Color(0xFFDBDDBB),
      Color(0xFF6BA587),
      Color(0xFFD5D88D),
      Color(0xFF88B884),
    ]),
    patternName: defaultPatternName,
    intensity: 50,
  );

  static const white = WallpaperSpec(
    key: 'builtin:white',
    fill: SolidFill(Color(0xFFFFFFFF)),
  );

  static const nightDefault = WallpaperSpec(
    key: 'builtin:night',
    fill: FreeformFill([
      Color(0xFF6A5BD8),
      Color(0xFF3F6FDD),
      Color(0xFF8B5ACF),
      Color(0xFF3A86D6),
    ]),
    patternName: defaultPatternName,
    intensity: -50,
    inverted: true,
  );

  static const nightTintedDefault = WallpaperSpec(
    key: 'builtin:night_tinted',
    fill: SolidFill(Color(0xFF0E1621)),
  );

  static const defaultPatternName = 'fqv01SQemVIBAAAApND8LDRUhRU';

  static const builtinFills = <WallpaperFill>[
    FreeformFill([
      Color(0xFFDBDDBB),
      Color(0xFF6BA587),
      Color(0xFFD5D88D),
      Color(0xFF88B884),
    ]),
    FreeformFill([
      Color(0xFF8DC0EB),
      Color(0xFFB9D1EA),
      Color(0xFFC6B1EF),
      Color(0xFFEBD7EF),
    ]),
    FreeformFill([
      Color(0xFF97BEEB),
      Color(0xFFB1E9EA),
      Color(0xFFC6B1EF),
      Color(0xFFEFB7DC),
    ]),
    FreeformFill([
      Color(0xFFE4B2EA),
      Color(0xFF8376C2),
      Color(0xFFEAB9D9),
      Color(0xFFB493E6),
    ]),
    FreeformFill([
      Color(0xFFFEC496),
      Color(0xFFDD6CB9),
      Color(0xFF962FBF),
      Color(0xFF4F5BD5),
    ]),
    FreeformFill([
      Color(0xFFEAA36E),
      Color(0xFFF0E486),
      Color(0xFFF29EBF),
      Color(0xFFE8C06E),
    ]),
    SolidFill(Color(0xFFFFFFFF)),
    SolidFill(Color(0xFFD4DFEA)),
    SolidFill(Color(0xFFB2CEE1)),
    SolidFill(Color(0xFFC7E3C2)),
    SolidFill(Color(0xFFF1E4B5)),
    SolidFill(Color(0xFFEAC3C7)),
    SolidFill(Color(0xFF0E1621)),
    SolidFill(Color(0xFF1C1C1D)),
    SolidFill(Color(0xFF000000)),
  ];

  static WallpaperSpec fromFill(WallpaperFill fill) =>
      WallpaperSpec(key: _fillKey(fill), fill: fill);

  static String _fillKey(WallpaperFill fill) =>
      'fill:${jsonEncode(fill.toTd())}';

  /// Returns null for unsupported types (chat themes).
  static WallpaperSpec? fromTd(TdObject? bg) {
    if (bg == null) return null;
    final type = bg['type'] as TdObject;
    final document = (bg['document'] as TdObject?);
    final file = document?['document'] as TdObject?;
    final thumb = (document?['thumbnail'] as TdObject?)?['file'] as TdObject?;
    final id = int.tryParse('${bg['id']}');
    final key = 'bg:${bg['id']}';
    switch (type['@type']) {
      case 'backgroundTypeFill':
        final fill = WallpaperFill.fromTd(type['fill'] as TdObject);
        return WallpaperSpec(
          key: _fillKey(fill),
          backgroundId: id,
          name: bg['name'] as String?,
          fill: fill,
        );
      case 'backgroundTypePattern':
        final intensity = type['intensity'] as int? ?? 50;
        final inverted = type['is_inverted'] == true;
        final fill = WallpaperFill.fromTd(type['fill'] as TdObject);
        return WallpaperSpec(
          key: '$key:${_fillKey(fill)}:$intensity',
          backgroundId: id,
          name: bg['name'] as String?,
          fill: fill,
          patternFile: file,
          intensity: inverted ? -intensity.abs() : intensity,
          inverted: inverted,
        );
      case 'backgroundTypeWallpaper':
        return WallpaperSpec(
          key: key,
          backgroundId: id,
          name: bg['name'] as String?,
          imageFile: file,
          thumbnailFile: thumb,
          blurred: type['is_blurred'] == true,
        );
      default:
        return null;
    }
  }

  TdObject? get tdType {
    if (imageFile != null) {
      return {
        '@type': 'backgroundTypeWallpaper',
        'is_blurred': blurred,
        'is_moving': false,
      };
    }
    if (fill == null) return null;
    if (patternFile != null) {
      return {
        '@type': 'backgroundTypePattern',
        'fill': fill!.toTd(),
        'intensity': intensity.abs(),
        'is_inverted': inverted,
        'is_moving': false,
      };
    }
    return {'@type': 'backgroundTypeFill', 'fill': fill!.toTd()};
  }

  @override
  bool operator ==(Object other) => other is WallpaperSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class WallpaperView extends StatelessWidget {
  const WallpaperView(
    this.spec, {
    super.key,
    this.thumbnail = false,
    this.dimming = 0,
  });

  final WallpaperSpec spec;

  final bool thumbnail;

  /// 0–100, for chat backgrounds in dark themes.
  final int dimming;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final patternFile = spec.patternFile ?? _resolvedPatterns[spec.patternName];
    return ListenableBuilder(
      listenable: tg,
      builder: (context, _) {
        final imageFile = thumbnail && spec.thumbnailFile != null
            ? spec.thumbnailFile
            : spec.imageFile;
        return RepaintBoundary(
          child: _WallpaperLayers(
            fill: spec.fill,
            patternPath: tg.localPath(patternFile),
            intensity: spec.intensity,
            inverted: spec.inverted,
            imagePath: tg.localPath(imageFile),
            blurred: spec.blurred,
            dimming: dimming,
          ),
        );
      },
    );
  }

  static final _resolvedPatterns = <String?, TdObject>{};

  static void registerPattern(String name, TdObject file) =>
      _resolvedPatterns[name] = file;
}

class _WallpaperLayers extends StatefulWidget {
  const _WallpaperLayers({
    required this.fill,
    required this.patternPath,
    required this.intensity,
    required this.inverted,
    required this.imagePath,
    required this.blurred,
    required this.dimming,
  });

  final WallpaperFill? fill;
  final String? patternPath;
  final int intensity;
  final bool inverted;
  final String? imagePath;
  final bool blurred;
  final int dimming;

  @override
  State<_WallpaperLayers> createState() => _WallpaperLayersState();
}

class _WallpaperLayersState extends State<_WallpaperLayers> {
  ui.Image? _gradient;
  PictureInfo? _pattern;
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_WallpaperLayers old) {
    super.didUpdateWidget(old);
    if (old.fill != widget.fill ||
        old.patternPath != widget.patternPath ||
        old.imagePath != widget.imagePath) {
      _load();
    }
  }

  Future<void> _load() async {
    final fill = widget.fill;
    final patternPath = widget.patternPath;
    final imagePath = widget.imagePath;
    final gradient = fill is FreeformFill
        ? await FreeformGradient.image(fill.colors)
        : null;
    final pattern = patternPath == null
        ? null
        : await PatternCache.load(patternPath);
    final image = imagePath == null ? null : await _ImageCache.load(imagePath);
    if (!mounted ||
        fill != widget.fill ||
        patternPath != widget.patternPath ||
        imagePath != widget.imagePath) {
      return;
    }
    setState(() {
      _gradient = gradient;
      _pattern = pattern;
      _image = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _WallpaperPainter(
        fill: widget.fill,
        gradient: _gradient,
        pattern: _pattern,
        intensity: widget.intensity,
        inverted: widget.inverted,
        image: _image,
        blurred: widget.blurred,
        dimming: widget.dimming,
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter({
    required this.fill,
    required this.gradient,
    required this.pattern,
    required this.intensity,
    required this.inverted,
    required this.image,
    required this.blurred,
    required this.dimming,
  });

  final WallpaperFill? fill;
  final ui.Image? gradient;
  final PictureInfo? pattern;
  final int intensity;
  final bool inverted;
  final ui.Image? image;
  final bool blurred;
  final int dimming;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);

    if (image != null) {
      _drawCover(
        canvas,
        rect,
        image!,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = blurred
              ? ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12)
              : null,
      );
    } else if (inverted && pattern != null) {
      // Inverted pattern: the gradient shows only through the pattern.
      canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
      canvas.saveLayer(rect, Paint());
      _drawPattern(canvas, size, Paint());
      _drawFill(
        canvas,
        rect,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..color = Color.fromRGBO(0, 0, 0, intensity.abs() / 100),
      );
      canvas.restore();
    } else if (inverted) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
    } else {
      _drawFill(canvas, rect, Paint());
      if (pattern != null && fill != null) {
        final alpha = intensity.abs() / 100;
        final Paint layer;
        if (fill is FreeformFill) {
          layer = Paint()
            ..blendMode = BlendMode.softLight
            ..colorFilter = ColorFilter.mode(
              Color.fromRGBO(0, 0, 0, alpha),
              BlendMode.srcIn,
            );
        } else {
          final c = patternColor(fill!.average);
          layer = Paint()
            ..colorFilter = ColorFilter.mode(
              c.withValues(alpha: c.a * alpha * 2.5),
              BlendMode.srcIn,
            );
        }
        canvas.saveLayer(rect, layer);
        _drawPattern(canvas, size, Paint());
        canvas.restore();
      }
    }

    if (dimming > 0) {
      canvas.drawRect(
        rect,
        Paint()..color = Color.fromRGBO(0, 0, 0, dimming / 100),
      );
    }
  }

  void _drawFill(Canvas canvas, Rect rect, Paint paint) {
    switch (fill) {
      case SolidFill(:final color):
        canvas.drawRect(
          rect,
          paint..color = color.withValues(alpha: paint.color.a),
        );
      case final LinearFill f:
        canvas.drawRect(rect, paint..shader = f.gradient.createShader(rect));
      case final FreeformFill f:
        if (gradient != null) {
          canvas.drawImageRect(
            gradient!,
            Offset.zero &
                Size(gradient!.width.toDouble(), gradient!.height.toDouble()),
            rect,
            paint..filterQuality = FilterQuality.high,
          );
        } else {
          canvas.drawRect(
            rect,
            paint..color = f.average.withValues(alpha: paint.color.a),
          );
        }
      case null:
        canvas.drawRect(rect, paint..color = const Color(0xFFFFFFFF));
    }
  }

  /// Fits the pattern to the height and tiles it horizontally.
  void _drawPattern(Canvas canvas, Size size, Paint paint) {
    final p = pattern!;
    if (p.size.isEmpty) return;
    final scale = math.max(size.height / p.size.height, 0.25);
    final tileW = p.size.width * scale;
    final count = (size.width / tileW).ceil();
    final startX = (size.width - count * tileW) / 2;
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.translate(startX + i * tileW, 0);
      canvas.scale(scale);
      canvas.drawPicture(p.picture);
      canvas.restore();
    }
  }

  static void _drawCover(Canvas canvas, Rect rect, ui.Image img, Paint paint) {
    final src = Size(img.width.toDouble(), img.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, src, rect.size);
    final srcRect = Alignment.center.inscribe(fitted.source, Offset.zero & src);
    canvas.drawImageRect(img, srcRect, rect, paint);
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) =>
      old.fill != fill ||
      old.gradient != gradient ||
      old.pattern != pattern ||
      old.intensity != intensity ||
      old.inverted != inverted ||
      old.image != image ||
      old.blurred != blurred ||
      old.dimming != dimming;
}

/// Pattern color over a plain fill, as Telegram computes it.
Color patternColor(Color color) {
  final hsv = HSVColor.fromColor(color);
  var s = hsv.saturation;
  var v = hsv.value;
  if (s > 0 || (v < 1 && v > 0)) {
    s = math.min(1, s + 0.05 + 0.1 * (1 - s));
  }
  v = v > 0.5 ? math.max(0, v * 0.65) : math.max(0, math.min(1, 1 - v * 0.65));
  return hsv.withSaturation(s).withValue(v).toColor().withValues(alpha: 0.4);
}

/// Telegram's freeform gradient: a 60×60 image scaled up with smoothing.
abstract final class FreeformGradient {
  static const _positions = [
    Offset(0.80, 0.10),
    Offset(0.35, 0.25),
    Offset(0.20, 0.90),
    Offset(0.65, 0.75),
  ];
  static const _size = 60;
  static final _cache = <int, Future<ui.Image>>{};

  static Future<ui.Image> image(List<Color> colors) =>
      _cache[Object.hashAll(colors)] ??= _render(colors);

  static Uint8List pixels(List<Color> colors) {
    final points = colors.length == 3
        ? _positions.take(3).toList()
        : (colors.length == 2
              ? const [Offset(0.5, 0.0), Offset(0.5, 1.0)]
              : _positions);
    final n = math.min(points.length, colors.length);
    final out = Uint8List(_size * _size * 4);
    var o = 0;
    for (var y = 0; y < _size; y++) {
      final py = y / _size;
      final cy = py - 0.5;
      for (var x = 0; x < _size; x++) {
        final px = x / _size;
        final cx = px - 0.5;
        final dist = math.sqrt(cx * cx + cy * cy);
        final swirl = 0.35 * dist;
        final theta = swirl * swirl * 0.8 * 8.0;
        final sinT = math.sin(theta), cosT = math.cos(theta);
        final sx = (0.5 + cx * cosT - cy * sinT).clamp(0.0, 1.0);
        final sy = (0.5 + cx * sinT + cy * cosT).clamp(0.0, 1.0);

        var sum = 0.0, r = 0.0, g = 0.0, b = 0.0;
        for (var i = 0; i < n; i++) {
          final dx = sx - points[i].dx;
          final dy = sy - points[i].dy;
          var d = math.max(0.0, 0.9 - math.sqrt(dx * dx + dy * dy));
          d = d * d * d * d;
          sum += d;
          r += d * colors[i].r;
          g += d * colors[i].g;
          b += d * colors[i].b;
        }
        if (sum == 0) sum = 1;
        out[o++] = (r / sum * 255).round().clamp(0, 255);
        out[o++] = (g / sum * 255).round().clamp(0, 255);
        out[o++] = (b / sum * 255).round().clamp(0, 255);
        out[o++] = 255;
      }
    }
    return out;
  }

  static Future<ui.Image> _render(List<Color> colors) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels(colors));
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _size,
      height: _size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

abstract final class PatternCache {
  static final _cache = <String, Future<PictureInfo?>>{};

  static Future<PictureInfo?> load(String path) =>
      _cache[path] ??= _load(path).whenComplete(() => _trim(_cache));

  static Future<PictureInfo?> _load(String path) async {
    try {
      var bytes = await File(path).readAsBytes();
      if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      return await vg.loadPicture(SvgBytesLoader(bytes), null);
    } catch (_) {
      return null;
    }
  }
}

abstract final class _ImageCache {
  static final _cache = <String, Future<ui.Image?>>{};

  static Future<ui.Image?> load(String path) =>
      _cache[path] ??= _load(path).whenComplete(() => _trim(_cache));

  static Future<ui.Image?> _load(String path) async {
    try {
      final codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
        targetWidth: 1600,
        allowUpscaling: false,
      );
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }
}

/// The chat's own wallpaper if it has one, otherwise the theme wallpaper.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.colors, this.chat});

  final TgColors colors;
  final TdObject? chat;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.tg, scope.appearance]),
      builder: (context, _) {
        final own = chat?['background'] as TdObject?;
        final ownSpec = WallpaperSpec.fromTd(own?['background'] as TdObject?);
        if (ownSpec != null) {
          return WallpaperView(
            ownSpec,
            dimming: colors.isDark
                ? own!['dark_theme_dimming'] as int? ?? 0
                : 0,
          );
        }
        return WallpaperView(scope.appearance.wallpaper(colors));
      },
    );
  }
}

/// Keeps the wallpaper caches small: thumbnails of many wallpapers are
/// loaded while browsing, but only a few are shown at once.
void _trim(Map<String, Object?> cache) {
  while (cache.length > 24) {
    cache.remove(cache.keys.first);
  }
}
