import 'dart:io';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

class PickedImage {
  const PickedImage(this.path, this.width, this.height, this.bytes);

  final String path;
  final int width;
  final int height;
  final int bytes;
}

/// Telegram's limit for photos; larger images must be sent as files.
const maxPhotoBytes = 10 * 1024 * 1024;

/// Demo mode sets this to bypass the system file dialog.
List<String>? debugPickedImagePaths;

Future<List<PickedImage>> pickImages() async {
  final List<String> paths;
  if (debugPickedImagePaths != null) {
    paths = debugPickedImagePaths!;
  } else {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 90,
    );
    paths = [for (final f in files) f.path];
  }
  return [for (final path in paths) ?await _describe(path)];
}

Future<PickedImage?> _describe(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final image = PickedImage(
      path,
      descriptor.width,
      descriptor.height,
      bytes.length,
    );
    descriptor.dispose();
    buffer.dispose();
    return image;
  } catch (_) {
    return null;
  }
}
