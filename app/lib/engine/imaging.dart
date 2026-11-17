// Alapvető képfeldolgozó műveletek tiszta Dartban (OpenCV nélkül), hogy az
// app natív függőség nélkül fusson Androidon és iOS-en is.
//
// A Python motor (engine/) cv2-hívásainak megfelelői.
import 'dart:math' as math;
import 'dart:typed_data';

/// Egycsatornás lebegőpontos kép.
class Gray {
  final int w;
  final int h;
  final Float32List d;

  Gray(this.w, this.h) : d = Float32List(w * h);
  Gray.from(this.w, this.h, this.d);

  double at(int x, int y) => d[y * w + x];

  Gray copy() => Gray.from(w, h, Float32List.fromList(d));

  /// Bilineáris mintavétel; képen kívül [outside].
  double sample(double x, double y, [double outside = double.nan]) {
    if (x < 0 || y < 0 || x > w - 1 || y > h - 1) return outside;
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
    final fx = x - x0, fy = y - y0;
    final a = d[y0 * w + x0], b = d[y0 * w + x1];
    final c = d[y1 * w + x0], e = d[y1 * w + x1];
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + e * fx) * fy;
  }
}

/// Bináris maszk.
class Mask {
  final int w;
  final int h;
  final Uint8List d;

  Mask(this.w, this.h) : d = Uint8List(w * h);
  Mask.from(this.w, this.h, this.d);

  bool get(int x, int y) => d[y * w + x] != 0;
  void set(int x, int y, bool v) => d[y * w + x] = v ? 1 : 0;
  Mask copy() => Mask.from(w, h, Uint8List.fromList(d));

  int count() {
    var n = 0;
    for (final v in d) {
      if (v != 0) n++;
    }
    return n;
  }

  Mask and(Mask o) {
    final r = Mask(w, h);
    for (var i = 0; i < d.length; i++) {
      r.d[i] = (d[i] != 0 && o.d[i] != 0) ? 1 : 0;
    }
    return r;
  }

  Mask or(Mask o) {
    final r = Mask(w, h);
    for (var i = 0; i < d.length; i++) {
      r.d[i] = (d[i] != 0 || o.d[i] != 0) ? 1 : 0;
    }
    return r;
  }

  Mask not() {
    final r = Mask(w, h);
    for (var i = 0; i < d.length; i++) {
      r.d[i] = d[i] != 0 ? 0 : 1;
    }
    return r;
  }
}

/// RGB kép (8 bit/csatorna, soronként RGBRGB...).
class Rgb {
  final int w;
  final int h;
  final Uint8List d;
  Rgb(this.w, this.h, this.d);

  Gray toGray() {
    final g = Gray(w, h);
    for (var i = 0, j = 0; i < w * h; i++, j += 3) {
      g.d[i] = 0.299 * d[j] + 0.587 * d[j + 1] + 0.114 * d[j + 2];
    }
    return g;
  }

  /// Teljesen fehér (>=254) képpontok – a kép körüli kitöltés felismeréséhez.
  Mask pureWhite() {
    final m = Mask(w, h);
    for (var i = 0, j = 0; i < w * h; i++, j += 3) {
      m.d[i] = (d[j] >= 254 && d[j + 1] >= 254 && d[j + 2] >= 254) ? 1 : 0;
    }
    return m;
  }
}

// ---------------------------------------------------------------------------
// Szűrők

Float32List _gaussKernel(double sigma) {
  final r = math.max(1, (sigma * 3).ceil());
  final k = Float32List(2 * r + 1);
  var s = 0.0;
  for (var i = -r; i <= r; i++) {
    final v = math.exp(-(i * i) / (2 * sigma * sigma));
    k[i + r] = v;
    s += v;
  }
  for (var i = 0; i < k.length; i++) {
    k[i] /= s;
  }
  return k;
}

