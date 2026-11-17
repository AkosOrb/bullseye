// Találatkeresés a kiegyenesített képen (a Python detect.py megfelelője).
//
// A lőlap forgásszimmetrikus: sugáronként (szögszektoronként) medián
// háttérértéket becsülünk. Fekete területen a lyuk világosabb, fehér
// területen az ólomgyűrű sötétebb a háttérnél. A számfeliratokat a
// túloldali ikerpárjukkal vetjük össze.
import 'dart:math' as math;
import 'dart:typed_data';

import 'imaging.dart';
import 'rings.dart';
import 'target.dart';

class Blob {
  final double area;
  final double cx, cy;
  final List<double> xs, ys; // a folt képpontjai
  final String zone; // 'black' | 'white'
  final double bandFrac;
  final double strength;
  Blob(this.area, this.cx, this.cy, this.xs, this.ys, this.zone, this.bandFrac, this.strength);
}

class AnomalyMaps {
  final Float32List bright, dark, t, phi;
  final Mask band;
  AnomalyMaps(this.bright, this.dark, this.t, this.phi, this.band);
}

const double _dt = 1 / 120;
const int _nphi = 1440;

Float32List _sectorMedians(Float32List pol, int r0, int r1, int sectors, Float32List out) {
  final w = _nphi ~/ sectors;
  final nWin = sectors * 2;
  final vals = Float64List(nWin);
  final buf = <double>[];
  for (var row = r0; row < r1; row++) {
    final base = row * _nphi;
    final all = <double>[];
    for (var s = 0; s < nWin; s++) {
      final c = s * w ~/ 2;
      buf.clear();
      for (var i = c - w ~/ 2; i < c - w ~/ 2 + w; i++) {
        final v = pol[base + ((i % _nphi) + _nphi) % _nphi];
        if (!v.isNaN) buf.add(v);
      }
      vals[s] = buf.isEmpty ? double.nan : median(buf);
    }
    for (var i = 0; i < _nphi; i++) {
      final v = pol[base + i];
      if (!v.isNaN) all.add(v);
    }
    final glob = all.isEmpty ? 128.0 : median(all);
    for (var s = 0; s < nWin; s++) {
      if (vals[s].isNaN) vals[s] = glob;
    }
    // szektorközéppontok közti lineáris interpoláció (körkörösen)
    for (var i = 0; i < _nphi; i++) {
      final pos = i / (w / 2.0);
      final s0 = pos.floor() % nWin;
      final s1 = (s0 + 1) % nWin;
      final f = pos - pos.floor();
      out[base + i] = vals[s0] * (1 - f) + vals[s1] * f;
    }
  }
  return out;
}

/// Polár háttérmodell: (sorok = t, oszlopok = phi).
(int, Float32List) _polarBackground(Gray g, RingModel rm, double tMax) {
  final nt = (tMax / _dt).ceil();
  final pol = Float32List(nt * _nphi);
  for (var ti = 0; ti < nt; ti++) {
    final t = ti * _dt;
    final (cx, cy, r) = rm.circle(t);
    for (var pi = 0; pi < _nphi; pi++) {
      final phi = -math.pi + pi * 2 * math.pi / _nphi;
      pol[ti * _nphi + pi] = g.sample(cx + r * math.cos(phi), cy + r * math.sin(phi));
    }
  }
  final full = Float32List(nt * _nphi);
  const choices = [(1, 0.0), (4, 1.6), (8, 3.2), (16, 6.0)];
  for (var c = 0; c < choices.length; c++) {
    final (sectors, tmin) = choices[c];
    final tNext = c + 1 < choices.length ? choices[c + 1].$2 : double.infinity;
    final r0 = (tmin / _dt).ceil().clamp(0, nt);
    final r1 = tNext.isInfinite ? nt : (tNext / _dt).ceil().clamp(0, nt);
    if (r1 > r0) _sectorMedians(pol, r0, r1, sectors, full);
  }
  return (nt, full);
}

Float32List _radialMinMax(Float32List b, int nt, int tol, bool isMax) {
  final out = Float32List(b.length);
  for (var ti = 0; ti < nt; ti++) {
    for (var pi = 0; pi < _nphi; pi++) {
      var v = isMax ? -double.infinity : double.infinity;
      for (var k = math.max(0, ti - tol); k <= math.min(nt - 1, ti + tol); k++) {
        final s = b[k * _nphi + pi];
        if (isMax ? s > v : s < v) v = s;
      }
      out[ti * _nphi + pi] = v;
    }
  }
  return out;
}

