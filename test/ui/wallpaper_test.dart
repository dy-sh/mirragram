import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirragram/ui/theme/wallpaper.dart';

void main() {
  test('parses a TDLib pattern with a freeform gradient', () {
    final spec = WallpaperSpec.fromTd({
      '@type': 'background',
      'id': '5947530738516623361',
      'name': 'fqv01SQemVIBAAAApND8LDRUhRU',
      'document': {
        '@type': 'document',
        'document': {'@type': 'file', 'id': 7},
      },
      'type': {
        '@type': 'backgroundTypePattern',
        'fill': {
          '@type': 'backgroundFillFreeformGradient',
          'colors': [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884],
        },
        'intensity': 50,
        'is_inverted': true,
        'is_moving': false,
      },
    })!;
    expect(spec.backgroundId, 5947530738516623361);
    expect(spec.inverted, isTrue);
    expect(spec.intensity, -50);
    expect(spec.patternFile?['id'], 7);
    expect((spec.fill! as FreeformFill).colors.first, const Color(0xFFDBDDBB));
    expect(spec.tdType?['@type'], 'backgroundTypePattern');
    expect(spec.tdType?['intensity'], 50);
  });

  test(
    'the same fill from TDLib and from built-in colors is one wallpaper',
    () {
      const fill = SolidFill(Color(0xFFC7E3C2));
      final fromTd = WallpaperSpec.fromTd({
        '@type': 'background',
        'id': '1',
        'type': {'@type': 'backgroundTypeFill', 'fill': fill.toTd()},
      });
      expect(fromTd, WallpaperSpec.fromFill(fill));
    },
  );

  test('chat themes are not supported', () {
    expect(
      WallpaperSpec.fromTd({
        '@type': 'background',
        'id': '1',
        'type': {'@type': 'backgroundTypeChatTheme', 'theme_name': '🏠'},
      }),
      isNull,
    );
  });

  test('freeform gradient: colors sit at their anchor points', () {
    const colors = [
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
      Color(0xFFFFFF00),
    ];
    final px = FreeformGradient.pixels(colors);
    expect(px.length, 60 * 60 * 4);
    // The top right corner is closest to the first point (0.8, 0.1).
    final i = (3 * 60 + 50) * 4;
    expect(px[i], greaterThan(px[i + 1]));
    expect(px[i], greaterThan(px[i + 2]));
  });
}