/// Szétválasztható Gauss-elmosás (tükrözött széllel).
Gray gaussianBlur(Gray src, double sigma) {
  final k = _gaussKernel(sigma);
  final r = k.length ~/ 2;
  final w = src.w, h = src.h;
  final tmp = Float32List(w * h);
  final out = Gray(w, h);
  int refl(int i, int n) {
    if (n == 1) return 0;
    while (i < 0 || i >= n) {
      if (i < 0) i = -i;
      if (i >= n) i = 2 * n - 2 - i;
    }
    return i;
  }

  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        s += k[i + r] * src.d[row + refl(x + i, w)];
      }
      tmp[row + x] = s;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        s += k[i + r] * tmp[refl(y + i, h) * w + x];
      }
      out.d[y * w + x] = s;
    }
  }
  return out;
}

/// Négyzetes min/max szűrő (szétválasztható), [rad] sugárral.
Gray minMaxFilter(Gray src, int rad, {required bool isMax}) {
  final w = src.w, h = src.h;
  final tmp = Float32List(w * h);
  final out = Gray(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = isMax ? -double.infinity : double.infinity;
      for (var i = math.max(0, x - rad); i <= math.min(w - 1, x + rad); i++) {
        final s = src.d[y * w + i];
        if (isMax ? s > v : s < v) v = s;
      }
      tmp[y * w + x] = v;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = isMax ? -double.infinity : double.infinity;
      for (var i = math.max(0, y - rad); i <= math.min(h - 1, y + rad); i++) {
        final s = tmp[i * w + x];
        if (isMax ? s > v : s < v) v = s;
      }
      out.d[y * w + x] = v;
    }
  }
  return out;
}

/// Otsu-küszöb a maszkolt képpontokra (0..255 tartomány).
double otsu(Gray g, Mask valid) {
  final hist = List<int>.filled(256, 0);
  var n = 0;
  for (var i = 0; i < g.d.length; i++) {
    if (valid.d[i] == 0) continue;
    hist[g.d[i].round().clamp(0, 255)]++;
    n++;
  }
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, thr = 0;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = n - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      thr = t;
    }
  }
  return thr.toDouble();
}

// ---------------------------------------------------------------------------
// Bináris morfológia euklideszi távolságtranszformációval (pontos kör alakú
// strukturáló elem bármekkora sugárra, O(N)).

const double _inf = 1e20;

void _edt1d(Float64List f, int n, Float64List d, Int32List v, Float64List z) {
  var k = 0;
  v[0] = 0;
  z[0] = -_inf;
  z[1] = _inf;
  for (var q = 1; q < n; q++) {
    var s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    while (s <= z[k]) {
      k--;
      s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    }
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = _inf;
  }
  k = 0;
  for (var q = 0; q < n; q++) {
    while (z[k + 1] < q) {
      k++;
    }
    d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
  }
}

/// Négyzetes távolság a legközelebbi "be" képponttól ([m] != 0 ? 0 : távolság²).
Float64List sqDistTo(Mask m) {
  final w = m.w, h = m.h;
  final n = math.max(w, h);
  final f = Float64List(n), d = Float64List(n), z = Float64List(n + 1);
  final v = Int32List(n);
  final g = Float64List(w * h);
  for (var i = 0; i < w * h; i++) {
    g[i] = m.d[i] != 0 ? 0 : _inf;
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      f[y] = g[y * w + x];
    }
    _edt1d(f, h, d, v, z);
    for (var y = 0; y < h; y++) {
      g[y * w + x] = d[y];
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      f[x] = g[y * w + x];
    }
    _edt1d(f, w, d, v, z);
    for (var x = 0; x < w; x++) {
      g[y * w + x] = d[x];
    }
  }
  return g;
}

/// cv2 ellipszis-kernel (k×k) sugara.
double kernelRadius(int k) => (k - 1) / 2.0 + 0.25;

Mask dilateDisk(Mask m, double r) {
  final dist = sqDistTo(m);
  final out = Mask(m.w, m.h);
  final r2 = r * r;
  for (var i = 0; i < dist.length; i++) {
    out.d[i] = dist[i] <= r2 ? 1 : 0;
  }
  return out;
}

Mask erodeDisk(Mask m, double r) {
  final dist = sqDistTo(m.not());
  final out = Mask(m.w, m.h);
  final r2 = r * r;
  for (var i = 0; i < dist.length; i++) {
    out.d[i] = dist[i] > r2 ? 1 : 0;
  }
  return out;
}

