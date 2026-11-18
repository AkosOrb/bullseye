// A lövésnyom (lyuk + koromgyűrű) sugarának mérése lövésenként.
//
// A lyuk középpontjából sugárirányban kifelé haladva megkeressük, hol tűnik el
// a nyom (a háttérhez mért eltérés a középső érték fele alá esik). Egymásba lőtt
// lyukaknál a szomszéd felé eső irányok hosszabbak, ezért alsó percentilist veszünk.
import 'dart:math' as math;
import 'dart:typed_data';

import 'imaging.dart';

const _edgeFrac = 0.5;

double? measureHoleRadius(Float32List sig, Mask valid, int size, double x, double y, double rp) {
  double at(double px, double py) {
    final ix = px.round(), iy = py.round();
    if (ix < 0 || iy < 0 || ix >= size || iy >= size) return double.nan;
    final i = iy * size + ix;
    if (valid.d[i] == 0) return double.nan;
    return sig[i];
  }

  const nAng = 36;
  final step = math.max(0.5, rp / 12);
  final edges = <double>[];
  for (var a = 0; a < nAng; a++) {
    final ang = a * 2 * math.pi / nAng;
    final ca = math.cos(ang), sa = math.sin(ang);
    // sugárirányú profil
    final rs = <double>[], vs = <double>[];
    for (var r = 0.0; r <= rp * 2.2; r += step) {
      final v = at(x + r * ca, y + r * sa);
      if (v.isNaN) break;
      rs.add(r);
      vs.add(v);
    }
    if (rs.length < 4) continue;
    // a nyom legerősebb része (lyuk vagy koromgyűrű) a névleges sugáron belül
    var pk = -1, pv = 0.0;
    for (var i = 0; i < rs.length && rs[i] <= rp * 1.3; i++) {
      if (vs[i] > pv) {
        pv = vs[i];
        pk = i;
      }
    }
    if (pk < 0 || pv < 12) continue;
    for (var i = pk + 1; i < rs.length; i++) {
      if (vs[i] < pv * _edgeFrac) {
        // a félértékhely lineáris becslése
        final f = (vs[i - 1] - pv * _edgeFrac) / math.max(1e-6, vs[i - 1] - vs[i]);
        edges.add(rs[i - 1] + f * (rs[i] - rs[i - 1]));
        break;
      }
    }
  }
  if (edges.length < nAng / 3) return null;
  final r = percentile(edges, 40);
  if (r < rp * 0.6 || r > rp * 1.6) return null;
  return r;
}
