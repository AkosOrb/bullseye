// Kalibrálás: a fekete korong ellipszise + a gyűrűvonalak körillesztése.
// (A Python motor bullseye_engine/calibrate.py megfelelője.)
import 'dart:math' as math;

import 'imaging.dart';
import 'target.dart';

/// Gyűrűtávolság a kiegyenesített (canonical) képen, képpontban.
const double kD = 60.0;

class CalibrationException implements Exception {
  final String message;
  CalibrationException(this.message);
  @override
  String toString() => message;
}

class RingFit {
  final double cx, cy, r;
  final int n;
  final double halfWidth;
  const RingFit(this.cx, this.cy, this.r, this.n, this.halfWidth);
}

class Calibration {
  final Affine a; // eredeti -> kiegyenesített
  final Affine ainv;
  final int size;
  final double spacing;
  final Ellipse ellipse;
  final Map<int, RingFit> ringFits;
  final double pxPerSpacingOrig;

  Calibration({
    required this.a,
    required this.size,
    required this.spacing,
    required this.ellipse,
    required this.ringFits,
    required this.pxPerSpacingOrig,
  }) : ainv = a.inverse();

  (double, double) toCanon(double x, double y) => a.apply(x, y);
  (double, double) toOrig(double x, double y) => ainv.apply(x, y);
}

/// A fotóhoz tartozó képpontok (nem a tiszta fehér kitöltés).
Mask validMask(Rgb img) {
  final pad = img.pureWhite();
  final lab = connectedComponents(pad);
  final out = Mask(img.w, img.h)..d.fillRange(0, img.w * img.h, 1);
  final minArea = 0.02 * img.w * img.h;
  for (final c in lab.comps) {
    if (c.area > minArea) {
      for (var i = 0; i < lab.lab.length; i++) {
        if (lab.lab[i] == c.label) out.d[i] = 0;
      }
    }
  }
  return out;
}

Ellipse _ransacEllipse(List<double> xs, List<double> ys,
    {int iters = 400, double tol = 3.0}) {
  final n = xs.length;
  if (n < 20) throw CalibrationException('Nem található a fekete korong széle.');
  final rnd = math.Random(0);
  List<bool>? bestInl;
  var bestCount = -1;
  for (var it = 0; it < iters; it++) {
    final idx = <int>{};
    while (idx.length < 6) {
      idx.add(rnd.nextInt(n));
    }
    final e = fitEllipse([for (final i in idx) xs[i]], [for (final i in idx) ys[i]]);
    if (e == null) continue;
    final mn = math.min(e.a, e.b), mx = math.max(e.a, e.b);
    if (mn < 25 || mx / mn > 1.6) continue;
    var cnt = 0;
    final inl = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      if (e.residual(xs[i], ys[i]) < tol) {
        inl[i] = true;
        cnt++;
      }
    }
    if (cnt > bestCount) {
      bestCount = cnt;
      bestInl = inl;
    }
  }
  if (bestInl == null) throw CalibrationException('Nem sikerült ellipszist illeszteni.');
  List<double> sel(List<double> v, List<bool> m) => [for (var i = 0; i < n; i++) if (m[i]) v[i]];
  var e = fitEllipse(sel(xs, bestInl), sel(ys, bestInl));
  if (e == null) throw CalibrationException('Nem sikerült ellipszist illeszteni.');
  for (var k = 0; k < 3; k++) {
    final inl = [for (var i = 0; i < n; i++) e!.residual(xs[i], ys[i]) < tol];
    final e2 = fitEllipse(sel(xs, inl), sel(ys, inl));
    if (e2 != null) e = e2;
  }
  return e!;
}