Mask closeDisk(Mask m, double r) => erodeDisk(dilateDisk(m, r), r);
Mask openDisk(Mask m, double r) => dilateDisk(erodeDisk(m, r), r);

/// Négyzetes erózió (a cv2.erode(np.ones((k,k))) megfelelője).
Mask erodeSquare(Mask m, int rad) {
  final g = Gray(m.w, m.h);
  for (var i = 0; i < m.d.length; i++) {
    g.d[i] = m.d[i].toDouble();
  }
  final e = minMaxFilter(g, rad, isMax: false);
  final out = Mask(m.w, m.h);
  for (var i = 0; i < m.d.length; i++) {
    out.d[i] = e.d[i] > 0.5 ? 1 : 0;
  }
  return out;
}

/// Lyukak kitöltése: ami a kép széléről nem érhető el "ki" képpontokon át.
Mask fillHoles(Mask m) {
  final w = m.w, h = m.h;
  final reach = Uint8List(w * h);
  final stack = <int>[];
  void push(int i) {
    if (m.d[i] == 0 && reach[i] == 0) {
      reach[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) push(i - 1);
    if (x < w - 1) push(i + 1);
    if (y > 0) push(i - w);
    if (y < h - 1) push(i + w);
  }
  final out = Mask(w, h);
  for (var i = 0; i < w * h; i++) {
    out.d[i] = (m.d[i] != 0 || reach[i] == 0) ? 1 : 0;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Összefüggő komponensek (8-szomszédság)

class Component {
  final int label;
  int area = 0;
  int x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
  double sx = 0, sy = 0;
  Component(this.label);
  double get cx => sx / area;
  double get cy => sy / area;
  int get bw => x1 - x0 + 1;
  int get bh => y1 - y0 + 1;
}

class Labels {
  final int w, h;
  final Int32List lab;
  final List<Component> comps; // comps[i].label == i + 1
  Labels(this.w, this.h, this.lab, this.comps);
}

Labels connectedComponents(Mask m) {
  final w = m.w, h = m.h;
  final lab = Int32List(w * h);
  final comps = <Component>[];
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (m.d[start] == 0 || lab[start] != 0) continue;
    final c = Component(comps.length + 1);
    comps.add(c);
    lab[start] = c.label;
    stack.add(start);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      c.area++;
      c.sx += x;
      c.sy += y;
      if (x < c.x0) c.x0 = x;
      if (x > c.x1) c.x1 = x;
      if (y < c.y0) c.y0 = y;
      if (y > c.y1) c.y1 = y;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w || (dx == 0 && dy == 0)) continue;
          final j = yy * w + xx;
          if (m.d[j] != 0 && lab[j] == 0) {
            lab[j] = c.label;
            stack.add(j);
          }
        }
      }
    }
  }
  return Labels(w, h, lab, comps);
}

// ---------------------------------------------------------------------------
// Geometria

/// 2×3 affin mátrix: [a, b, c, d, e, f] -> x' = a x + b y + c, y' = d x + e y + f.
class Affine {
  final double a, b, c, d, e, f;
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  (double, double) apply(double x, double y) => (a * x + b * y + c, d * x + e * y + f);

  Affine inverse() {
    final det = a * e - b * d;
    final ia = e / det, ib = -b / det, id = -d / det, ie = a / det;
    return Affine(ia, ib, -(ia * c + ib * f), id, ie, -(id * c + ie * f));
  }

  double get det => a * e - b * d;

  List<double> toList() => [a, b, c, d, e, f];
  static Affine fromList(List l) => Affine(
      (l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble(),
      (l[3] as num).toDouble(), (l[4] as num).toDouble(), (l[5] as num).toDouble());
}

/// Kép transzformálása: out(x', y') = src(A⁻¹(x', y')).
Gray warpAffine(Gray src, Affine a, int size, {double border = 0}) {
  final inv = a.inverse();
  final out = Gray(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final (sx, sy) = inv.apply(x.toDouble(), y.toDouble());
      final v = src.sample(sx, sy, border);
      out.d[y * size + x] = v.isNaN ? border : v;
    }
  }
  return out;
}