double _samplePolar(Float32List b, int nt, double ti, double pi) {
  ti = ti.clamp(0.0, nt - 1.0);
  final t0 = ti.floor(), t1 = math.min(t0 + 1, nt - 1);
  final p0 = pi.floor() % _nphi, p1 = (p0 + 1) % _nphi;
  final ft = ti - ti.floor(), fp = pi - pi.floor();
  final a = b[t0 * _nphi + p0], bb = b[t0 * _nphi + p1];
  final c = b[t1 * _nphi + p0], d = b[t1 * _nphi + p1];
  return (a * (1 - fp) + bb * fp) * (1 - ft) + (c * (1 - fp) + d * fp) * ft;
}

(double, double)? _refineTwin(Gray g, Mask valid, (double, double) lc, (double, double) rc,
    double spacing, double hh,
    {int? search, double minCorr = 0.5}) {
  final s = search ?? (0.5 * spacing).toInt();
  final halfW = (0.42 * spacing).toInt();
  final halfH = (hh * spacing * 0.9).toInt();
  final lx = lc.$1.round(), ly = lc.$2.round();
  final rx = rc.$1.round(), ry = rc.$2.round();
  bool ok(int x0, int y0, int x1, int y1) {
    if (x0 < 0 || y0 < 0 || x1 > g.w || y1 > g.h) return false;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (valid.d[y * g.w + x] == 0) return false;
      }
    }
    return true;
  }

  if (!ok(lx - halfW, ly - halfH, lx + halfW, ly + halfH) ||
      !ok(rx - halfW - s, ry - halfH - s, rx + halfW + s, ry + halfH + s)) {
    return null;
  }
  // sablon szórása
  final tv = <double>[];
  for (var y = ly - halfH; y < ly + halfH; y++) {
    for (var x = lx - halfW; x < lx + halfW; x++) {
      tv.add(g.d[y * g.w + x]);
    }
  }
  final mean = tv.reduce((a, b) => a + b) / tv.length;
  final sd = math.sqrt(tv.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / tv.length);
  if (sd < 5) return null;
  final (bx, by, best, res) = matchTemplate(g, lx - halfW, ly - halfH, 2 * halfW, 2 * halfH,
      rx - halfW - s, ry - halfH - s, 2 * halfW + 2 * s, 2 * halfH + 2 * s);
  if (best < minCorr) return null;
  final ow = 2 * s + 1, oh = 2 * s + 1;
  double sub(double a, double b, double c) {
    final den = a - 2 * b + c;
    return den.abs() > 1e-6 ? 0.5 * (a - c) / den : 0.0;
  }

  final fx = (bx > 0 && bx < ow - 1) ? sub(res[by * ow + bx - 1], res[by * ow + bx], res[by * ow + bx + 1]) : 0.0;
  final fy = (by > 0 && by < oh - 1) ? sub(res[(by - 1) * ow + bx], res[by * ow + bx], res[(by + 1) * ow + bx]) : 0.0;
  return ((rx - lx) + (bx - s) + fx, (ry - ly) + (by - s) + fy);
}

double _labelAxisAngle(Gray g, Mask valid, RingModel rm, TargetSpec spec) {
  final angs = <double>[];
  for (final k in spec.labelRings) {
    final tm = spec.ringRadius(k) - 0.5;
    final lc = rm.point(tm, math.pi);
    final rc = rm.point(tm, 0);
    final search = (math.tan(8 * math.pi / 180) * tm * rm.spacing).toInt() + 4;
    final o = _refineTwin(g, valid, lc, rc, rm.spacing, spec.labelHalfHeight,
        search: search, minCorr: 0.6);
    if (o == null) continue;
    angs.add(math.atan2(o.$2, o.$1));
    if (angs.length >= 4) break; // elég néhány pár a szöghöz
  }
  return angs.isEmpty ? 0.0 : median(angs);
}

