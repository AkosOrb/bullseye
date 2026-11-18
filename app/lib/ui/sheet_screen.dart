// Egy lap eredménye: jelölt fotó, fejléc, kézi javítás, táblázat.

import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/stats.dart';
import '../data/store.dart';
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

class _SheetScreenState extends State<SheetScreen> {
  final _tc = TransformationController();
  String? _selected;
  bool _addMode = false;
  bool _dragging = false;
  Offset? _dragStartShot;

  Sheet get sheet => widget.sheet;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
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
    });
    _save();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Lövés törölve'),
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
    ShotView? sel;
    for (final v in views) {
      if (v.shot.id == _selected) sel = v;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${fmtShortDate(sheet.createdAt)} ${fmtTime(sheet.createdAt)}'),
        actions: [
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
                      color: sheet.shots.length == sheet.expectedShots ? kTaupe : kCoral,
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
          else if (diff != 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NoticeCard(
                icon: Icons.warning_amber_outlined,
                text: diff < 0
                    ? '${sheet.shots.length} lövést találtam a megadott ${sheet.expectedShots} helyett. '
                        'Koppints a hiányzó ${-diff} lövés helyére.'
                    : '${sheet.shots.length} lövést találtam a megadott ${sheet.expectedShots} helyett. '
                        'Jelöld ki és töröld a felesleges $diff lövést.',
                actionLabel: diff < 0 ? 'Lövés hozzáadása' : null,
                onAction: diff < 0 ? () => setState(() => _addMode = true) : null,
              ),
            ),
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
            panEnabled: !_dragging,
            child: SizedBox(
              width: w,
              height: h,
              child: Listener(
                onPointerDown: (e) {
                  final p = e.localPosition / fit;
                  final hit = _hitShot(p, photoPerScreen);
                  if (hit != null && hit.id == _selected && !_addMode) {
                    setState(() {
                      _dragging = true;
                      _dragStartShot = Offset(hit.x, hit.y) - p;
                    });
                  }
                },
                onPointerMove: (e) {
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
                  if (_dragging) {
                    setState(() => _dragging = false);
                    _save();
                  }
                },
                onPointerCancel: (_) => setState(() => _dragging = false),
                child: GestureDetector(
                  onTapUp: (d) {
                    final p = d.localPosition / fit;
                    if (_addMode) {
                      _addShotAt(p);
                      return;
                    }
                    final hit = _hitShot(p, photoPerScreen);
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
          child: sel != null
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
                  onDelete: _deleteSelected,
                  onClose: () => setState(() => _selected = null),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        _addMode
                            ? 'Koppints a lövés helyére a fotón.'
                            : checks.isNotEmpty
                                ? 'A sárgával jelölt lövéseket nézőkével ellenőrizd. Koppints egy lövésre a javításhoz.'
                                : 'Koppints egy lövésre a javításhoz. Kijelölés után húzással mozgatható.',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _addMode
                        ? OutlinedButton(onPressed: () => setState(() => _addMode = false), child: const Text('Mégse'))
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
    if (res != null) {
      setState(() => sheet.expectedShots = res);
      _save();
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
  });
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
