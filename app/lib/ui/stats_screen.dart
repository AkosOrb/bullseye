import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/stats.dart';
import '../data/store.dart';
import '../engine/target.dart';
import 'new_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Range { lastSession, last30, all }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Range _range = _Range.all;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final all = store.allSheetsChronological();
    if (all.isEmpty) {
      return CustomScrollView(slivers: [
        const SliverAppBar(title: Text('Statisztika'), pinned: true),
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.insights_outlined,
            title: 'Még nincs mit elemezni',
            body: 'A kiértékelt lapokból itt látod az átlagodat, a fejlődésedet és azt, hogy merre húz a csoportod.',
            actionLabel: 'Lap fotózása',
            actionIcon: Icons.photo_camera_outlined,
            onAction: () => startNewSheet(context),
          ),
        ),
      ]);
    }
    final now = DateTime.now();
    final List<(Session, Sheet)> sel;
    switch (_range) {
      case _Range.lastSession:
        final last = all.last.$1;
        sel = all.where((e) => e.$1 == last).toList();
      case _Range.last30:
        sel = all.where((e) => now.difference(e.$2.createdAt).inDays <= 30).toList();
      case _Range.all:
        sel = all;
    }
    final totals = [for (final e in sel) e.$2.total];
    final shots = sel.fold<int>(0, (a, e) => a + e.$2.shots.length);
    final sum = totals.fold<int>(0, (a, b) => a + b);
    final offsets = [for (final e in sel) ...shotOffsets(e.$2)];
    final group = groupStats(offsets);
    // edzésenkénti átlag (fejlődés)
    final sessions = store.sessions.reversed.where((s) => s.sheets.isNotEmpty).toList();

    return CustomScrollView(slivers: [
      const SliverAppBar(title: Text('Statisztika'), pinned: true),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        sliver: SliverList.list(children: [
          SegmentedButton<_Range>(
            segments: const [
              ButtonSegment(value: _Range.lastSession, label: Text('Utolsó edzés')),
              ButtonSegment(value: _Range.last30, label: Text('30 nap')),
              ButtonSegment(value: _Range.all, label: Text('Összes')),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _range = v.first),
          ),
          const SizedBox(height: 12),
          if (sel.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Ebben az időszakban nincs kiértékelt lap.', textAlign: TextAlign.center),
            )
          else ...[
            StatGrid(children: [
                StatTile(label: 'Lapok', value: '${sel.length}', sub: '$shots lövés'),
                StatTile(label: 'Átlag / lap', value: fmtNum(sum / sel.length)),
                StatTile(label: 'Legjobb lap', value: '${totals.reduce(math.max)}'),
                StatTile(label: 'Átlag / lövés', value: shots == 0 ? '–' : fmtNum(sum / shots, 2)),
              ],
            ),
            SectionHeader(sel.length > 1 ? 'Lapok pontszáma időrendben' : 'Lap pontszáma'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: SizedBox(height: 200, child: _TotalsChart(values: totals, average: sum / sel.length)),
              ),
            ),
            if (_range == _Range.all && sessions.length >= 2) ...[
              const SectionHeader('Fejlődés: edzésenkénti átlag / lap'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: SizedBox(
                    height: 180,
                    child: _TotalsChart(
                      values: [for (final s in sessions) s.averagePerSheet],
                      average: null,
                      xLabel: (i) => fmtShortDate(sessions[i].date).substring(6),
                    ),
                  ),
                ),
              ),
            ],
            const SectionHeader('Találati kép'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: TargetDiagram(points: offsets, group: group, spec: sel.first.$2.spec),
                  ),
                  const SizedBox(height: 12),
                  if (group != null) ...[
                    Text(group.describe(), style: t.textTheme.titleMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      'Szórás: átlagosan ${fmtNum(group.spread, 0)} mm a csoport közepétől, '
                      'legnagyobb távolság két lövés között ${fmtNum(group.maxSpread, 0)} mm.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _TotalsChart extends StatelessWidget {
  const _TotalsChart({required this.values, required this.average, this.xLabel});
  final List<num> values;
  final double? average;
  final String Function(int i)? xLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final ds = [for (final v in values) v.toDouble()];
    final minV = ds.reduce(math.min), maxV = ds.reduce(math.max);
    final pad = math.max(5.0, (maxV - minV) * 0.15);
    final grid = cs.outlineVariant.withValues(alpha: 0.5);
    final labelStyle = t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    return LineChart(
      LineChartData(
        minY: (minV - pad).floorToDouble(),
        maxY: (maxV + pad).ceilToDouble(),
        minX: 0,
        maxX: math.max(1, values.length - 1).toDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => v == m.max || v == m.min ? const SizedBox() : Text(v.toInt().toString(), style: labelStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: math.max(1, (values.length / 6).ceil()).toDouble(),
              getTitlesWidget: (v, m) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= values.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(xLabel?.call(i) ?? '${i + 1}.', style: labelStyle),
                );
              },
            ),
          ),
        ),
        extraLinesData: average == null
            ? null
            : ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: average!,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: labelStyle,
                    labelResolver: (l) => 'átlag ${fmtNum(l.y)}',
                  ),
                ),
              ]),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(fmtNum(s.y, s.y == s.y.roundToDouble() ? 0 : 1), TextStyle(color: cs.onInverseSurface)),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].toDouble())],
            color: cs.primary,
            barWidth: 2.5,
            isCurved: false,
            dotData: FlDotData(
              show: values.length <= 40,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 3, color: cs.primary, strokeWidth: 0),
            ),
          ),
        ],
      ),
    );
  }
}