(double, double) _robustLinfit(List<double> x, List<double> y) {
  var keep = List<bool>.filled(x.length, true);
  var a = 1.0, b = 0.0;
  for (var it = 0; it < 3; it++) {
    final xs = [for (var i = 0; i < x.length; i++) if (keep[i]) x[i]];
    final ys = [for (var i = 0; i < x.length; i++) if (keep[i]) y[i]];
    if (xs.length < 20) break;
    final mx = xs.reduce((p, q) => p + q) / xs.length;
    final my = ys.reduce((p, q) => p + q) / ys.length;
    var sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < xs.length; i++) {
      sxx += (xs[i] - mx) * (xs[i] - mx);
      sxy += (xs[i] - mx) * (ys[i] - my);
    }
    if (math.sqrt(sxx / xs.length) < 1) break;
    a = sxy / sxx;
    b = my - a * mx;
    final res = [for (var i = 0; i < x.length; i++) (y[i] - (a * x[i] + b)).abs()];
    final med = median([for (var i = 0; i < x.length; i++) if (keep[i]) res[i]]);
    final thr = math.max(15.0, 2.5 * med);
    keep = [for (final r in res) r < thr];
  }
  return (a.clamp(0.7, 1.4), b);
}

AnomalyMaps anomalyMaps(Gray g, Mask valid, RingModel rm, TargetSpec spec) {
  final size = g.w;
  final n = size * size;
  final tMap = Float32List(n), phiMap = Float32List(n);
  var tMax = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final (t, p) = rm.coords(x.toDouble(), y.toDouble());
      tMap[y * size + x] = t;
      phiMap[y * size + x] = p;
      if (valid.d[y * size + x] != 0 && t > tMax) tMax = t;
    }
  }
  tMax += 0.1;
  final (nt, bg) = _polarBackground(g, rm, tMax);
  final bhi = _radialMinMax(bg, nt, 3, true);
  final blo = _radialMinMax(bg, nt, 3, false);
  final bright = Float32List(n), dark = Float32List(n);
  for (var i = 0; i < n; i++) {
    final ti = tMap[i] / _dt;
    final pi = (phiMap[i] + math.pi) / (2 * math.pi) * _nphi;
    bright[i] = g.d[i] - _samplePolar(bhi, nt, ti, pi);
    dark[i] = _samplePolar(blo, nt, ti, pi) - g.d[i];
  }

  final band = Mask(size, size);
  if (spec.labelRings.isNotEmpty) {
    final hh = spec.labelHalfHeight;
    final theta = _labelAxisAngle(g, valid, rm, spec);
    final twinX = Float32List(n)..fillRange(0, n, -10);
    final twinY = Float32List(n)..fillRange(0, n, -10);
    final cellId = Int16List(n);
    final offsets = <int, (double, double)>{};
    for (var ci = 0; ci < spec.labelRings.length; ci++) {
      final tm = spec.ringRadius(spec.labelRings[ci]) - 0.5;
      final lc = rm.point(tm, theta + math.pi);
      final rc = rm.point(tm, theta);
      final o = _refineTwin(g, valid, lc, rc, rm.spacing, hh, search: (0.2 * rm.spacing).toInt()) ??
          (rc.$1 - lc.$1, rc.$2 - lc.$2);
      offsets[ci] = o;
    }
    for (var i = 0; i < n; i++) {
      final t = tMap[i];
      final s = math.sin(phiMap[i] - theta), c = math.cos(phiMap[i] - theta);
      if ((t * s).abs() >= hh) continue;
      for (var ci = 0; ci < spec.labelRings.length; ci++) {
        final tm = spec.ringRadius(spec.labelRings[ci]) - 0.5;
        if (t > tm - 0.5 && t <= tm + 0.5) {
          final (ox, oy) = offsets[ci]!;
          final x = (i % size).toDouble(), y = (i ~/ size).toDouble();
          band.d[i] = 1;
          if (c < 0) {
            twinX[i] = x + ox;
            twinY[i] = y + oy;
            cellId[i] = 2 * ci + 1;
          } else if (c > 0) {
            twinX[i] = x - ox;
            twinY[i] = y - oy;
            cellId[i] = 2 * ci + 2;
          }
          break;
        }
      }
    }
    final gmax = minMaxFilter(g, 3, isMax: true);
    final gmin = minMaxFilter(g, 3, isMax: false);
    final twinHi = Float32List(n), twinLo = Float32List(n), twin = Float32List(n);
    final vtw = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (band.d[i] == 0) continue;
      final tx = twinX[i], ty = twinY[i];
      final ix = tx.round(), iy = ty.round();
      vtw[i] = (ix >= 0 && iy >= 0 && ix < size && iy < size && valid.d[iy * size + ix] != 0) ? 1 : 0;
      twinHi[i] = gmax.sample(tx, ty, 255);
      twinLo[i] = gmin.sample(tx, ty, 0);
      twin[i] = g.sample(tx, ty, 0);
    }
    // fénykorrekció cellánként
    final cells = <int, List<int>>{};
    final cellsAll = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (band.d[i] == 0 || cellId[i] == 0) continue;
      cellsAll.putIfAbsent(cellId[i], () => []).add(i);
      if (vtw[i] != 0) cells.putIfAbsent(cellId[i], () => []).add(i);
    }
    for (final e in cells.entries) {
      final (a, b) = _robustLinfit([for (final i in e.value) twin[i]], [for (final i in e.value) g.d[i]]);
      for (final i in e.value) {
        twinHi[i] = a * twinHi[i] + b;
        twinLo[i] = a * twinLo[i] + b;
      }
    }
    final nouse = Uint8List(n);
    for (final e in cellsAll.entries) {
      final frac = e.value.where((i) => vtw[i] != 0).length / e.value.length;
      if (frac < 0.97) {
        for (final i in e.value) {
          nouse[i] = 1;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      if (band.d[i] == 0) continue;
      if (vtw[i] == 0 || nouse[i] != 0) {
        bright[i] = 0;
        dark[i] = 0;
      } else {
        bright[i] = math.min(bright[i], g.d[i] - twinHi[i]);
        dark[i] = math.min(dark[i], twinLo[i] - g.d[i]);
      }
    }
  }
  for (var i = 0; i < n; i++) {
    if (valid.d[i] == 0) {
      bright[i] = 0;
      dark[i] = 0;
    }
  }
  return AnomalyMaps(bright, dark, tMap, phiMap, band);
}

