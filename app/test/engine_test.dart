import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bullseye/engine/decode.dart';
import 'package:bullseye/engine/imaging.dart';
import 'package:bullseye/engine/pipeline.dart';
import 'package:bullseye/engine/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ellipszisillesztés szintetikus pontokra', () {
    final xs = <double>[], ys = <double>[];
    const a = 120.0, b = 90.0, ang = 0.4, cx = 300.0, cy = 250.0;
    for (var i = 0; i < 200; i++) {
      final t = i * 2 * math.pi / 200;
      final u = a * math.cos(t), v = b * math.sin(t);
      xs.add(cx + u * math.cos(ang) - v * math.sin(ang));
      ys.add(cy + u * math.sin(ang) + v * math.cos(ang));
    }
    final e = fitEllipse(xs, ys)!;
    expect(e.cx, closeTo(cx, 1e-6));
    expect(e.cy, closeTo(cy, 1e-6));
    for (var i = 0; i < 200; i++) {
      expect(e.residual(xs[i], ys[i]), lessThan(1e-6));
    }
  });

  test('vonalérintési szabály', () {
    const s = TargetSpec.mdlszGyorspont;
    final rp = s.pelletRadius;
    expect(s.scoreForDistance(1 + rp), 13);
    expect(s.scoreForDistance(1 + rp + 0.01), 12);
    expect(s.scoreForDistance(6 + rp * 0.9), 8);
  });

  final gtFile = File('../testdata/ground_truth.json');
  final gt = jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>;
  for (final name in gt.keys.toList()..sort()) {
    test('tesztfotó $name: ±1 pont a kézi kiértékeléshez képest', () {
      final g = gt[name] as Map<String, dynamic>;
      final (rgb, scale) = decodeForEngine(File('../testdata/$name').readAsBytesSync());
      final sw = Stopwatch()..start();
      final res = analyze(rgb, TargetSpec.mdlszGyorspont, expected: g['shot_count'] as int);
      // ignore: avoid_print
      print('$name: ${res.total} (kézi ${g['total']}), ${res.shots.length} lövés, '
          '${res.shots.where((s) => s.flagged).length} jelölt, ${sw.elapsedMilliseconds} ms');
      expect(res.shots.length, g['shot_count']);
      expect((res.total - (g['total'] as int)).abs(), lessThanOrEqualTo(1));
      // minden kézi lövéshez van közeli találat, és ha a pont eltér, jelölt
      final shots = (g['shots'] as List).cast<Map<String, dynamic>>();
      var wrongUnflagged = 0;
      for (final t in shots) {
        final tx = (t['x'] as num).toDouble() / scale, ty = (t['y'] as num).toDouble() / scale;
        DetectedShot? best;
        var bd = double.infinity;
        for (final s in res.shots) {
          final d = math.sqrt((s.x - tx) * (s.x - tx) + (s.y - ty) * (s.y - ty));
          if (d < bd) {
            bd = d;
            best = s;
          }
        }
        expect(bd, lessThan(res.geometry.pxPerSpacingOrig * 0.7));
        if (best!.score.score != t['score'] && !best.flagged) wrongUnflagged++;
      }
      expect(wrongUnflagged, lessThanOrEqualTo(1));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