Mask warpMask(Mask src, Affine a, int size) {
  final inv = a.inverse();
  final out = Mask(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final (sx, sy) = inv.apply(x.toDouble(), y.toDouble());
      final ix = sx.round(), iy = sy.round();
      if (ix >= 0 && iy >= 0 && ix < src.w && iy < src.h && src.d[iy * src.w + ix] != 0) {
        out.d[y * size + x] = 1;
      }
    }
  }
  return out;
}

/// Ellipszis: középpont, féltengelyek ([a] a [angle] irányában), szög radiánban.
class Ellipse {
  final double cx, cy, a, b, angle;
  const Ellipse(this.cx, this.cy, this.a, this.b, this.angle);

  /// Közelítő távolság az ellipszis vonalától (képpontban).
  double residual(double x, double y) {
    final c = math.cos(angle), s = math.sin(angle);
    final dx = x - cx, dy = y - cy;
    final u = dx * c + dy * s, v = -dx * s + dy * c;
    final rr = math.sqrt((u / a) * (u / a) + (v / b) * (v / b));
    return (rr - 1).abs() * (a + b) / 2;
  }
}

/// Közvetlen legkisebb négyzetes ellipszisillesztés (Halíř–Flusser).
Ellipse? fitEllipse(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 6) return null;
  // normalizálás a numerikus stabilitásért
  var mx = 0.0, my = 0.0;
  for (var i = 0; i < n; i++) {
    mx += xs[i];
    my += ys[i];
  }
  mx /= n;
  my /= n;
  var sc = 0.0;
  for (var i = 0; i < n; i++) {
    sc += math.sqrt((xs[i] - mx) * (xs[i] - mx) + (ys[i] - my) * (ys[i] - my));
  }
  sc = sc / n;
  if (sc < 1e-9) return null;
  // S1 = D1ᵀD1, S2 = D1ᵀD2, S3 = D2ᵀD2 ; D1 = [x², xy, y²], D2 = [x, y, 1]
  final s1 = List.generate(3, (_) => List<double>.filled(3, 0));
  final s2 = List.generate(3, (_) => List<double>.filled(3, 0));
  final s3 = List.generate(3, (_) => List<double>.filled(3, 0));
  for (var i = 0; i < n; i++) {
    final x = (xs[i] - mx) / sc, y = (ys[i] - my) / sc;
    final d1 = [x * x, x * y, y * y];
    final d2 = [x, y, 1.0];
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        s1[r][c] += d1[r] * d1[c];
        s2[r][c] += d1[r] * d2[c];
        s3[r][c] += d2[r] * d2[c];
      }
    }
  }
  final s3i = _inv3(s3);
  if (s3i == null) return null;
  // T = -S3⁻¹ S2ᵀ
  final t = List.generate(3, (_) => List<double>.filled(3, 0));
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      var v = 0.0;
      for (var k = 0; k < 3; k++) {
        v += s3i[r][k] * s2[c][k];
      }
      t[r][c] = -v;
    }
  }
  // M = S1 + S2 T
  final m = List.generate(3, (_) => List<double>.filled(3, 0));
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      var v = s1[r][c];
      for (var k = 0; k < 3; k++) {
        v += s2[r][k] * t[k][c];
      }
      m[r][c] = v;
    }
  }
  // M = C1⁻¹ M ; C1⁻¹ = [[0,0,0.5],[0,-1,0],[0.5,0,0]]
  final mm = [
    [m[2][0] / 2, m[2][1] / 2, m[2][2] / 2],
    [-m[1][0], -m[1][1], -m[1][2]],
    [m[0][0] / 2, m[0][1] / 2, m[0][2] / 2],
  ];
  final evs = _eigvecs3(mm);
  List<double>? a1;
  for (final v in evs) {
    final cond = 4 * v[0] * v[2] - v[1] * v[1];
    if (cond > 0) {
      a1 = v;
      break;
    }
  }
  if (a1 == null) return null;
  final a2 = List<double>.filled(3, 0);
  for (var r = 0; r < 3; r++) {
    for (var k = 0; k < 3; k++) {
      a2[r] += t[r][k] * a1[k];
    }
  }
  // általános kúpszelet: A x² + B xy + C y² + D x + E y + F = 0 (normalizált koordinátákban)
  final aa = a1[0], bb = a1[1], cc = a1[2], dd = a2[0], ee = a2[1], ff = a2[2];
  final den = bb * bb - 4 * aa * cc;
  if (den.abs() < 1e-15) return null;
  final x0 = (2 * cc * dd - bb * ee) / den;
  final y0 = (2 * aa * ee - bb * dd) / den;
  final num = 2 * (aa * ee * ee + cc * dd * dd - bb * dd * ee + den * ff);
  final root = math.sqrt((aa - cc) * (aa - cc) + bb * bb);
  final l1 = -math.sqrt((num * (aa + cc + root)).abs()) / den;
  final l2 = -math.sqrt((num * (aa + cc - root)).abs()) / den;
  double theta;
  if (bb.abs() < 1e-15) {
    theta = aa < cc ? 0 : math.pi / 2;
  } else {
    theta = math.atan2(cc - aa - root, bb);
  }
  // l1 a theta irányú féltengely
  var semiA = l1.abs(), semiB = l2.abs();
  // ellenőrzés: a theta irányú tengely hossza a kúpszelet alapján
  final ct = math.cos(theta), st = math.sin(theta);
  double q(double r, double cs, double sn) {
    final x = x0 + r * cs, y = y0 + r * sn;
    return aa * x * x + bb * x * y + cc * y * y + dd * x + ee * y + ff;
  }

  if (q(semiA, ct, st).abs() > q(semiB, ct, st).abs()) {
    final tmp = semiA;
    semiA = semiB;
    semiB = tmp;
  }
  return Ellipse(x0 * sc + mx, y0 * sc + my, semiA * sc, semiB * sc, theta);
}

