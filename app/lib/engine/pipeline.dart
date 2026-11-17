// Teljes kiértékelés: kép -> lövések, pontok, jelzések.
//
// A [TargetGeometry] a kalibráció eredménye, ami elmenthető: ezzel a kézi
// javításnál (húzás, új lövés) a felhasználó által megadott pont is azonnal
// pontozható, újabb képfeldolgozás nélkül.
import 'dart:math' as math;

import 'calibrate.dart';
import 'detect.dart';
import 'imaging.dart';
import 'rings.dart';
import 'split.dart';
import 'target.dart';

class ShotScore {
  final int score;
  final double gapMm; // a lövedék széle ennyire van a magasabb gyűrűtől
  final double depthMm; // ennyivel nyúlik be a saját gyűrűjébe
  final bool borderline;
  final String note;
  final double dxMm; // jobbra +
  final double dyMm; // felfelé +
  const ShotScore(this.score, this.gapMm, this.depthMm, this.borderline, this.note, this.dxMm, this.dyMm);
}

class TargetGeometry {
  final TargetSpec spec;
  final Affine toCanon;
  final Map<int, RingFit> ringFits;
  final double spacing; // kiegyenesített px / gyűrűtávolság
  final double pxPerSpacingOrig; // eredeti px / gyűrűtávolság (közelítő)
  late final RingModel _rm = RingModel.fromFits(ringFits, spacing, spec);
  late final Affine _toOrig = toCanon.inverse();

  TargetGeometry(this.spec, this.toCanon, this.ringFits, this.spacing, this.pxPerSpacingOrig);

  double get mmPerCanonPx => spec.ringSpacingMm / spacing;

  /// Lövedéksugár az eredeti képen (rajzoláshoz).
  double get pelletRadiusOrig => spec.pelletRadius * pxPerSpacingOrig;

  /// A célközéppont az eredeti képen.
  (double, double) get centerOrig {
    final (cx, cy, _) = _rm.ringCircle(spec.ringCount);
    return _toOrig.apply(cx, cy);
  }

  /// A k gyűrű köre az eredeti képen közelítő középponttal és sugárral.
  (double, double, double) ringOrig(int k) {
    final (cx, cy, r) = _rm.ringCircle(k);
    final (ox, oy) = _toOrig.apply(cx, cy);
    return (ox, oy, r / spacing * pxPerSpacingOrig);
  }

  ShotScore scoreOrig(double x, double y) {
    final (cx, cy) = toCanon.apply(x, y);
    return scoreCanon(cx, cy);
  }

  ShotScore scoreCanon(double x, double y) {
    final rp = spec.pelletRadius * spacing + spec.edgeToleranceMm / spec.ringSpacingMm * spacing;
    final thr = spec.lineTouchCountsHigher ? rp : 0.0;
    var best = 0;
    for (var k = spec.ringCount; k >= 1; k--) {
      if (_rm.signedDistToRing(x, y, k) <= thr) {
        best = k;
        break;
      }
    }
    final mm = mmPerCanonPx;
    final depthMm = best > 0 ? (thr - _rm.signedDistToRing(x, y, best)) * mm : 1e9;
    final gapMm = best == spec.ringCount ? 0.0 : math.max(0.0, _rm.signedDistToRing(x, y, best + 1) - thr) * mm;
    final nearHi = best < spec.ringCount && gapMm <= spec.borderlineMm;
    final nearLo = best > 0 && depthMm <= spec.borderlineMm / 2;
    final notes = <String>[];
    if (nearHi) notes.add('${_fmt(gapMm)} mm-re a ${best + 1}-es gyűrűtől');
    if (nearLo) notes.add('csak ${_fmt(depthMm)} mm-rel érinti a $best-es gyűrűt');
    final (ccx, ccy, _) = _rm.ringCircle(spec.ringCount);
    return ShotScore(best, gapMm, depthMm, nearHi || nearLo, notes.join('; '),
        (x - ccx) * mm, -(y - ccy) * mm);
  }

  Map<String, dynamic> toJson() => {
        'target': spec.id,
        'toCanon': toCanon.toList(),
        'spacing': spacing,
        'pxPerSpacingOrig': pxPerSpacingOrig,
        'rings': {
          for (final e in ringFits.entries)
            '${e.key}': [e.value.cx, e.value.cy, e.value.r, e.value.n, e.value.halfWidth]
        },
      };

  static TargetGeometry fromJson(Map<String, dynamic> j, {TargetSpec? spec}) {
    final rings = <int, RingFit>{};
    (j['rings'] as Map).forEach((k, v) {
      final l = v as List;
      rings[int.parse(k as String)] = RingFit((l[0] as num).toDouble(), (l[1] as num).toDouble(),
          (l[2] as num).toDouble(), (l[3] as num).toInt(), (l[4] as num).toDouble());
    });
    return TargetGeometry(spec ?? TargetSpec.byId(j['target'] as String), Affine.fromList(j['toCanon'] as List),
        rings, (j['spacing'] as num).toDouble(), (j['pxPerSpacingOrig'] as num).toDouble());
  }
}

String _fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

class DetectedShot {
  final double x, y; // eredeti kép px
  final ShotScore score;
  final bool uncertain;
  final String note;
  DetectedShot(this.x, this.y, this.score, this.uncertain, this.note);
  bool get flagged => uncertain || score.borderline;
}

class AnalysisResult {
  final TargetGeometry geometry;
  final List<DetectedShot> shots;
  final int? expected;
  AnalysisResult(this.geometry, this.shots, this.expected);
  int get total => shots.fold(0, (a, s) => a + s.score.score);
}

/// A képet ekkora hosszabb oldalra kicsinyítjük feldolgozás előtt.
const int kMaxSide = 1600;

AnalysisResult analyze(Rgb img, TargetSpec spec, {int? expected = 15}) {
  final valid = validMask(img);
  final g = img.toGray();
  final cal = calibrate(g, valid, spec);
  final rm = RingModel(cal, spec);
  final can = warpAffine(g, cal.a, cal.size);
  var vm = warpMask(valid, cal.a, cal.size);
  vm = erodeSquare(vm, 4);
  final am = anomalyMaps(can, vm, rm, spec);
  final mask = holeMask(am, vm, spec, cal.spacing);
  final blobs = findBlobs(mask, am, vm, spec, cal.spacing);
  final rp = spec.pelletRadius * cal.spacing;
  final holes = splitBlobs(blobs, rp, expected);
  final geo = TargetGeometry(spec, cal.a, cal.ringFits, cal.spacing, cal.pxPerSpacingOrig);
  final shots = <DetectedShot>[];
  for (final h in holes) {
    final sc = geo.scoreCanon(h.x, h.y);
    final (ox, oy) = cal.toOrig(h.x, h.y);
    final note = [if (h.reason.isNotEmpty) h.reason, if (sc.note.isNotEmpty) sc.note].join('; ');
    shots.add(DetectedShot(ox, oy, sc, h.uncertain, note));
  }
  // sorszámozás olvasási sorrendben (fentről le, balról jobbra)
  final row = cal.pxPerSpacingOrig * 0.8;
  shots.sort((a, b) {
    final ra = (a.y / row).round(), rb = (b.y / row).round();
    return ra != rb ? ra.compareTo(rb) : a.x.compareTo(b.x);
  });
  return AnalysisResult(geo, shots, expected);
}
