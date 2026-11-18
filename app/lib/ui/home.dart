import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/store.dart';
import 'new_sheet.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const SessionsPage(), const StatsScreen(), const SettingsScreen()];
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: pages)),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => startNewSheet(context),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Lap fotózása'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Edzések'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Statisztika'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Beállítások'),
        ],
      ),
    );
  }
}

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Edzések'),
          pinned: true,
          actions: [
            IconButton(
              tooltip: 'Kép választása a galériából',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => startNewSheet(context, source: SheetSource.gallery),
            ),
          ],
        ),
        if (store.sessions.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.track_changes,
              title: 'Még nincs kiértékelt lap',
              body: 'Fotózd le a lelőtt lapot: az app megkeresi a találatokat, kiszámolja a pontszámot, '
                  'és az edzéseid eredményét itt gyűjti össze.',
              actionLabel: 'Lap fotózása',
              actionIcon: Icons.photo_camera_outlined,
              onAction: () => startNewSheet(context),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: store.sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _SessionCard(session: store.sessions[i]),
            ),
          ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = session;
    final title = s.title.isNotEmpty ? s.title : fmtDate(s.date);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(session: s))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Thumbs(sheets: s.sheets),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${s.sheets.length} lap · ${s.shotCount} lövés · átlag ${fmtNum(s.averagePerSheet)}/lap',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s.total}',
                      style: t.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('pont', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbs extends StatelessWidget {
  const _Thumbs({required this.sheets});
  final List<Sheet> sheets;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = sheets.isEmpty ? null : sheets.last;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        color: t.colorScheme.surfaceContainerHighest,
        child: first == null
            ? Icon(Icons.image_outlined, color: t.colorScheme.onSurfaceVariant)
            : Image.file(File(first.imagePath), fit: BoxFit.cover, cacheWidth: 168,
                errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: t.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}
