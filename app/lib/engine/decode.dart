// Képfájl beolvasása és előkészítése a motorhoz (package:image).
import 'dart:typed_data';

import 'package:image/image.dart' as im;

import 'imaging.dart';
import 'pipeline.dart' show kMaxSide;

/// Dekódolja a képet, alkalmazza az EXIF-forgatást, és ha kell, kicsinyíti.
/// Visszaadja az RGB képet és a kicsinyítés arányát (eredeti/feldolgozott).
(Rgb, double) decodeForEngine(Uint8List bytes) {
  var image = im.decodeImage(bytes);
  if (image == null) throw const FormatException('A kép nem olvasható.');
  image = im.bakeOrientation(image);
  var scale = 1.0;
  final long = image.width > image.height ? image.width : image.height;
  if (long > kMaxSide) {
    scale = long / kMaxSide;
    image = im.copyResize(image,
        width: (image.width / scale).round(),
        height: (image.height / scale).round(),
        interpolation: im.Interpolation.average);
  }
  final w = image.width, h = image.height;
  final out = Uint8List(w * h * 3);
  var j = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      out[j++] = p.r.toInt();
      out[j++] = p.g.toInt();
      out[j++] = p.b.toInt();
    }
  }
  return (Rgb(w, h, out), scale);
}