Ellipse findBlackDisk(Gray g, Mask valid) {
  final b = gaussianBlur(g, 3);
  final t = otsu(b, valid);
  var dark = Mask(g.w, g.h);
  for (var i = 0; i < g.d.length; i++) {
    dark.d[i] = (b.d[i] < t && valid.d[i] != 0) ? 1 : 0;
  }
  final k = math.max(15, (math.min(g.w, g.h) * 0.03).toInt()) | 1;
  dark = closeDisk(dark, kernelRadius(k));
  final lab = connectedComponents(dark);
  if (lab.comps.isEmpty) throw CalibrationException('Nem található a fekete korong.');
  final best = lab.comps.reduce((a, b) => a.area >= b.area ? a : b);
  // a fekete korong határpontjai, a kép/kitöltés szélén lévők nélkül
  final inv = dilateDisk(valid.not(), 4.5);
  final xs = <double>[], ys = <double>[];
  final w = g.w, h = g.h;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (lab.lab[i] != best.label) continue;
      if (lab.lab[i - 1] == best.label &&
          lab.lab[i + 1] == best.label &&
          lab.lab[i - w] == best.label &&
          lab.lab[i + w] == best.label) {
        continue;
      }
      if (x <= 4 || y <= 4 || x >= w - 5 || y >= h - 5) continue;
      if (inv.d[i] != 0) continue;
      xs.add(x.toDouble());
      ys.add(y.toDouble());
    }
  }
  // a futásidő miatt ritkítjuk
  if (xs.length > 3000) {
    final step = xs.length / 3000;
    final nx = <double>[], ny = <double>[];
    for (var f = 0.0; f < xs.length; f += step) {
      nx.add(xs[f.toInt()]);
      ny.add(ys[f.toInt()]);
    }
    return _ransacEllipse(nx, ny);
  }
  return _ransacEllipse(xs, ys);
}

Affine _affineFromEllipse(Ellipse e, double r0, double c) {
  final ct = math.cos(e.angle), st = math.sin(e.angle);
  final sa = r0 / e.a, sb = r0 / e.b;
  // M = Rot · diag(sa, sb) · Rotᵀ
  final m00 = ct * ct * sa + st * st * sb;
  final m01 = ct * st * (sa - sb);
  final m11 = st * st * sa + ct * ct * sb;
  return Affine(m00, m01, c - (m00 * e.cx + m01 * e.cy), m01, m11, c - (m01 * e.cx + m11 * e.cy));
}

(double, double, double, int)? _robustCircle(List<double> xs, List<double> ys) {
  var keep = List<bool>.filled(xs.length, true);
  (double, double, double)? fit;
  var nk = xs.length;
  for (var it = 0; it < 4; it++) {
    if (nk < 12) return null;
    final fx = [for (var i = 0; i < xs.length; i++) if (keep[i]) xs[i]];
    final fy = [for (var i = 0; i < xs.length; i++) if (keep[i]) ys[i]];
    fit = fitCircle(fx, fy);
    if (fit == null) return null;
    final (cx, cy, r) = fit;
    final res = [for (var i = 0; i < xs.length; i++) ((math.sqrt((xs[i] - cx) * (xs[i] - cx) + (ys[i] - cy) * (ys[i] - cy))) - r).abs()];
    final mad = median([for (var i = 0; i < xs.length; i++) if (keep[i]) res[i]]) * 1.4826 + 0.3;
    final thr = math.max(2.5 * mad, 0.8);
    keep = [for (final v in res) v < thr];
    nk = keep.where((v) => v).length;
  }
  return (fit!.$1, fit.$2, fit.$3, nk);
}

double _lineHalfWidth(Gray canf, double cx, double cy, double r, bool insideBlack) {
  final rs = <double>[for (var v = r - 8; v < r + 8; v += 0.25) v];
  final prof = <double>[];
  final phs = <double>[];
  for (var i = 0; i < 360; i++) {
    final p = i * 2 * math.pi / 360;
    if (math.sin(p).abs() > 0.3) phs.add(p);
  }
  for (final rr in rs) {
    final vals = <double>[];
    for (final p in phs) {
      final v = canf.sample(cx + math.cos(p) * rr, cy + math.sin(p) * rr, 0);
      vals.add(insideBlack ? v : -v);
    }
    prof.add(median(vals));
  }
  final base = median([...prof.sublist(0, 8), ...prof.sublist(prof.length - 8)]);
  final pk = prof.reduce(math.max);
  final half = (base + pk) / 2;
  final w = prof.where((v) => v > half).length * 0.25;
  return (w / 2).clamp(0.0, 4.0);
}

