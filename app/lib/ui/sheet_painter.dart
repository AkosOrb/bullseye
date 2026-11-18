// A lap fotójára rajzolt jelölések: kör minden találatnál, mellette
// "sorszám: pont" címke. A címkék elhelyezése mohó: az első olyan hely, ahol
// nem takar másik címkét vagy kört.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import 'theme.dart';

class SheetPainter extends CustomPainter {
  SheetPainter({
    required this.views,
    required this.imageSize,
    required this.pelletRadius,
    this.selectedId,
    this.labelScale = 1.0,
    this.showLabels = true,
  });

  final List<ShotView> views;
  final Size imageSize; // a fotó mérete képpontban
  final double pelletRadius; // képpontban, a fotón
  final String? selectedId;
  /// A címkék mérete: 1/nagyítás, hogy nagyításkor is olvashatók maradjanak.
  final double labelScale;
  final bool showLabels;

  static Color colorFor(ShotView v, {bool selected = false}) {
    if (selected) return kSelectedColor;
    if (v.needsCheck) return kCheckColor;
    if (v.overridden || !v.shot.auto) return kEditedColor;
    return kShotColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / imageSize.width; // fotó px -> rajz px
    final r = math.max(pelletRadius * 1.15 * s, 5.0);
    final stroke = 2.2 * labelScale;
    final circles = <(Offset, double)>[];
    for (final v in views) {
      final c = Offset(v.shot.x * s, v.shot.y * s);
      final sel = v.shot.id == selectedId;
      final col = colorFor(v, selected: sel);
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 2.5 * labelScale
        ..color = kInk.withValues(alpha: 0.8));
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = col);
      if (v.needsCheck) {
        _dashedCircle(canvas, c, r + 5 * labelScale, col, stroke * 0.8);
      }
      if (sel) {
        canvas.drawCircle(c, 2.5 * labelScale, Paint()..color = col);
      }
      circles.add((c, r + 2 * labelScale));
    }
    if (!showLabels) return;
    final placed = <Rect>[];
    final labels = <(Rect, Offset, Color, TextPainter, double, double)>[];
    final fontSize = 12.5 * labelScale;
    for (final v in views) {
      final c = Offset(v.shot.x * s, v.shot.y * s);
      final sel = v.shot.id == selectedId;
      final col = colorFor(v, selected: sel);
      final text = '${v.index}: ${v.score}${v.needsCheck ? '?' : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: kCream,
            fontFamily: kFont,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final padX = 4 * labelScale, padY = 2 * labelScale;
      final bw = tp.width + 2 * padX, bh = tp.height + 2 * padY;
      // Az első ütközésmentes hely; ha nincs ilyen, a legkisebb átfedésű.
      Rect? best;
      var bestCost = double.infinity;
      for (final dist in [3, 12, 24, 40, 60, 85, 115, 150]) {
        final d = r + dist * labelScale;
        for (final deg in const [0, 180, -40, 40, -140, 140, -90, 90, 20, 160, -20, -160, -65, 65, -115, 115]) {
          final a = deg * math.pi / 180;
          final ax = c.dx + math.cos(a) * d, ay = c.dy + math.sin(a) * d;
          final double x0;
          if (math.cos(a).abs() < 0.35) {
            x0 = ax - bw / 2;
          } else {
            x0 = math.cos(a) > 0 ? ax : ax - bw;
          }
          final y0 = math.sin(a).abs() < 0.5 ? ay - bh / 2 : (math.sin(a) < 0 ? ay - bh : ay);
          final rect = Rect.fromLTWH(x0, y0, bw, bh);
          if (rect.left < 0 || rect.top < 0 || rect.right > size.width || rect.bottom > size.height) continue;
          var cost = 0.0;
          for (final p in placed) {
            final i = p.inflate(1.5 * labelScale).intersect(rect);
            if (i.width > 0 && i.height > 0) cost += i.width * i.height;
          }
          for (final cc in circles) {
            if (_circleHitsRect(cc.$1, cc.$2, rect)) cost += cc.$2 * cc.$2;
          }
          // távolabbi helyek enyhe büntetése, hogy egyenlő esetben közel maradjon
          cost += dist * 0.01;
          if (cost < bestCost) {
            bestCost = cost;
            best = rect;
          }
        }
        if (bestCost < 1) break;
      }
      best ??= Rect.fromLTWH(c.dx + r, c.dy - bh / 2, bw, bh);
      placed.add(best);
      labels.add((best, c, col, tp, padX, padY));
    }
    // Előbb a vezetővonalak, utána a címkék, hogy vonal ne takarjon szöveget.
    for (final (box, c, col, _, _, _) in labels) {
      final nearest = Offset(box.center.dx.clamp(box.left, box.right), box.center.dy);
      if ((nearest - c).distance > r + 8 * labelScale) {
        final dir = (box.center - c);
        final start = c + dir / dir.distance * r;
        canvas.drawLine(start, _closestPoint(box, start), Paint()
          ..color = col
          ..strokeWidth = 1.2 * labelScale);
      }
    }
    for (final (box, _, col, tp, padX, padY) in labels) {
      final rr = RRect.fromRectAndRadius(box, Radius.circular(4 * labelScale));
      canvas.drawRRect(rr, Paint()..color = kInk.withValues(alpha: 0.92));
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * labelScale
        ..color = col);
      tp.paint(canvas, Offset(box.left + padX, box.top + padY));
    }
  }

  static Offset _closestPoint(Rect r, Offset p) =>
      Offset(p.dx.clamp(r.left, r.right), p.dy.clamp(r.top, r.bottom));

  static bool _circleHitsRect(Offset c, double r, Rect rect) {
    final p = _closestPoint(rect, c);
    return (p - c).distance < r;
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Color col, double w) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = col;
    const n = 16;
    for (var i = 0; i < n; i++) {
      final a0 = i * 2 * math.pi / n;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, math.pi / n, false, paint);
    }
  }

  @override
  bool shouldRepaint(SheetPainter old) => true;
}
