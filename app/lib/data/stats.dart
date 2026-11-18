// Statisztikák: körönkénti eloszlás, legjobb/leggyengébb lövés, szórásminta.
import 'dart:math' as math;

import 'models.dart';

class RingRow {
  final int score;
  final int count;
  const RingRow(this.score, this.count);
}

/// Hány lövés esett az egyes gyűrűkbe (csak az előforduló értékek, csökkenő sorrendben).
List<RingRow> ringDistribution(List<ShotView> views) {
  final m = <int, int>{};
  for (final v in views) {
    m[v.score] = (m[v.score] ?? 0) + 1;
  }
  final keys = m.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) RingRow(k, m[k]!)];
}

class GroupStats {
  final int n;
  final double meanX, meanY; // mm, jobbra/felfelé +
  final double spread; // a lövések átlagos távolsága a csoport közepétől (mm)
  final double maxSpread; // legnagyobb távolság két lövés között (mm)
  const GroupStats(this.n, this.meanX, this.meanY, this.spread, this.maxSpread);

  double get offset => math.sqrt(meanX * meanX + meanY * meanY);

  /// Szöveges irány, pl. „bal felső irányba húz (kb. 6 mm)”.
  String describe({double centredMm = 3}) {
    if (n < 3) return 'Legalább 3 lövés kell a szórásminta elemzéséhez.';
    if (offset < centredMm) return 'A csoport közepe a célközépponton van.';
    final a = math.atan2(meanY, meanX) * 180 / math.pi; // 0 = jobbra, 90 = fel
    const names = [
      'jobbra',
      'jobb felső irányba',
      'felfelé',
      'bal felső irányba',
      'balra',
      'bal alsó irányba',
      'lefelé',
      'jobb alsó irányba',
    ];
    final idx = (((a + 360) % 360 + 22.5) ~/ 45) % 8;
    return '${_cap(names[idx])} húz (kb. ${offset.toStringAsFixed(0)} mm).';
  }
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

GroupStats? groupStats(List<(double, double)> pts) {
  if (pts.isEmpty) return null;
  final n = pts.length;
  final mx = pts.fold(0.0, (a, p) => a + p.$1) / n;
  final my = pts.fold(0.0, (a, p) => a + p.$2) / n;
  var s = 0.0;
  for (final p in pts) {
    s += math.sqrt((p.$1 - mx) * (p.$1 - mx) + (p.$2 - my) * (p.$2 - my));
  }
  var ext = 0.0;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final d = math.sqrt(math.pow(pts[i].$1 - pts[j].$1, 2) + math.pow(pts[i].$2 - pts[j].$2, 2));
      if (d > ext) ext = d;
    }
  }
  return GroupStats(n, mx, my, s / n, ext);
}

/// A lövések célközépponthoz viszonyított helye mm-ben.
List<(double, double)> shotOffsets(Sheet sheet) {
  final g = sheet.geometry;
  if (g == null) return const [];
  return [
    for (final v in sheet.views())
      if (v.computed != null) (v.computed!.dxMm, v.computed!.dyMm)
  ];
}
