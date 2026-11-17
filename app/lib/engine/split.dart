// Egymásba lőtt lyukak szétbontása (a Python split.py megfelelője).
import 'dart:math' as math;

import 'detect.dart';

const _coverR = {'black': 1.3, 'white': 1.6};
const _singleArea = {'black': 0.95, 'white': 2.2};

class Hole {
  final double x, y;
  final int blobIndex;
  final int nInBlob;
  final bool uncertain;
  final String reason;
  Hole(this.x, this.y, this.blobIndex, this.nInBlob, this.uncertain, this.reason);
}

List<(double, double)> _kmeans(List<double> xs, List<double> ys, int k, math.Random rnd) {
  final n = xs.length;
  if (k == 1) {
    return [(xs.reduce((a, b) => a + b) / n, ys.reduce((a, b) => a + b) / n)];
  }
  List<(double, double)>? best;
  var bestCost = double.infinity;
  for (var attempt = 0; attempt < 8; attempt++) {
    // k-means++ inicializálás
    final cx = <double>[], cy = <double>[];
    final first = rnd.nextInt(n);
    cx.add(xs[first]);
    cy.add(ys[first]);
    final d2 = List<double>.filled(n, double.infinity);
    while (cx.length < k) {
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        final dx = xs[i] - cx.last, dy = ys[i] - cy.last;
        d2[i] = math.min(d2[i], dx * dx + dy * dy);
        sum += d2[i];
      }
      var r = rnd.nextDouble() * sum;
      var pick = n - 1;
      for (var i = 0; i < n; i++) {
        r -= d2[i];
        if (r <= 0) {
          pick = i;
          break;
        }
      }
      cx.add(xs[pick]);
      cy.add(ys[pick]);
    }
    final assign = List<int>.filled(n, 0);
    var cost = 0.0;
    for (var it = 0; it < 60; it++) {
      cost = 0;
      for (var i = 0; i < n; i++) {
        var bd = double.infinity, bj = 0;
        for (var j = 0; j < k; j++) {
          final dx = xs[i] - cx[j], dy = ys[i] - cy[j];
          final dd = dx * dx + dy * dy;
          if (dd < bd) {
            bd = dd;
            bj = j;
          }
        }
        assign[i] = bj;
        cost += bd;
      }
      final sx = List<double>.filled(k, 0), sy = List<double>.filled(k, 0);
      final cnt = List<int>.filled(k, 0);
      for (var i = 0; i < n; i++) {
        sx[assign[i]] += xs[i];
        sy[assign[i]] += ys[i];
        cnt[assign[i]]++;
      }
      var moved = 0.0;
      for (var j = 0; j < k; j++) {
        if (cnt[j] == 0) continue;
        final nx = sx[j] / cnt[j], ny = sy[j] / cnt[j];
        moved = math.max(moved, (nx - cx[j]).abs() + (ny - cy[j]).abs());
        cx[j] = nx;
        cy[j] = ny;
      }
      if (moved < 0.05) break;
    }
    if (cost < bestCost) {
      bestCost = cost;
      best = [for (var j = 0; j < k; j++) (cx[j], cy[j])];
    }
  }
  return best!;
}

double _coverage(List<double> xs, List<double> ys, List<(double, double)> cen, double r) {
  var c = 0;
  final r2 = r * r;
  for (var i = 0; i < xs.length; i++) {
    for (final (x, y) in cen) {
      final dx = xs[i] - x, dy = ys[i] - y;
      if (dx * dx + dy * dy <= r2) {
        c++;
        break;
      }
    }
  }
  return c / xs.length;
}

class _BlobModel {
  late final List<double> xs, ys;
  final double r;
  final double normArea;
  late final int nmax;
  final Map<int, (List<(double, double)>, double)> _cache = {};
  final math.Random rnd = math.Random(1234);

  _BlobModel(Blob b, double rp, double a1)
      : r = _coverR[b.zone]! * rp,
        normArea = b.area / (_singleArea[b.zone]! * a1) {
    if (b.xs.length > 4000) {
      final step = b.xs.length / 4000;
      xs = [for (var f = 0.0; f < b.xs.length; f += step) b.xs[f.toInt()]];
      ys = [for (var f = 0.0; f < b.ys.length; f += step) b.ys[f.toInt()]];
    } else {
      xs = b.xs;
      ys = b.ys;
    }
    nmax = math.max(1, math.min(8, (normArea * 1.6).ceil() + 1));
  }

  (List<(double, double)>, double) centres(int n) {
    return _cache.putIfAbsent(n, () {
      final c = _kmeans(xs, ys, n, rnd);
      return (c, _coverage(xs, ys, c, r));
    });
  }

  double gain(int n) {
    if (n + 1 > nmax) return -1;
    return (centres(n + 1).$2 - centres(n).$2) * normArea;
  }

  int naturalN([double thr = 0.9]) {
    for (var n = 1; n <= nmax; n++) {
      if (centres(n).$2 >= thr) return n;
    }
    return nmax;
  }
}

List<Hole> splitBlobs(List<Blob> blobs, double rp, int? expected) {
  final a1 = math.pi * rp * rp;
  final models = [for (final b in blobs) _BlobModel(b, rp, a1)];
  List<int> ns;
  if (expected == null) {
    ns = [for (final m in models) m.naturalN()];
  } else {
    ns = List<int>.filled(models.length, 1);
    while (ns.fold<int>(0, (a, b) => a + b) < expected) {
      var bi = -1;
      var bg = 0.0;
      for (var i = 0; i < models.length; i++) {
        final g = models[i].gain(ns[i]);
        if (g > bg) {
          bg = g;
          bi = i;
        }
      }
      if (bi < 0) break;
      ns[bi]++;
    }
  }
  final holes = <Hole>[];
  for (var bi = 0; bi < models.length; bi++) {
    final m = models[bi];
    final n = ns[bi];
    final cen = m.centres(n).$1;
    final agree = m.naturalN() == n;
    for (final (x, y) in cen) {
      var unc = n > 1 && !agree;
      var reason = n > 1 ? 'összefolyó lyukakból bontva' : '';
      if (n == 1 && m.normArea > 1.7) {
        unc = true;
        reason = 'nagy folt, lehet több lövés';
      }
      holes.add(Hole(x, y, bi, n, unc, reason));
    }
  }
  return holes;
}
