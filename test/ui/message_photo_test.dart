import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tel_client/ui/widgets/message_photo.dart';

Map<String, dynamic> _size(String type, int w, int h) => {
  '@type': 'photoSize',
  'type': type,
  'photo': {'@type': 'file', 'id': w},
  'width': w,
  'height': h,
};

void main() {
  final photo = {
    '@type': 'photo',
    'sizes': [
      _size('y', 1280, 960),
      _size('m', 320, 240),
      _size('x', 800, 600),
    ],
  };

  test('picks the smallest size that covers the display width', () {
    expect(photoSizeFor(photo, 300, 2)?['type'], 'x');
    expect(photoSizeFor(photo, 150, 2)?['type'], 'm');
    expect(photoSizeFor(photo, 1000, 2)?['type'], 'y');
  });

  test('largest size is used for the full-screen viewer', () {
    expect(largestPhotoSize(photo)?['type'], 'y');
  });

  test('tall photos are limited in height, wide ones are cropped', () {
    final tall = {
      'sizes': [_size('y', 600, 3000)],
    };
    final wide = {
      'sizes': [_size('y', 3000, 300)],
    };
    expect(photoDisplaySize(photo, 320), const Size(320, 240));
    expect(photoDisplaySize(tall, 320).height, 420);
    expect(photoDisplaySize(tall, 320).width, 160);
    expect(photoDisplaySize(wide, 320), const Size(320, 120));
  });
}