List<List<double>>? _inv3(List<List<double>> m) {
  final a = m[0][0], b = m[0][1], c = m[0][2];
  final d = m[1][0], e = m[1][1], f = m[1][2];
  final g = m[2][0], h = m[2][1], i = m[2][2];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-18) return null;
  return [
    [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
    [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
    [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det],
  ];
}

/// Valós sajátvektorok egy 3×3 (nem szimmetrikus) mátrixhoz.
List<List<double>> _eigvecs3(List<List<double>> m) {
  // karakterisztikus polinom: λ³ + p λ² + q λ + r = 0
  final tr = m[0][0] + m[1][1] + m[2][2];
  final minors = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) +
      (m[0][0] * m[2][2] - m[0][2] * m[2][0]) +
      (m[1][1] * m[2][2] - m[1][2] * m[2][1]);
  final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
      m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
      m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
  final roots = _cubicRoots(-tr, minors, -det);
  final out = <List<double>>[];
  for (final l in roots) {
    final a = [
      [m[0][0] - l, m[0][1], m[0][2]],
      [m[1][0], m[1][1] - l, m[1][2]],
      [m[2][0], m[2][1], m[2][2] - l],
    ];
    // sajátvektor: két sor vektoriális szorzata (a legnagyobb normájú)
    List<double> cross(List<double> u, List<double> v) =>
        [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    final cands = [cross(a[0], a[1]), cross(a[0], a[2]), cross(a[1], a[2])];
    cands.sort((p, q) => _norm(q).compareTo(_norm(p)));
    final v = cands.first;
    final nv = _norm(v);
    if (nv > 0) out.add([v[0] / nv, v[1] / nv, v[2] / nv]);
  }
  return out;
}

double _norm(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

List<double> _cubicRoots(double a, double b, double c) {
  // x³ + a x² + b x + c = 0
  final q = (a * a - 3 * b) / 9;
  final r = (2 * a * a * a - 9 * a * b + 27 * c) / 54;
  if (r * r < q * q * q) {
    final t = math.acos((r / math.sqrt(q * q * q)).clamp(-1.0, 1.0));
    final sq = -2 * math.sqrt(q);
    return [
      sq * math.cos(t / 3) - a / 3,
      sq * math.cos((t + 2 * math.pi) / 3) - a / 3,
      sq * math.cos((t - 2 * math.pi) / 3) - a / 3,
    ];
  }
  final aa = -(r.sign) * math.pow(r.abs() + math.sqrt(r * r - q * q * q), 1 / 3).toDouble();
  final bb = aa == 0 ? 0.0 : q / aa;
  return [(aa + bb) - a / 3];
}

/// Kör illesztése (algebrai legkisebb négyzetek): (cx, cy, r).
(double, double, double)? fitCircle(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 3) return null;
  // [2x 2y 1] [cx cy c]ᵀ = x² + y²
  final ata = List.generate(3, (_) => List<double>.filled(3, 0));
  final atb = List<double>.filled(3, 0);
  for (var i = 0; i < n; i++) {
    final row = [2 * xs[i], 2 * ys[i], 1.0];
    final bv = xs[i] * xs[i] + ys[i] * ys[i];
    for (var r = 0; r < 3; r++) {
      atb[r] += row[r] * bv;
      for (var c = 0; c < 3; c++) {
        ata[r][c] += row[r] * row[c];
      }
    }
  }
  final inv = _inv3(ata);
  if (inv == null) return null;
  final sol = List<double>.filled(3, 0);
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      sol[r] += inv[r][c] * atb[c];
    }
  }
  final r2 = sol[2] + sol[0] * sol[0] + sol[1] * sol[1];
  return (sol[0], sol[1], math.sqrt(math.max(r2, 1e-9)));
}

