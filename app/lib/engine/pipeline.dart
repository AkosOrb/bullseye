// Teljes kiértékelés: kép -> lövések, pontok, jelzések.
//
// A [TargetGeometry] a kalibráció eredménye, ami elmenthető: ezzel a kézi
// javításnál (húzás, új lövés) a felhasználó által megadott pont is azonnal
// pontozható, újabb képfeldolgozás nélkül.
import 'dart:math' as math;

import 'calibrate.dart';
import 'detect.dart';
import 'imaging.dart';
import 'measure.dart';
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
  /// Kézi igazítás a kiegyenesített képen: a gyűrűk eltolása (px) és nagyítása
  /// a célközéppont körül. (0, 0, 1) = a felismert gyűrűk.
  final double adjDx, adjDy, adjScale;
  late final RingModel _rm = RingModel.fromFits(ringFits, spacing, spec);
  late final Affine _toOrig = toCanon.inverse();
  late final (double, double) _c0 = () {
    final (cx, cy, _) = _rm.ringCircle(spec.ringCount);
    return (cx, cy);
  }();

  TargetGeometry(this.spec, this.toCanon, this.ringFits, this.spacing, this.pxPerSpacingOrig,
      {this.adjDx = 0, this.adjDy = 0, this.adjScale = 1});

  TargetGeometry withSpec(TargetSpec s) => TargetGeometry(s, toCanon, ringFits, spacing, pxPerSpacingOrig,
      adjDx: adjDx, adjDy: adjDy, adjScale: adjScale);

  TargetGeometry withAdjust({double? dx, double? dy, double? scale}) =>
      TargetGeometry(spec, toCanon, ringFits, spacing, pxPerSpacingOrig,
          adjDx: dx ?? adjDx, adjDy: dy ?? adjDy, adjScale: scale ?? adjScale);

  bool get adjusted => adjDx != 0 || adjDy != 0 || adjScale != 1;

  /// Eredeti képen mért eltolás átváltása kiegyenesített px-re.
  (double, double) deltaToCanon(double dx, double dy) {
    final (x0, y0) = toCanon.apply(0, 0);
    final (x1, y1) = toCanon.apply(dx, dy);
    return (x1 - x0, y1 - y0);
  }

  /// Igazított kiegyenesített pont -> a felismert gyűrűmodell koordinátái.
  (double, double) _unadjust(double x, double y) {
    final (cx, cy) = _c0;
    return (cx + (x - cx - adjDx) / adjScale, cy + (y - cy - adjDy) / adjScale);
  }

  /// A gyűrűmodell pontja -> igazított kiegyenesített pont.
  (double, double) _adjust(double x, double y) {
    final (cx, cy) = _c0;
    return (cx + adjDx + (x - cx) * adjScale, cy + adjDy + (y - cy) * adjScale);
  }

  double get mmPerCanonPx => spec.ringSpacingMm / spacing;

  /// Lövedéksugár az eredeti képen (rajzoláshoz).
  double get pelletRadiusOrig => spec.pelletRadius * pxPerSpacingOrig * adjScale;

  /// A célközéppont az eredeti képen.
  (double, double) get centerOrig {
    final (cx, cy) = _adjust(_c0.$1, _c0.$2);
    return _toOrig.apply(cx, cy);
  }

  /// A k gyűrű köre az eredeti képen közelítő középponttal és sugárral.
  (double, double, double) ringOrig(int k) {
    final (cx, cy, r) = _rm.ringCircle(k);
    final (ax, ay) = _adjust(cx, cy);
    final (ox, oy) = _toOrig.apply(ax, ay);
    return (ox, oy, r * adjScale / spacing * pxPerSpacingOrig);
  }

  /// A k gyűrű pontozási széle (a vonal külső széle) pontsorként az eredeti képen.
  List<(double, double)> ringOutlineOrig(int k, {int n = 120}) {
    final (cx, cy, r) = _rm.ringCircle(k);
    final hw = _rm.halfWidthOf(k);
    return [
      for (var i = 0; i < n; i++)
        () {
          final a = i * 2 * math.pi / n;
          final (ax, ay) = _adjust(cx + (r + hw) * math.cos(a), cy + (r + hw) * math.sin(a));
          return _toOrig.apply(ax, ay);
        }()
    ];
  }

  ShotScore scoreOrig(double x, double y, {double? radiusOrig}) {
    final (cx, cy) = toCanon.apply(x, y);
    return scoreCanon(cx, cy, radiusPx: radiusOrig == null ? null : radiusOrig / pxPerSpacingOrig * spacing);
  }

  /// [radiusPx]: a lövésnyom mért sugara (kiegyenesített px); ha nincs, a névleges lövedéksugár.
  ShotScore scoreCanon(double xa, double ya, {double? radiusPx}) {
    final (x, y) = _unadjust(xa, ya);
    // A gyűrűmodell terében 1 px = mmPerCanonPx mm (a gyűrűtávolság definíció szerint
    // 8 mm); a képen mért sugarat a kézi nagyítással visszaosztjuk.
    final rp = (radiusPx == null ? spec.pelletRadius * spacing : radiusPx / adjScale) +
        spec.edgeToleranceMm / spec.ringSpacingMm * spacing;
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
        if (adjusted) 'adj': [adjDx, adjDy, adjScale],
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
    final adj = (j['adj'] as List?)?.map((v) => (v as num).toDouble()).toList();
    return TargetGeometry(spec ?? TargetSpec.byId(j['target'] as String), Affine.fromList(j['toCanon'] as List),
        rings, (j['spacing'] as num).toDouble(), (j['pxPerSpacingOrig'] as num).toDouble(),
        adjDx: adj?[0] ?? 0, adjDy: adj?[1] ?? 0, adjScale: adj?[2] ?? 1);
  }
}

