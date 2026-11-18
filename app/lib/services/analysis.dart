// A képfeldolgozás háttérszálon (isolate) fut, hogy a felület ne akadjon.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as im;

import '../engine/calibrate.dart';
import '../engine/decode.dart';
import '../engine/pipeline.dart';
import '../engine/target.dart';

class AnalysisOutput {
  final Uint8List jpeg; // a feldolgozott kép (ehhez tartoznak a koordináták)
  final int width, height;
  final Map<String, dynamic>? geometry;
  final List<Map<String, dynamic>> shots; // x, y, uncertain, note
  final String? error; // kalibrálási hiba szövege
  AnalysisOutput(this.jpeg, this.width, this.height, this.geometry, this.shots, this.error);
}

Future<AnalysisOutput> analyzeInBackground(Uint8List bytes, TargetSpec spec, int expected) {
  return Isolate.run(() {
    final (rgb, _) = decodeForEngine(bytes);
    final img = im.Image.fromBytes(width: rgb.w, height: rgb.h, bytes: rgb.d.buffer, numChannels: 3);
    final jpeg = Uint8List.fromList(im.encodeJpg(img, quality: 90));
    try {
      final res = analyze(rgb, spec, expected: expected);
      return AnalysisOutput(
        jpeg,
        rgb.w,
        rgb.h,
        res.geometry.toJson(),
        [
          for (final s in res.shots)
            {'x': s.x, 'y': s.y, 'uncertain': s.uncertain, 'note': s.reason}
        ],
        null,
      );
    } on CalibrationException catch (e) {
      return AnalysisOutput(jpeg, rgb.w, rgb.h, null, const [], e.message);
    }
  });
}