Mask holeMask(AnomalyMaps am, Mask valid, TargetSpec spec, double spacing,
    {double tb = 45, double tw = 20}) {
  final size = valid.w;
  final n = size * size;
  final rp = spec.pelletRadius * spacing;
  final darkPos = Gray(size, size);
  for (var i = 0; i < n; i++) {
    darkPos.d[i] = math.max(0, am.dark[i]);
  }
  final dsm = gaussianBlur(darkPos, rp * 0.4);
  var m = Mask(size, size);
  for (var i = 0; i < n; i++) {
    final on = (am.bright[i] > tb) || (dsm.d[i] > tw);
    m.d[i] = (on && valid.d[i] != 0) ? 1 : 0;
  }
  final kc = math.max(3, (rp * 0.5).toInt()) | 1;
  m = closeDisk(m, kernelRadius(kc));
  m = fillHoles(m);
  final ko = math.max(3, (rp * 0.6).toInt()) | 1;
  m = openDisk(m, kernelRadius(ko));
  return m;
}

List<Blob> findBlobs(Mask mask, AnomalyMaps am, Mask valid, TargetSpec spec, double spacing,
    {double tb = 45, double tw = 28}) {
  final size = mask.w;
  final rp = spec.pelletRadius * spacing;
  final a1 = math.pi * rp * rp;
  final border = dilateDisk(valid.not(), kernelRadius(rp.toInt()));
  final lab = connectedComponents(mask);
  final pixels = <int, List<int>>{};
  for (var i = 0; i < lab.lab.length; i++) {
    final l = lab.lab[i];
    if (l != 0) pixels.putIfAbsent(l, () => []).add(i);
  }
  final out = <Blob>[];
  for (final c in lab.comps) {
    if (c.area < 0.25 * a1) continue;
    final px = pixels[c.label]!;
    if (px.any((i) => border.d[i] != 0)) continue;
    final strong = px.where((i) => am.bright[i] > tb || am.dark[i] > tw).length;
    if (strong < 0.2 * a1) continue;
    final ci = c.cy.toInt() * size + c.cx.toInt();
    final t = am.t[ci];
    final zone = (spec.whiteDiskRadius <= t && t <= spec.blackRadius) ? 'black' : 'white';
    final strength = zone == 'black'
        ? median([for (final i in px) am.bright[i]])
        : percentile([for (final i in px) am.dark[i]], 90);
    final bf = px.where((i) => am.band.d[i] != 0).length / px.length;
    if (bf > 0.5 && zone == 'black' && strength < 70) continue;
    out.add(Blob(
      c.area.toDouble(),
      c.cx,
      c.cy,
      [for (final i in px) (i % size).toDouble()],
      [for (final i in px) (i ~/ size).toDouble()],
      zone,
      bf,
      strength,
    ));
  }
  return out;
}
