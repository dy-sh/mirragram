import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../tdlib/td_client.dart';

/// Picks the smallest size that still covers [width] logical pixels.
TdObject? photoSizeFor(TdObject photo, double width, double pixelRatio) {
  final sizes = (photo['sizes'] as List? ?? []).cast<TdObject>()
    ..sort((a, b) => (a['width'] as int).compareTo(b['width'] as int));
  if (sizes.isEmpty) return null;
  final needed = width * pixelRatio;
  return sizes.firstWhere(
    (s) => (s['width'] as int) >= needed,
    orElse: () => sizes.last,
  );
}

TdObject? largestPhotoSize(TdObject photo) {
  final sizes = (photo['sizes'] as List? ?? []).cast<TdObject>();
  if (sizes.isEmpty) return null;
  return sizes.reduce(
    (a, b) =>
        (a['width'] as int) * (a['height'] as int) >=
            (b['width'] as int) * (b['height'] as int)
        ? a
        : b,
  );
}

Size photoDisplaySize(TdObject photo, double maxWidth) {
  final size = largestPhotoSize(photo);
  return mediaDisplaySize(
    size?['width'] as int? ?? 1,
    size?['height'] as int? ?? 1,
    maxWidth,
  );
}

/// Display size of media in a bubble, like Telegram: limited width and
/// height, very narrow or wide media are cropped.
Size mediaDisplaySize(int width, int height, double maxWidth) {
  final aspect = math.max(width, 1) / math.max(height, 1);
  var w = maxWidth;
  var h = w / aspect;
  const maxHeight = 420.0, minHeight = 120.0, minWidth = 160.0;
  if (h > maxHeight) {
    h = maxHeight;
    w = math.max(minWidth, h * aspect);
  }
  if (h < minHeight) h = minHeight;
  return Size(w, h);
}

/// A photo from a message: blurred minithumbnail until the file is
/// downloaded. Tapping opens [PhotoViewer].
class MessagePhoto extends StatelessWidget {
  const MessagePhoto({
    super.key,
    required this.photo,
    required this.size,
    this.uploading = false,
  });

  final TdObject photo;
  final Size size;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final file = photoSizeFor(photo, size.width, ratio)?['photo'] as TdObject?;
    final path = tg.localPath(file);
    final mini = photo['minithumbnail'] as TdObject?;

    Widget image;
    if (path != null) {
      image = Image.file(
        File(path),
        width: size.width,
        height: size.height,
        fit: BoxFit.cover,
        cacheWidth: (size.width * ratio).round(),
        gaplessPlayback: true,
      );
    } else if (mini != null) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Image.memory(
          base64.decode(mini['data'] as String),
          width: size.width,
          height: size.height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } else {
      image = const ColoredBox(color: Color(0x33888888));
    }

    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => PhotoViewer(photo: photo),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (path == null || uploading) const Center(child: MediaSpinner()),
          ],
        ),
      ),
    );
  }
}

class MediaSpinner extends StatelessWidget {
  const MediaSpinner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: const BoxDecoration(
      color: Color(0x80000000),
      shape: BoxShape.circle,
    ),
    child: const CupertinoActivityIndicator(color: Color(0xFFFFFFFF)),
  );
}

/// Full-screen photo with pinch and scroll zoom.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.photo});

  final TdObject photo;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final largest = largestPhotoSize(photo)?['photo'] as TdObject?;
    final mini = photo['minithumbnail'] as TdObject?;
    return ListenableBuilder(
      listenable: tg,
      builder: (context, _) {
        final path = tg.localPath(largest);
        final Widget image;
        if (path != null) {
          image = Image.file(File(path), fit: BoxFit.contain);
        } else if (mini != null) {
          image = Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                base64.decode(mini['data'] as String),
                fit: BoxFit.contain,
              ),
              const Center(child: MediaSpinner()),
            ],
          );
        } else {
          image = const Center(child: MediaSpinner());
        }
        return EscapeToClose(
          onEscape: () => Navigator.of(context).pop(),
          child: ColoredBox(
            color: const Color(0xF2000000),
            child: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Center(child: image),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: Color(0xFFFFFFFF),
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Closes a full-screen page with Escape on desktop.
class EscapeToClose extends StatelessWidget {
  const EscapeToClose({super.key, required this.onEscape, required this.child});

  final VoidCallback onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape},
    child: Focus(autofocus: true, child: child),
  );
}