String _fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

class DetectedShot {
  final double x, y; // eredeti kép px
  final ShotScore score;
  final bool uncertain;
  final String note;
  final String reason; // felismerési megjegyzés (pl. szétbontott lyuk)
  /// A mért nyomsugár az eredeti képen (px); null, ha nem mérhető.
  final double? radius;
  DetectedShot(this.x, this.y, this.score, this.uncertain, this.note, this.reason, [this.radius]);
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
  // A találati kör mérete a képen látható koromgyűrűhöz igazodik: a fehér
  // részen lövésenként mérjük. Ahol koromgyűrű nem látszik (fekete rész,
  // egymásba lőtt lyuk), a névleges 4,5 mm-es lövedékméret marad.
  final toOrigScale = cal.pxPerSpacingOrig / cal.spacing;
  final measured = <double?>[];
  for (final h in holes) {
    final b = blobs[h.blobIndex];
    measured.add(b.zone == 'white' && h.nInBlob == 1
        ? measureHoleRadius(am.dark, vm, cal.size, h.x, h.y, rp)
        : null);
  }
  for (var i = 0; i < holes.length; i++) {
    final h = holes[i];
    final rc = measured[i];
    final sc = geo.scoreCanon(h.x, h.y, radiusPx: rc);
    final (ox, oy) = cal.toOrig(h.x, h.y);
    final note = [if (h.reason.isNotEmpty) h.reason, if (sc.note.isNotEmpty) sc.note].join('; ');
    shots.add(DetectedShot(ox, oy, sc, h.uncertain, note, h.reason, rc == null ? null : rc * toOrigScale));
  }
  // sorszámozás olvasási sorrendben (fentről le, balról jobbra)
  final row = cal.pxPerSpacingOrig * 0.8;
  shots.sort((a, b) {
    final ra = (a.y / row).round(), rb = (b.y / row).round();
    return ra != rb ? ra.compareTo(rb) : a.x.compareTo(b.x);
  });
  return AnalysisResult(geo, shots, expected);
}
