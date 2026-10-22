import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../ui/media/pick_images.dart';
import '../ui/theme/appearance.dart';
import '../ui/theme/palette.dart';

/// Scripted control of demo mode for checking the UI:
///   flutter run -d macos --dart-define=TG_DEMO=true \
///     --dart-define=TG_DEMO_DRIVER=/path/to/dir
///
/// The app reads commands from `cmd` in that directory, one per line, runs
/// them and writes `done`. The directory must be inside the app sandbox.
///   size W H        window size in logical pixels
///   theme NAME      dayClassic | day | night | nightTinted
///   lang CODE       en | ru | system
///   pick P1|P2      files returned by the image picker instead of a dialog
///   tap X Y         tap at a window point
///   scroll X Y DY   mouse wheel scroll
///   wait MS         pause
///   shot NAME       screenshot to NAME.png
class DemoDriver extends StatefulWidget {
  const DemoDriver({
    super.key,
    required this.directory,
    required this.appearance,
    required this.child,
  });

  final String directory;
  final AppearanceController appearance;
  final Widget child;

  @override
  State<DemoDriver> createState() => _DemoDriverState();
}

class _DemoDriverState extends State<DemoDriver> {
  final _boundary = GlobalKey();
  Timer? _timer;
  bool _busy = false;
  static const _window = MethodChannel('tel_client/window');
  var _pointer = 1000;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy) return;
    final cmd = File(p.join(widget.directory, 'cmd'));
    if (!cmd.existsSync()) return;
    _busy = true;
    final log = StringBuffer();
    try {
      final lines = await cmd.readAsLines();
      await cmd.delete();
      for (final line
          in lines.map((l) => l.trim()).where((l) => l.isNotEmpty)) {
        try {
          await _run(line.split(RegExp(r'\s+')));
          log.writeln('ok $line');
        } catch (e) {
          log.writeln('error $line: $e');
        }
      }
    } finally {
      await File(p.join(widget.directory, 'done')).writeAsString('$log');
      _busy = false;
    }
  }

  Future<void> _run(List<String> a) async {
    switch (a[0]) {
      case 'size':
        await _window.invokeMethod('setContentSize', {
          'width': double.parse(a[1]),
          'height': double.parse(a[2]),
        });
        await _frames();
      case 'theme':
        final variant = TgThemeVariant.values.byName(a[1]);
        widget.appearance.selectVariant(
          variant,
          ui.PlatformDispatcher.instance.platformBrightness,
        );
        await _frames();
      case 'pick':
        demoPickedImagePaths = a.sublist(1).join(' ').split('|');
      case 'lang':
        widget.appearance.setLanguage(a[1] == 'system' ? null : a[1]);
        await _frames();
      case 'tap':
        final pos = Offset(double.parse(a[1]), double.parse(a[2]));
        final id = _pointer++;
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(pointer: id, position: pos),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(pointer: id, position: pos),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _frames();
      case 'scroll':
        GestureBinding.instance.handlePointerEvent(
          PointerScrollEvent(
            position: Offset(double.parse(a[1]), double.parse(a[2])),
            scrollDelta: Offset(0, double.parse(a[3])),
          ),
        );
        await _frames();
      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: int.parse(a[1])));
      case 'shot':
        final pixelRatio = View.of(context).devicePixelRatio;
        await _frames();
        final boundary =
            _boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          p.join(widget.directory, '${a[1]}.png'),
        ).writeAsBytes(png!.buffer.asUint8List());
      default:
        throw ArgumentError('unknown command');
    }
  }

  Future<void> _frames() async {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _boundary, child: widget.child);
}