/// A lőlap sematikus rajza a lövések helyével és a csoport közepével.
/// Koppintásra teljes képernyőn, nagyíthatóan nyílik meg.
class TargetDiagram extends StatelessWidget {
  const TargetDiagram({super.key, required this.points, required this.group, required this.spec, this.zoomable = true});
  final List<(double, double)> points; // mm, jobbra/felfelé +
  final GroupStats? group;
  final TargetSpec spec;
  final bool zoomable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final paint = Semantics(
      label: 'Találati kép: ${points.length} lövés. ${group?.describe() ?? ''}',
      button: zoomable,
      child: CustomPaint(painter: _TargetPainter(points, group, spec, t.colorScheme)),
    );
    if (!zoomable) return paint;
    return Tooltip(
      message: 'Találati kép nagyítása',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _TargetZoomPage(points: points, group: group, spec: spec))),
        child: Stack(children: [
          Positioned.fill(child: paint),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: kInk, shape: BoxShape.circle),
              child: const Icon(Icons.zoom_in, size: 16, color: kCream),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Teljes képernyős, nagyítható találati kép (csippentés, dupla koppintás).
class _TargetZoomPage extends StatefulWidget {
  const _TargetZoomPage({required this.points, required this.group, required this.spec});
  final List<(double, double)> points;
  final GroupStats? group;
  final TargetSpec spec;
  @override
  State<_TargetZoomPage> createState() => _TargetZoomPageState();
}

class _TargetZoomPageState extends State<_TargetZoomPage> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() {
      final tw = _tween;
      if (tw != null) _tc.value = tw.evaluate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    });
  Matrix4Tween? _tween;
  Offset _tapPos = Offset.zero;

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _toggle() {
    const s = 3.0;
    final zoomed = _tc.value.getMaxScaleOnAxis() > 1.05;
    final p = _tc.toScene(_tapPos);
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
          ..scaleByDouble(s, s, 1, 1));
    _tween = Matrix4Tween(begin: _tc.value.clone(), end: target);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final g = widget.group;
    return Scaffold(
      appBar: AppBar(title: const Text('Találati kép')),
      body: Column(children: [
        Expanded(
          child: GestureDetector(
            onDoubleTapDown: (d) => _tapPos = d.localPosition,
            onDoubleTap: _toggle,
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 12,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TargetDiagram(points: widget.points, group: g, spec: widget.spec, zoomable: false),
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.points.length} lövés${g != null && g.n >= 3 ? ' · ${g.describe()}' : ''}',
                  style: t.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Csippentéssel vagy dupla koppintással nagyíthatsz. A sárga kör a szórás, a kereszt a csoport közepe.',
                  style: t.textTheme.bodySmall?.copyWith(color: kTaupe)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _TargetPainter extends CustomPainter {
  _TargetPainter(this.points, this.group, this.spec, this.cs);
  final List<(double, double)> points;
  final GroupStats? group;
  final TargetSpec spec;
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // a látható tartomány: a legtávolabbi lövés vagy a fekete korong, ami nagyobb
    var maxMm = spec.blackRadius * spec.ringSpacingMm;
    for (final p in points) {
      maxMm = math.max(maxMm, math.sqrt(p.$1 * p.$1 + p.$2 * p.$2) + 4);
    }
    maxMm = math.min(maxMm, spec.ringRadius(1) * spec.ringSpacingMm);
    final k = size.shortestSide / 2 / maxMm;
    Offset at(double x, double y) => c + Offset(x * k, -y * k);
    // fekete korong + gyűrűk
    canvas.drawCircle(c, spec.blackRadius * spec.ringSpacingMm * k, Paint()..color = const Color(0xFF2B2B2B));
    canvas.drawCircle(c, spec.whiteDiskRadius * spec.ringSpacingMm * k, Paint()..color = kCream);
    for (var ring = 1; ring <= spec.ringCount; ring++) {
      final r = spec.ringRadius(ring) * spec.ringSpacingMm * k;
      if (r > size.shortestSide / 2 + 1) continue;
      final inBlack = ring > spec.blackOuterRing && ring <= spec.blackInnerRing;
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = inBlack ? const Color(0xAAFFFFFF) : const Color(0x88000000));
    }
    final rp = spec.pelletDiameterMm / 2 * k;
    final dot = Paint()..color = kShotColor.withValues(alpha: 0.75);
    for (final p in points) {
      canvas.drawCircle(at(p.$1, p.$2), math.max(rp, 2.5), dot);
    }
    final g = group;
    if (g != null && g.n >= 3) {
      final gc = at(g.meanX, g.meanY);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kYellow;
      canvas.drawCircle(gc, g.spread * k, ring);
      canvas.drawLine(gc - const Offset(7, 0), gc + const Offset(7, 0), ring);
      canvas.drawLine(gc - const Offset(0, 7), gc + const Offset(0, 7), ring);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetPainter old) => true;
}
