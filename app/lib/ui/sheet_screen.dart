// Egy lap eredménye: jelölt fotó, fejléc, kézi javítás, táblázat.

import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/stats.dart';
import '../data/store.dart';
import '../services/analysis.dart';
import '../services/export.dart';
import 'sheet_painter.dart';
import 'theme.dart';
import 'widgets.dart';

class SheetScreen extends StatefulWidget {
  const SheetScreen({super.key, required this.sheet, this.fresh = false});
  final Sheet sheet;
  final bool fresh;
  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  String? _selected;
  bool _addMode = false;
  bool _busy = false; // újrakeresés folyamatban
  bool _showRings = false; // a tábla gyűrűinek megjelenítése
  bool _ringEdit = false; // gyűrűk kézi igazítása
  Offset? _ringDragLast;
  int _pointers = 0;
  late final AnimationController _zoomAnim;
  Matrix4Tween? _zoomTween;
  String? _resizedId; // ennek a lövésnek a körét állította át kézzel (még nem kérdeztük)
  bool _askingResize = false;
  bool _dragging = false;
  Offset? _dragStartShot;

  Sheet get sheet => widget.sheet;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() => setState(() {}));
    _zoomAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        final t = _zoomTween;
        if (t != null) _tc.value = t.evaluate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
      });
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _tc.dispose();
    super.dispose();
  }

  double get _viewScale => _tc.value.getMaxScaleOnAxis();

  Future<void> _save() => StoreScope.of(context).changed();

  Shot? get _selectedShot {
    for (final s in sheet.shots) {
      if (s.id == _selected) return s;
    }
    return null;
  }

  /// A rajzolt kép mérete (fotó px -> képernyő px arány).
  double _fitScale(BoxConstraints box) {
    final sx = box.maxWidth / sheet.imageW, sy = box.maxHeight / sheet.imageH;
    return sx < sy ? sx : sy;
  }

  Shot? _hitShot(Offset photoPos, double photoPerScreen) {
    final r = (sheet.geometry?.pelletRadiusOrig ?? 10) * 1.6 + 14 * photoPerScreen;
    Shot? best;
    var bd = double.infinity;
    for (final s in sheet.shots) {
      final d = (Offset(s.x, s.y) - photoPos).distance;
      if (d < r && d < bd) {
        bd = d;
        best = s;
      }
    }
    return best;
  }

  void _addShotAt(Offset p) {
    final s = Shot(id: newId(), x: p.dx, y: p.dy, auto: false);
    setState(() {
      sheet.shots.add(s);
      _selected = s.id;
      _addMode = false;
    });
    _save();
  }

  void _deleteSelected() {
    final s = _selectedShot;
    if (s == null) return;
    final idx = sheet.shots.indexOf(s);
    setState(() {
      sheet.shots.remove(s);
      _selected = null;
      if (_resizedId == s.id) _resizedId = null;
    });
    _save();
    // A visszavonás-sáv magától eltűnik (különben az alsó panelt eltakarná,
    // és nem lehetne folytatni a javítást).
    final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: const Text('Lövés törölve'),
      duration: const Duration(seconds: 4),
      persist: false,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 76),
      action: SnackBarAction(
        label: 'Visszavonás',
        onPressed: () {
          setState(() => sheet.shots.insert(idx.clamp(0, sheet.shots.length), s));
          _save();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final views = sheet.views();
    final total = views.fold<int>(0, (a, v) => a + v.score);
    final checks = views.where((v) => v.needsCheck).toList();
    final diff = sheet.shots.length - sheet.expectedShots;
    // Egy lövés körének átméretezése után (amikor a kijelölés elmozdul róla)
    // megkérdezzük, igazítsuk-e hozzá a többi lövést is.
    if (_resizedId != null && _selected != _resizedId && !_askingResize) {
      _askingResize = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askApplyRadius());
    }
    ShotView? sel;
    for (final v in views) {
      if (v.shot.id == _selected) sel = v;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${fmtShortDate(sheet.createdAt)} ${fmtTime(sheet.createdAt)}'),
        actions: [
          if (sheet.geometry != null)
            IconButton(
              tooltip: _showRings ? 'Gyűrűk elrejtése' : 'Gyűrűk megjelenítése',
              isSelected: _showRings || _ringEdit,
              icon: const Icon(Icons.track_changes),
              onPressed: () => setState(() {
                _showRings = !_showRings;
                if (!_showRings) _ringEdit = false;
              }),
            ),
          IconButton(
            tooltip: 'Táblázat és részletek',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => _showDetails(views),
          ),
          PopupMenuButton<String>(
            tooltip: 'További műveletek',
            onSelected: (v) async {
              switch (v) {
                case 'pdf':
                  await shareSheetPdf(context, sheet);
                case 'png':
                  await shareSheetImage(context, sheet);
                case 'shots':
                  await _editExpected();
                case 'delete':
                  await _confirmDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Megosztás PDF-ként'))),
              PopupMenuItem(value: 'png', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Megosztás képként'))),
              PopupMenuItem(value: 'shots', child: ListTile(leading: Icon(Icons.tag), title: Text('Lövésszám módosítása'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Lap törlése'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // fejléc: nagy összpontszám, mellette a lövésszám és a jelzések paneljei
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$total',
                    style: t.textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 0.95,
                        letterSpacing: -2,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('pont', style: t.textTheme.titleLarge?.copyWith(color: kTaupe)),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Panel(
                      color: diff != 0
                          ? kCoral
                          : sheet.irregular
                              ? kYellow
                              : kTaupe,
                      radius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('${sheet.shots.length} / ${sheet.expectedShots} lövés',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (checks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Panel(
                        color: kYellow,
                        radius: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text('${checks.length} ellenőrizendő', style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (sheet.geometry == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NoticeCard(
                icon: Icons.warning_amber_outlined,
                text: 'A lapot nem sikerült kalibrálni, ezért a pontokat kézzel kell megadni.',
              ),
            )
          else if (diff < 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NoticeCard(
                icon: Icons.warning_amber_outlined,
                text: '${sheet.shots.length} lövést találtam a megadott ${sheet.expectedShots} helyett. '
                    'Koppints a hiányzó ${-diff} lövés helyére.',
                actionLabel: 'Lövés hozzáadása',
                onAction: () => setState(() => _addMode = true),
              ),
            )
          else if (diff > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NoticeCard(
                icon: Icons.warning_amber_outlined,
                text: '${sheet.shots.length} lövést találtam a megadott ${sheet.expectedShots} helyett. '
                    'Mindet beszámoltam; ha valamelyik nem lövés, jelöld ki és töröld.'
                    '${sheet.irregular ? ' (Nem szabályos: egy lapon ${sheet.regulationShots} lövés a szabályos.)' : ''}',
                actionLabel: 'Mind számít',
                onAction: () {
                  setState(() => sheet.expectedShots = sheet.shots.length);
                  _save();
                },
              ),
            )
          else if (sheet.irregular)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NoticeCard(
                color: kYellow,
                icon: Icons.info_outline,
                text: 'Nem szabályos lap: ${sheet.shots.length} lövés (szabályosan ${sheet.regulationShots}). '
                    'Az eredményt így is kiértékeltem.',
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(child: _buildViewer(views)),
          _buildBottomPanel(sel, checks),
        ],
      ),
    );
  }

  Widget _buildViewer(List<ShotView> views) {
    return LayoutBuilder(builder: (context, box) {
      final fit = _fitScale(box);
      final w = sheet.imageW * fit, h = sheet.imageH * fit;
      final photoPerScreen = 1 / (fit * _viewScale);
      return ClipRect(
        child: Container(
          color: const Color(0xFF0E0A06),
          alignment: Alignment.center,
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 8,
            panEnabled: !_dragging && !_ringEdit,
            child: SizedBox(
              width: w,
              height: h,
              child: Listener(
                onPointerDown: (e) {
                  _pointers++;
                  final p = e.localPosition / fit;
                  if (_ringEdit) {
                    _ringDragLast = _pointers == 1 ? p : null;
                    return;
                  }
                  final hit = _hitShot(p, photoPerScreen);
                  if (hit != null && hit.id == _selected && !_addMode) {
                    setState(() {
                      _dragging = true;
                      _dragStartShot = Offset(hit.x, hit.y) - p;
                    });
                  }
                },
                onPointerMove: (e) {
                  if (_ringEdit) {
                    final last = _ringDragLast;
                    final g = sheet.geometry;
                    if (last == null || g == null || _pointers != 1) return;
                    final p = e.localPosition / fit;
                    _moveRings(p.dx - last.dx, p.dy - last.dy);
                    _ringDragLast = p;
                    return;
                  }
                  if (!_dragging) return;
                  final s = _selectedShot;
                  if (s == null) return;
                  final p = e.localPosition / fit + (_dragStartShot ?? Offset.zero);
                  setState(() {
                    s.x = p.dx.clamp(0, sheet.imageW.toDouble());
                    s.y = p.dy.clamp(0, sheet.imageH.toDouble());
                    s.uncertain = false;
                  });
                },
                onPointerUp: (_) {
                  _pointers = (_pointers - 1).clamp(0, 10);
                  if (_ringEdit && _ringDragLast != null) {
                    _ringDragLast = null;
                    _save();
                  }
                  if (_dragging) {
                    setState(() => _dragging = false);
                    _save();
                  }
                },
                onPointerCancel: (_) {
                  _pointers = (_pointers - 1).clamp(0, 10);
                  _ringDragLast = null;
                  setState(() => _dragging = false);
                },
                child: GestureDetector(
                  onTapUp: (d) {
                    if (_ringEdit) return;
                    final p = d.localPosition / fit;
                    if (_addMode) {
                      _addShotAt(p);
                      return;
                    }
                    final hit = _hitShot(p, photoPerScreen);
                    // Üres helyre koppintás (ha nincs kijelölés): ránagyít oda, ill. visszaáll.
                    if (hit == null && _selected == null) {
                      _toggleZoom(p * fit);
                      return;
                    }
                    setState(() => _selected = hit?.id);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SheetImage(sheet: sheet, fit: BoxFit.fill),
                      CustomPaint(
                        painter: SheetPainter(
                          views: views,
                          imageSize: Size(sheet.imageW.toDouble(), sheet.imageH.toDouble()),
                          pelletRadius: sheet.geometry?.pelletRadiusOrig ?? 10,
                          selectedId: _selected,
                          labelScale: 1 / _viewScale,
                          geometry: sheet.geometry,
                          showRings: _showRings || _ringEdit,
                          // igazítás közben a címkék ne takarják a gyűrűket
                          showLabels: !_ringEdit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildBottomPanel(ShotView? sel, List<ShotView> checks) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.dividerTheme.color ?? t.dividerColor))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: _ringEdit && sheet.geometry != null
              ? _RingEditor(
                  adjusted: sheet.geometry!.adjusted,
                  onMove: (dx, dy) {
                    final px = 0.6 / _viewScale;
                    _moveRings(dx * px, dy * px);
                    _save();
                  },
                  onScale: (f) {
                    final g = sheet.geometry!;
                    setState(() => sheet.geometry = g.withAdjust(scale: (g.adjScale * f).clamp(0.8, 1.25)));
                    _save();
                  },
                  onReset: () {
                    setState(() => sheet.geometry = sheet.geometry!.withAdjust(dx: 0, dy: 0, scale: 1));
                    _save();
                  },
                  onDone: () => setState(() => _ringEdit = false),
                )
              : sel != null
              ? _ShotEditor(
                  view: sel,
                  spec: sheet.spec,
                  onScore: (v) {
                    setState(() => sel.shot.override = v);
                    _save();
                  },
                  onReset: () {
                    setState(() => sel.shot.override = null);
                    _save();
                  },
                  onConfirm: () {
                    setState(() {
                      sel.shot.override = sel.score;
                      _selected = null;
                    });
                    _save();
                  },
                  onRadius: (f) {
                    final base = sheet.geometry?.pelletRadiusOrig ?? 10;
                    final cur = sel.shot.radius ?? base;
                    setState(() {
                      sel.shot.radius = (cur * f).clamp(base * 0.5, base * 2.0);
                      _resizedId = sel.shot.id;
                    });
                    _save();
                  },
                  onDelete: _deleteSelected,
                  onClose: () => setState(() => _selected = null),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        _addMode
                            ? 'Koppints a lövés helyére a fotón.'
                            : _showRings
                                ? 'A narancs vonalak a gyűrűk pontozási szélét mutatják. Ha elcsúsztak, igazítsd őket.'
                                : checks.isNotEmpty
                                ? 'A sárgával jelölt lövéseket nézőkével ellenőrizd. Koppints egy lövésre a javításhoz.'
                                : 'Koppints egy lövésre a javításhoz, vagy üres helyre a nagyításhoz.',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _addMode
                        ? OutlinedButton(onPressed: () => setState(() => _addMode = false), child: const Text('Mégse'))
                        : _showRings
                        ? FilledButton.tonalIcon(
                            onPressed: () => setState(() {
                              _ringEdit = true;
                              _selected = null;
                            }),
                            icon: const Icon(Icons.open_with),
                            label: const Text('Gyűrűk igazítása'),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: () => setState(() {
                              _addMode = true;
                              _selected = null;
                            }),
                            icon: const Icon(Icons.add),
                            label: const Text('Lövés hozzáadása'),
                          ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _askApplyRadius() async {
    final id = _resizedId;
    _resizedId = null;
    Shot? src;
    for (final s in sheet.shots) {
      if (s.id == id) src = s;
    }
    final r = src?.radius;
    final others = sheet.shots.where((s) => s.id != id).length;
    if (src == null || r == null || others == 0 || !mounted) {
      _askingResize = false;
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('A többi lövés körét is igazítsam?'),
        content: Text('A ${sheet.views().firstWhere((v) => v.shot.id == id).index}. lövés körét átállítottad. '
            'A többi $others lövés találati köre is legyen ekkora? A pontok ennek megfelelően újraszámolódnak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Csak ez az egy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mindet igazítsd')),
        ],
      ),
    );
    _askingResize = false;
    if (ok != true || !mounted) return;
    final before = sheet.total;
    setState(() {
      for (final s in sheet.shots) {
        s.radius = r;
      }
    });
    await _save();
    if (!mounted) return;
    final d = sheet.total - before;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(d == 0
              ? 'Minden lövés köre igazítva, az összpontszám nem változott.'
              : 'Minden lövés köre igazítva, az összpontszám ${d > 0 ? '+' : ''}$d ponttal változott.')));
  }

  void _toggleZoom(Offset childPos) {
    const s = 3.0;
    final target = _viewScale > 1.05
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-childPos.dx * (s - 1), -childPos.dy * (s - 1), 0, 1)
          ..scaleByDouble(s, s, 1, 1));
    _zoomTween = Matrix4Tween(begin: _tc.value.clone(), end: target);
    _zoomAnim.forward(from: 0);
  }

  /// A gyűrűk eltolása a fotón mért (dx, dy) képponttal; a pontok azonnal újraszámolódnak.
  void _moveRings(double dx, double dy) {
    final g = sheet.geometry;
    if (g == null) return;
    final (cx, cy) = g.deltaToCanon(dx, dy);
    setState(() => sheet.geometry = g.withAdjust(dx: g.adjDx + cx, dy: g.adjDy + cy));
  }

  Future<void> _editExpected() async {
    var v = sheet.expectedShots;
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Lövésszám a lapon'),
          content: _Stepper(value: v, min: 1, max: 60, onChanged: (n) => set(() => v = n)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
            FilledButton(onPressed: () => Navigator.pop(ctx, v), child: const Text('Mentés')),
          ],
        ),
      ),
    );
    if (res == null || !mounted) return;
    final more = res > sheet.shots.length;
    setState(() => sheet.expectedShots = res);
    await _save();
    // Több lövés kell, mint amennyit találtunk: keressük újra a lapot ennyi lövésre,
    // így az egymásba lőtt lyukakat a nagyobb számhoz bontja szét.
    if (more && sheet.geometry != null && _untouched) await _reanalyze();
  }

  /// Még nincs kézi javítás a lapon (újrakeresés nem ír felül semmit).
  bool get _untouched => sheet.shots.every((s) => s.auto && s.override == null);

  Future<void> _reanalyze() async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await store.imageBytes(sheet);
      if (bytes == null) throw StateError('nincs kép');
      final out = await analyzeInBackground(bytes, store.settings.spec, sheet.expectedShots);
      if (!mounted) return;
      if (out.error == null && out.width == sheet.imageW && out.height == sheet.imageH) {
        final before = sheet.shots.length;
        setState(() {
          sheet.shots = [
            for (final m in out.shots)
              Shot(
                id: newId(),
                x: (m['x'] as num).toDouble(),
                y: (m['y'] as num).toDouble(),
                uncertain: m['uncertain'] as bool? ?? false,
                detectNote: m['note'] as String? ?? '',
                radius: (m['r'] as num?)?.toDouble(),
              )
          ];
          _selected = null;
        });
        await _save();
        final found = sheet.shots.length - before;
        messenger.showSnackBar(SnackBar(
            content: Text(found > 0
                ? 'Újrakeresés: $found további lövést találtam.'
                : 'Újrakeresés: nem találtam több lövést, a hiányzókat koppintással add hozzá.')));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Az újrakeresés nem sikerült, a hiányzó lövéseket koppintással add hozzá.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Törlöd a lapot?'),
        content: const Text('A lap fotója és a lövései véglegesen törlődnek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lap törlése'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final store = StoreScope.of(context);
      Navigator.of(context).pop();
      await store.deleteSheet(sheet);
    }
  }

  void _showDetails(List<ShotView> views) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, sc) => SheetDetails(
          views: views,
          scrollController: sc,
          onPick: (id) {
            Navigator.pop(ctx);
            setState(() => _selected = id);
          },
        ),
      ),
    );
  }
}

class _ShotEditor extends StatelessWidget {
  const _ShotEditor({
    required this.view,
    required this.spec,
    required this.onScore,
    required this.onReset,
    required this.onConfirm,
    required this.onDelete,
    required this.onClose,
    required this.onRadius,
  });
  final ValueChanged<double> onRadius;
  final ShotView view;
  final dynamic spec;
  final ValueChanged<int> onScore;
  final VoidCallback onReset;
  final VoidCallback onConfirm;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final v = view;
    final auto = v.computed?.score;
    final subtitle = v.overridden
        ? 'Kézzel megadva${auto != null ? ' (felismert: $auto)' : ''}'
        : (v.needsCheck ? 'Ellenőrizendő: ${v.note}' : (v.shot.auto ? 'Felismert találat' : 'Kézzel hozzáadva'));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${v.index}. lövés', style: t.textTheme.titleMedium),
            const SizedBox(width: 8),
            Expanded(
              child: Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(color: v.needsCheck ? kCheckColor.withValues(alpha: 1) : t.colorScheme.onSurfaceVariant)),
            ),
            Text('kör', style: t.textTheme.labelMedium?.copyWith(color: kTaupe)),
            IconButton(
                tooltip: 'Kisebb találati kör',
                visualDensity: VisualDensity.compact,
                onPressed: () => onRadius(1 / 1.06),
                icon: const Icon(Icons.zoom_in_map, size: 20)),
            IconButton(
                tooltip: 'Nagyobb találati kör',
                visualDensity: VisualDensity.compact,
                onPressed: () => onRadius(1.06),
                icon: const Icon(Icons.zoom_out_map, size: 20)),
            IconButton(tooltip: 'Kijelölés megszüntetése', onPressed: onClose, icon: const Icon(Icons.close)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Eggyel kevesebb pont',
              onPressed: v.score > 0 ? () => onScore(v.score - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 64,
              child: Text('${v.score}',
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            IconButton.outlined(
              tooltip: 'Eggyel több pont',
              onPressed: v.score < 13 ? () => onScore(v.score + 1) : null,
              icon: const Icon(Icons.add),
            ),
            const Spacer(),
            if (v.overridden)
              TextButton(onPressed: onReset, child: const Text('Visszaállítás'))
            else if (v.needsCheck)
              TextButton(onPressed: onConfirm, child: const Text('Rendben')),
            IconButton(
              tooltip: 'Lövés törlése',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: t.colorScheme.error),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});
  final int value, min, max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(
          tooltip: 'Kevesebb', onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
      SizedBox(
          width: 64,
          child: Text('$value', textAlign: TextAlign.center, style: t.textTheme.headlineSmall)),
      IconButton.outlined(
          tooltip: 'Több', onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
    ]);
  }
}

/// Táblázat: körönkénti eloszlás, legjobb/leggyengébb lövés, ellenőrizendők.
class SheetDetails extends StatelessWidget {
  const SheetDetails({super.key, required this.views, this.scrollController, this.onPick});
  final List<ShotView> views;
  final ScrollController? scrollController;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dist = ringDistribution(views);
    final sorted = [...views]..sort((a, b) => b.score.compareTo(a.score));
    final checks = views.where((v) => v.needsCheck).toList();
    final total = views.fold<int>(0, (a, v) => a + v.score);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Részletek', style: t.textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatTile(label: 'Összesen', value: '$total', color: kOrange)),
          const SizedBox(width: 8),
          Expanded(
              child: StatTile(
                  label: 'Átlag / lövés', value: views.isEmpty ? '–' : fmtNum(total / views.length, 2), color: kYellow)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Legjobb lövés',
                  value: sorted.isEmpty ? '–' : '${sorted.first.score}',
                  sub: sorted.isEmpty ? null : '${sorted.first.index}. lövés',
                  color: kCream)),
          const SizedBox(width: 8),
          Expanded(
              child: StatTile(
                  label: 'Leggyengébb lövés',
                  value: sorted.isEmpty ? '–' : '${sorted.last.score}',
                  sub: sorted.isEmpty ? null : '${sorted.last.index}. lövés',
                  color: kTaupe)),
        ]),
        const SectionHeader('Lövések gyűrűnként'),
        Card(
          child: Column(children: [
            for (var i = 0; i < dist.length; i++) ...[
              if (i > 0) const Divider(),
              ListTile(
                dense: true,
                title: Text('${dist[i].score} pont'),
                trailing: Text('${dist[i].count} lövés',
                    style: t.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
            if (dist.isEmpty) const ListTile(title: Text('Nincs lövés a lapon.')),
          ]),
        ),
        if (checks.isNotEmpty) ...[
          const SectionHeader('Nézőkével ellenőrizendő'),
          Card(
            child: Column(children: [
              for (var i = 0; i < checks.length; i++) ...[
                if (i > 0) const Divider(),
                ListTile(
                  dense: true,
                  leading: Text('${checks[i].index}.', style: t.textTheme.titleSmall),
                  title: Text('${checks[i].score} pont'),
                  subtitle: Text(checks[i].note),
                  trailing: onPick == null ? null : const Icon(Icons.chevron_right),
                  onTap: onPick == null ? null : () => onPick!(checks[i].shot.id),
                ),
              ],
            ]),
          ),
        ],
        const SectionHeader('Minden lövés'),
        Card(
          child: Column(children: [
            for (var i = 0; i < views.length; i++) ...[
              if (i > 0) const Divider(),
              ListTile(
                dense: true,
                leading: Text('${views[i].index}.', style: t.textTheme.titleSmall),
                title: Text('${views[i].score} pont${views[i].overridden ? ' (kézzel)' : ''}'),
                subtitle: views[i].computed == null
                    ? null
                    : Text('${fmtNum(views[i].computed!.dxMm.abs(), 0)} mm ${views[i].computed!.dxMm >= 0 ? 'jobbra' : 'balra'}, '
                        '${fmtNum(views[i].computed!.dyMm.abs(), 0)} mm ${views[i].computed!.dyMm >= 0 ? 'fent' : 'lent'}'),
                onTap: onPick == null ? null : () => onPick!(views[i].shot.id),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

/// A tábla gyűrűinek kézi igazítása: eltolás nyilakkal (vagy húzással a fotón) és méretezés.
class _RingEditor extends StatelessWidget {
  const _RingEditor({
    required this.adjusted,
    required this.onMove,
    required this.onScale,
    required this.onReset,
    required this.onDone,
  });
  final bool adjusted;
  final void Function(double dx, double dy) onMove;
  final ValueChanged<double> onScale;
  final VoidCallback onReset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget arrow(IconData i, String tip, double dx, double dy) => IconButton.outlined(
        tooltip: tip, visualDensity: VisualDensity.compact, onPressed: () => onMove(dx, dy), icon: Icon(i, size: 20));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('Húzd a gyűrűket a helyükre a fotón, vagy használd a gombokat. A pontok azonnal frissülnek.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          if (adjusted) TextButton(onPressed: onReset, child: const Text('Visszaállítás')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          arrow(Icons.arrow_back, 'Balra', -1, 0),
          arrow(Icons.arrow_upward, 'Fel', 0, -1),
          arrow(Icons.arrow_downward, 'Le', 0, 1),
          arrow(Icons.arrow_forward, 'Jobbra', 1, 0),
          const SizedBox(width: 8),
          IconButton.outlined(
              tooltip: 'Gyűrűk kicsinyítése',
              visualDensity: VisualDensity.compact,
              onPressed: () => onScale(1 / 1.003),
              icon: const Icon(Icons.zoom_in_map, size: 20)),
          IconButton.outlined(
              tooltip: 'Gyűrűk nagyítása',
              visualDensity: VisualDensity.compact,
              onPressed: () => onScale(1.003),
              icon: const Icon(Icons.zoom_out_map, size: 20)),
          const Spacer(),
          FilledButton(onPressed: onDone, child: const Text('Kész')),
        ]),
      ],
    );
  }
}
