
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/stats.dart';
import '../data/store.dart';
import '../services/export.dart';
import 'new_sheet.dart';
import 'sheet_screen.dart';
import 'stats_screen.dart';
import 'widgets.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final s = session;
    if (!store.sessions.contains(s)) {
      // törölték közben
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    final sheets = [...s.sheets]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final best = sheets.isEmpty ? null : sheets.map((e) => e.total).reduce((a, b) => a > b ? a : b);
    final offsets = [for (final sh in sheets) ...shotOffsets(sh)];
    final group = groupStats(offsets);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title.isNotEmpty ? s.title : fmtDate(s.date)),
        actions: [
          IconButton(
            tooltip: 'Edzés megosztása PDF-ként',
            icon: const Icon(Icons.ios_share),
            onPressed: sheets.isEmpty ? null : () => shareSessionPdf(context, s),
          ),
          PopupMenuButton<String>(
            tooltip: 'További műveletek',
            onSelected: (v) {
              if (v == 'rename') _rename(context, store);
              if (v == 'delete') _delete(context, store);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edzés elnevezése'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Edzés törlése'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startNewSheet(context, session: s),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Lap hozzáadása'),
      ),
      body: sheets.isEmpty
          ? EmptyState(
              icon: Icons.track_changes,
              title: 'Ebben az edzésben még nincs lap',
              body: 'Adj hozzá lapokat, és az edzés összesített eredménye itt jelenik meg.',
              actionLabel: 'Lap hozzáadása',
              actionIcon: Icons.photo_camera_outlined,
              onAction: () => startNewSheet(context, session: s),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                StatGrid(children: [
                    StatTile(label: 'Összesen', value: '${s.total}', sub: '${sheets.length} lap, ${s.shotCount} lövés'),
                    StatTile(label: 'Átlag / lap', value: fmtNum(s.averagePerSheet)),
                    StatTile(label: 'Legjobb lap', value: '${best ?? '–'}'),
                    StatTile(label: 'Átlag / lövés', value: fmtNum(s.averagePerShot, 2)),
                  ],
                ),
                if (group != null && group.n >= 3) ...[
                  const SectionHeader('Találati kép'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(width: 120, height: 120, child: TargetDiagram(points: offsets, group: group, spec: sheets.first.spec)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(group.describe(), style: t.textTheme.bodyLarge),
                                const SizedBox(height: 6),
                                Text('Szórás: átlagosan ${fmtNum(group.spread, 0)} mm a csoport közepétől, '
                                    'legnagyobb távolság ${fmtNum(group.maxSpread, 0)} mm.',
                                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SectionHeader('Lapok'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < sheets.length; i++) ...[
                        if (i > 0) const Divider(),
                        _SheetRow(index: i + 1, sheet: sheets[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _rename(BuildContext context, AppStore store) async {
    final ctrl = TextEditingController(text: session.title);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edzés neve'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Név', helperText: 'Üresen hagyva a dátum látszik: ${fmtDate(session.date)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Mentés')),
        ],
      ),
    );
    if (res != null) {
      session.title = res;
      await store.changed();
    }
  }

  Future<void> _delete(BuildContext context, AppStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Törlöd az edzést?'),
        content: Text('Az edzés ${session.sheets.length} lapja és a fotók véglegesen törlődnek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Edzés törlése'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      await store.deleteSession(session);
    }
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.index, required this.sheet});
  final int index;
  final Sheet sheet;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final views = sheet.views();
    final checks = views.where((v) => v.needsCheck).length;
    final mismatch = sheet.shots.length != sheet.expectedShots;
    final sub = [
      '${fmtTime(sheet.createdAt)} · ${sheet.shots.length} lövés',
      if (mismatch) '${sheet.expectedShots} helyett',
      if (sheet.irregular) 'nem szabályos',
      if (checks > 0) '$checks ellenőrizendő',
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 48, height: 48, child: SheetImage(sheet: sheet, cacheWidth: 144)),
      ),
      title: Text('$index. lap'),
      subtitle: Text(sub),
      trailing: Text('${sheet.total}',
          style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SheetScreen(sheet: sheet))),
    );
  }
}
