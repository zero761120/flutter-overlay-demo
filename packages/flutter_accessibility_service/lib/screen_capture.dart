import 'dart:typed_data';

/// LOCAL PATCH: one frame returned by [FlutterAccessibilityService.takeScreenshot].
///
/// [pixels] is RGBA, 4 bytes per pixel, rows [rowBytes] apart (which can be wider than
/// `width * 4` if the platform pads rows). Size is in physical pixels, not dp.
class ScreenCapture {
  const ScreenCapture({
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.pixels,
  });

  final int width;
  final int height;
  final int rowBytes;
  final Uint8List pixels;

  factory ScreenCapture.fromMap(Map<dynamic, dynamic> map) => ScreenCapture(
        width: map['width'] as int,
        height: map['height'] as int,
        rowBytes: map['rowBytes'] as int,
        pixels: map['pixels'] as Uint8List,
      );
}
