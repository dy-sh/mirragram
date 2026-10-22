import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilgram/ui/widgets/message_photo.dart';
import 'package:veilgram/ui/widgets/message_video.dart';

void main() {
  test('durations are formatted like Telegram', () {
    expect(formatDuration(5), '0:05');
    expect(formatDuration(83), '1:23');
    expect(formatDuration(3725), '1:02:05');
  });

  test('16:9 video fits the bubble width', () {
    expect(mediaDisplaySize(1280, 720, 320), const Size(320, 180));
  });

  test('missing dimensions do not break layout', () {
    final size = mediaDisplaySize(0, 0, 320);
    expect(size.width, 320);
    expect(size.height, greaterThan(0));
  });
}