Calibration calibrate(Gray g, Mask valid, TargetSpec spec) {
  final e = findBlackDisk(g, valid);
  final rBlack = spec.blackRadius * kD;
  final half = ((spec.blackRadius + 2.5) * kD).ceil();
  final size = 2 * half;
  final a = _affineFromEllipse(e, rBlack, half.toDouble());
  final can = warpAffine(g, a, size);
  var vmask = warpMask(valid, a, size);
  vmask = erodeSquare(vmask, 3);
  final canf = gaussianBlur(can, 1.0);

  const nang = 720;
  final fits = <int, RingFit>{};
  const win = 0.28 * kD;
  for (var k = 1; k <= spec.ringCount; k++) {
    final r0 = spec.ringRadius(k) * kD;
    if (r0 + win >= half - 2) continue;
    final rs = <double>[for (var v = r0 - win; v < r0 + win; v += 0.5) v];
    final isEdge = k == spec.blackOuterRing || k == spec.blackInnerRing;
    final insideBlack = spec.blackOuterRing < k && k < spec.blackInnerRing;
    final xs = <double>[], ys = <double>[];
    for (var ai = 0; ai < nang; ai++) {
      final ang = ai * 2 * math.pi / nang;
      if (math.sin(ang).abs() <= 0.16) continue;
      final ca = math.cos(ang), sa = math.sin(ang);
      final prof = List<double>.filled(rs.length, 0);
      var ok = true;
      for (var j = 0; j < rs.length; j++) {
        final x = half + ca * rs[j], y = half + sa * rs[j];
        final ix = x.round(), iy = y.round();
        if (ix < 0 || iy < 0 || ix >= size || iy >= size || vmask.d[iy * size + ix] == 0) {
          ok = false;
          break;
        }
        prof[j] = canf.sample(x, y, 0);
      }
      if (!ok) continue;
      double pos;
      if (isEdge) {
        var best = -1e9;
        var bi = 0;
        for (var j = 0; j < rs.length - 1; j++) {
          var dd = prof[j + 1] - prof[j];
          if (k == spec.blackInnerRing) dd = -dd;
          if (dd > best) {
            best = dd;
            bi = j;
          }
        }
        if (best <= 6) continue;
        pos = rs[bi] + 0.25;
      } else {
        final p = insideBlack ? prof : [for (final v in prof) -v];
        var bi = 0;
        for (var j = 1; j < p.length; j++) {
          if (p[j] > p[bi]) bi = j;
        }
        bi = bi.clamp(1, p.length - 2);
        final y0 = p[bi - 1], y1 = p[bi], y2 = p[bi + 1];
        final den = y0 - 2 * y1 + y2;
        final off = den.abs() > 1e-6 ? (0.5 * (y0 - y2) / den).clamp(-1.0, 1.0) : 0.0;
        pos = rs[bi] + off * 0.5;
        if (y1 - median(p) <= 12) continue;
      }
      xs.add(half + ca * pos);
      ys.add(half + sa * pos);
    }
    if (xs.length < 40) continue;
    final fit = _robustCircle(xs, ys);
    if (fit != null && fit.$4 > 40) {
      final hw = isEdge ? 0.0 : _lineHalfWidth(canf, fit.$1, fit.$2, fit.$3, insideBlack);
      fits[k] = RingFit(fit.$1, fit.$2, fit.$3, fit.$4, hw);
    }
  }
  if (fits.length < 3) {
    throw CalibrationException('Kevés gyűrűvonal található. Fotózd újra a lapot merőlegesen, jó fényben.');
  }
  var num = 0.0, den = 0.0;
  for (final en in fits.entries) {
    final n = spec.ringRadius(en.key);
    num += en.value.n * n * en.value.r;
    den += en.value.n * n * n;
  }
  final spacing = num / den;
  final pxOrig = spacing / math.sqrt(a.det.abs());
  return Calibration(
      a: a, size: size, spacing: spacing, ellipse: e, ringFits: fits, pxPerSpacingOrig: pxOrig);
}