double median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = List<double>.from(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double percentile(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final s = List<double>.from(v)..sort();
  final pos = (s.length - 1) * p / 100.0;
  final lo = pos.floor(), hi = pos.ceil();
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

/// Lineáris interpoláció (np.interp megfelelője, növekvő [xp]).
double interp(double x, List<double> xp, List<double> fp) {
  if (x <= xp.first) return fp.first;
  if (x >= xp.last) return fp.last;
  var lo = 0, hi = xp.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (xp[mid] <= x) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final t = (x - xp[lo]) / (xp[hi] - xp[lo]);
  return fp[lo] + t * (fp[hi] - fp[lo]);
}

/// Normalizált keresztkorreláció (cv2.TM_CCOEFF_NORMED): a legjobb (dx, dy, érték)
/// a régión belül; [tpl] a sablon, [reg] a keresési régió.
(int, int, double, List<double>) matchTemplate(
    Gray src, int tx, int ty, int tw, int th, int rx, int ry, int rw, int rh) {
  // sablon: src[ty..ty+th, tx..tx+tw]; régió: src[ry..ry+rh, rx..rx+rw]
  final n = tw * th;
  final tpl = Float64List(n);
  var tm = 0.0;
  for (var y = 0; y < th; y++) {
    for (var x = 0; x < tw; x++) {
      final v = src.d[(ty + y) * src.w + tx + x];
      tpl[y * tw + x] = v;
      tm += v;
    }
  }
  tm /= n;
  var tn = 0.0;
  for (var i = 0; i < n; i++) {
    tpl[i] -= tm;
    tn += tpl[i] * tpl[i];
  }
  tn = math.sqrt(tn);
  final ow = rw - tw + 1, oh = rh - th + 1;
  final res = List<double>.filled(ow * oh, -1);
  var best = -2.0;
  var bx = 0, by = 0;
  for (var oy = 0; oy < oh; oy++) {
    for (var ox = 0; ox < ow; ox++) {
      var s = 0.0, s2 = 0.0, num = 0.0;
      for (var y = 0; y < th; y++) {
        final row = (ry + oy + y) * src.w + rx + ox;
        final trow = y * tw;
        for (var x = 0; x < tw; x++) {
          final v = src.d[row + x];
          s += v;
          s2 += v * v;
          num += v * tpl[trow + x];
        }
      }
      final varr = s2 - s * s / n;
      final den = math.sqrt(math.max(varr, 1e-9)) * tn;
      final r = den > 0 ? num / den : 0.0;
      res[oy * ow + ox] = r;
      if (r > best) {
        best = r;
        bx = ox;
        by = oy;
      }
    }
  }
  return (bx, by, best, res);
}
