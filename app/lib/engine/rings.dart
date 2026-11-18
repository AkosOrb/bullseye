// Gyűrűmodell: a mért gyűrűkörökből folytonos "gyűrűkoordináta".
import 'dart:math' as math;

import 'calibrate.dart';
import 'imaging.dart';
import 'target.dart';

class RingModel {
  final TargetSpec spec;
  late final List<double> n, cx, cy, r;
  final Map<int, double> halfWidth = {};
  final double spacing;

  RingModel(Calibration cal, TargetSpec spec) : this.fromFits(cal.ringFits, cal.spacing, spec);

  RingModel.fromFits(Map<int, RingFit> fits, this.spacing, this.spec) {
    final ks = fits.keys.toList()..sort((a, b) => spec.ringRadius(a).compareTo(spec.ringRadius(b)));
    final nn = [for (final k in ks) spec.ringRadius(k)];
    final xx = [for (final k in ks) fits[k]!.cx];
    final yy = [for (final k in ks) fits[k]!.cy];
    final rr = [for (final k in ks) fits[k]!.r];
    for (final k in ks) {
      halfWidth[k] = fits[k]!.halfWidth;
    }
    var sx = 0.0, sy = 0.0;
    if (nn.length >= 2) {
      sx = (xx[1] - xx[0]) / (nn[1] - nn[0]);
      sy = (yy[1] - yy[0]) / (nn[1] - nn[0]);
    }
    n = [0.0, ...nn];
    cx = [xx[0] - sx * nn[0], ...xx];
    cy = [yy[0] - sy * nn[0], ...yy];
    r = [0.0, ...rr];
  }

  double _interp(double t, List<double> arr) {
    if (t > n.last) {
      final slope = (arr.last - arr[arr.length - 2]) / (n.last - n[n.length - 2]);
      return arr.last + slope * (t - n.last);
    }
    return interp(t, n, arr);
  }

  (double, double, double) circle(double t) => (_interp(t, cx), _interp(t, cy), _interp(t, r));
  (double, double, double) ringCircle(int k) => circle(spec.ringRadius(k));

  (double, double) point(double t, double phi) {
    final (x, y, rr) = circle(t);
    return (x + rr * math.cos(phi), y + rr * math.sin(phi));
  }

  double _invertR(double d) {
    if (d > r.last) {
      final slope = (n.last - n[n.length - 2]) / (r.last - r[r.length - 2]);
      return n.last + slope * (d - r.last);
    }
    return interp(d, r, n);
  }

  /// Képpont -> (t, phi).
  (double, double) coords(double x, double y) {
    var t = math.sqrt((x - cx[1]) * (x - cx[1]) + (y - cy[1]) * (y - cy[1])) / spacing;
    for (var i = 0; i < 6; i++) {
      final (ccx, ccy, _) = circle(t);
      t = _invertR(math.sqrt((x - ccx) * (x - ccx) + (y - ccy) * (y - ccy)));
    }
    final (ccx, ccy, _) = circle(t);
    return (t, math.atan2(y - ccy, x - ccx));
  }

  /// Előjeles távolság a k gyűrű pontozási szélétől (a vonal külső széle).
  double halfWidthOf(int k) {
    final hw = halfWidth[k];
    if (hw != null) return hw;
    final vals = halfWidth.values.where((v) => v > 0).toList();
    return vals.isEmpty ? 0.0 : median(vals);
  }

  double signedDistToRing(double x, double y, int k) {
    final (ccx, ccy, rr) = ringCircle(k);
    final hw = halfWidthOf(k);
    return math.sqrt((x - ccx) * (x - ccx) + (y - ccy) * (y - ccy)) - (rr + hw);
  }
}
